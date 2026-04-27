#!/usr/bin/env bash
# preflight-check.sh — Verify the host is ready for a Qubentoo dom0 build.
#
# Runs a series of hardware, kernel, and firmware checks before you attempt
# bootstrap-dom0.sh.  All failures are collected and reported together; the
# script exits non-zero only when a hard requirement is missing.
# Warnings do not cause a non-zero exit — read them anyway.
#
# Usage:
#   bash scripts/preflight-check.sh [--json]   (--json: machine-readable output)

set -uo pipefail

# --- output helpers ----------------------------------------------------

USE_JSON=0
[[ "${1:-}" == "--json" ]] && USE_JSON=1

declare -a ERRORS=()
declare -a WARNINGS=()
declare -a PASSES=()

_pass()  { PASSES+=("$*");   printf '\e[1;32m[PASS]\e[0m  %s\n' "$*"; }
_warn()  { WARNINGS+=("$*"); printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
_fail()  { ERRORS+=("$*");   printf '\e[1;31m[FAIL]\e[0m  %s\n' "$*"; }
_info()  {                   printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
_head()  {                   printf '\n\e[1;37m=== %s ===\e[0m\n' "$*"; }

# --- helpers -----------------------------------------------------------

kernel_config_val() {
	# Returns the value of a kernel config option.
	# Checks /proc/config.gz, /boot/config-$(uname -r), or /boot/config.
	local key="$1"
	local cfg

	if [[ -f /proc/config.gz ]]; then
		zcat /proc/config.gz 2>/dev/null | grep -E "^${key}=" | cut -d= -f2
		return
	fi
	for cfg in "/boot/config-$(uname -r)" /boot/config; do
		if [[ -f "${cfg}" ]]; then
			grep -E "^${key}=" "${cfg}" 2>/dev/null | cut -d= -f2
			return
		fi
	done
	echo "UNKNOWN"
}

kernel_config_is() {
	# Returns 0 if config key equals expected value
	[[ "$(kernel_config_val "$1")" == "$2" ]]
}

# --- check 1: CPU virtualisation extension ----------------------------

_head "CPU Virtualisation"

if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo 2>/dev/null; then
	virt_type=$(grep -oE '\b(vmx|svm)\b' /proc/cpuinfo | head -1)
	if [[ "${virt_type}" == "vmx" ]]; then
		_pass "Intel VT-x (vmx) detected"
	else
		_pass "AMD-V (svm) detected"
	fi
else
	_fail "No virtualisation extension found in /proc/cpuinfo (no vmx/svm)"
	_fail "       Xen dom0 requires hardware virtualisation. Enable VT-x/AMD-V in BIOS."
fi

# Check if we are already inside a VM (nested virt warning)
if systemd-detect-virt --quiet 2>/dev/null || \
   grep -qE '\bhypervisor\b' /proc/cpuinfo 2>/dev/null; then
	_warn "Running inside a hypervisor — nested Xen dom0 is NOT supported for production"
	_warn "       This is fine for testing the emerge sequence (bootstrap dry-run only)"
fi

# --- check 2: IOMMU ---------------------------------------------------

_head "IOMMU (VT-d / AMD-Vi)"

iommu_found=0
if dmesg 2>/dev/null | grep -qiE '(DMAR|IOMMU).*enabled|AMD-Vi.*enabled'; then
	_pass "IOMMU reported as enabled in dmesg"
	iommu_found=1
elif dmesg 2>/dev/null | grep -qiE 'DMAR|AMD-Vi|IOMMU'; then
	_warn "IOMMU hardware found in dmesg but may not be enabled"
	_warn "       Add 'intel_iommu=on' or 'amd_iommu=on' to kernel cmdline"
	iommu_found=1
else
	_warn "No IOMMU messages found in dmesg — either not present or boot messages rolled off"
	_warn "       Run: dmesg | grep -i iommu"
	_warn "       Xen requires IOMMU for secure PCI passthrough (dom0 works without it)"
fi

if kernel_config_is CONFIG_INTEL_IOMMU y; then
	_pass "CONFIG_INTEL_IOMMU=y"
elif kernel_config_is CONFIG_AMD_IOMMU y; then
	_pass "CONFIG_AMD_IOMMU=y"
else
	_warn "CONFIG_INTEL_IOMMU and CONFIG_AMD_IOMMU are not =y in running kernel"
	_warn "       The Qubentoo dom0 kernel config enables both — rebuild after bootstrap"
fi

# --- check 3: Xen dom0 kernel support ---------------------------------

_head "Xen dom0 Kernel Support"

xen_val=$(kernel_config_val CONFIG_XEN)
dom0_val=$(kernel_config_val CONFIG_XEN_DOM0)

case "${xen_val}" in
	y)
		_pass "CONFIG_XEN=y (built-in)"
		;;
	m)
		_fail "CONFIG_XEN=m — Xen support is a module; dom0 requires it built-in (=y)"
		;;
	UNKNOWN)
		_warn "Cannot determine CONFIG_XEN — no /proc/config.gz or /boot/config found"
		_warn "       Enable CONFIG_IKCONFIG_PROC=y in your kernel to expose /proc/config.gz"
		;;
	*)
		_fail "CONFIG_XEN is not set — this kernel has no Xen support at all"
		;;
esac

case "${dom0_val}" in
	y)
		_pass "CONFIG_XEN_DOM0=y (built-in)"
		;;
	m)
		_fail "CONFIG_XEN_DOM0=m — dom0 support must be built-in (=y), not a module"
		;;
	UNKNOWN)
		_warn "Cannot determine CONFIG_XEN_DOM0"
		;;
	*)
		_fail "CONFIG_XEN_DOM0 is not set"
		;;
esac

# Xen pvcalls: known breakage with 4.17 + Linux 6.6
pvcalls_val=$(kernel_config_val CONFIG_XEN_PVCALLS_FRONTEND)
if [[ "${pvcalls_val}" == "y" ]] || [[ "${pvcalls_val}" == "m" ]]; then
	_warn "CONFIG_XEN_PVCALLS_FRONTEND=${pvcalls_val}"
	_warn "       Xen 4.17 + Linux 6.6: PVCALLS_FRONTEND causes boot hangs in dom0"
	_warn "       Set CONFIG_XEN_PVCALLS_FRONTEND=n in your kernel config"
fi

# Hardened security options
for opt in \
	CONFIG_HARDENED_USERCOPY:y \
	CONFIG_FORTIFY_SOURCE:y \
	CONFIG_CC_STACKPROTECTOR_STRONG:y \
	CONFIG_RANDOMIZE_BASE:y \
	CONFIG_PAGE_TABLE_ISOLATION:y \
	CONFIG_RETPOLINE:y \
	CONFIG_MODULE_SIG:y; do
	key="${opt%%:*}"
	want="${opt##*:}"
	val=$(kernel_config_val "${key}")
	if [[ "${val}" == "${want}" ]]; then
		_pass "${key}=${val}"
	else
		_warn "${key}=${val:-unset}  (expected ${want} for hardened dom0)"
	fi
done

# Must NOT be set
if kernel_config_is CONFIG_MODULE_FORCE_UNLOAD y; then
	_fail "CONFIG_MODULE_FORCE_UNLOAD=y — must be unset per Qubentoo constraints"
else
	_pass "CONFIG_MODULE_FORCE_UNLOAD is not set"
fi

# --- check 4: /boot/xen*.gz -------------------------------------------

_head "Xen Bootloader Image"

xen_gz=$(find /boot -maxdepth 2 \( -name "xen*.gz" -o -name "xen-*.gz" \) 2>/dev/null | sort -V | tail -1)
if [[ -n "${xen_gz}" ]]; then
	_pass "Found Xen image: ${xen_gz}"
else
	_fail "No xen*.gz found under /boot"
	_fail "       After emerging app-emulation/xen, copy:"
	_fail "       /usr/lib/xen/boot/xen.gz → /boot/xen-4.17.5.gz"
fi

# GRUB config check
if [[ -f /boot/grub/grub.cfg ]]; then
	if grep -q "multiboot\|xen" /boot/grub/grub.cfg 2>/dev/null; then
		_pass "grub.cfg contains Xen multiboot entry"
	else
		_warn "grub.cfg exists but has no Xen multiboot entry"
		_warn "       Run: grub-mkconfig -o /boot/grub/grub.cfg  (after installing Xen)"
	fi
else
	_warn "/boot/grub/grub.cfg not found — GRUB not yet configured"
fi

# --- check 5: EFI detection + documentation ---------------------------

_head "EFI vs BIOS"

if [[ -d /sys/firmware/efi ]]; then
	_warn "EFI boot detected"
	_warn ""
	_warn "  Xen on EFI requires a specific GRUB configuration."
	_warn "  Standard 'grub-install --target=x86_64-efi' installs GRUB as an EFI app."
	_warn "  Xen itself must also be installed as an EFI binary (xen.efi):"
	_warn ""
	_warn "    1. Copy /usr/lib/xen/boot/xen.efi to /boot/efi/EFI/qubentoo/xen.efi"
	_warn "    2. In /etc/default/grub set:"
	_warn "         GRUB_CMDLINE_XEN_DEFAULT=\"dom0_mem=4096M,max:4096M iommu=on\""
	_warn "    3. grub-mkconfig uses the 'xen' platform in GRUB_PLATFORMS."
	_warn "       Ensure 'xen' and 'efi-64' are both in GRUB_PLATFORMS in make.conf."
	_warn ""
	_warn "  BIOS systems: grub-install --target=i386-pc uses multiboot2 directly."
	_warn "  EFI systems: GRUB chainloads xen.efi, which then loads the Linux kernel."
	_warn "  The kernel and initramfs are passed as Xen 'modules', not as GRUB kernels."
	_warn ""
	_warn "  Reference: https://wiki.gentoo.org/wiki/Xen#UEFI"

	efi_xen=$(find /boot/efi -name "xen.efi" 2>/dev/null | head -1)
	if [[ -n "${efi_xen}" ]]; then
		_pass "xen.efi found at: ${efi_xen}"
	else
		_warn "xen.efi not found under /boot/efi — Xen EFI binary not yet installed"
	fi
else
	_pass "BIOS/legacy boot — standard GRUB multiboot2 applies"
fi

# --- check 5b: Apple hardware specific checks -------------------------

_head "Apple Hardware"

APPLE_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
APPLE_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ "${APPLE_VENDOR}" == "Apple Inc." ]]; then
	_pass "Apple hardware detected: ${APPLE_PRODUCT}"

	# VT-d on Apple: Haswell (2013) exposes VT-d but may need intel_iommu=on
	if dmesg 2>/dev/null | grep -qi "DMAR.*IOMMU\|Intel.*IOMMU"; then
		_pass "Intel VT-d (DMAR) visible in dmesg — IOMMU should work"
	else
		_warn "Apple EFI may require 'intel_iommu=on' in kernel cmdline to activate VT-d"
		_warn "       bootstrap-dom0.sh adds this automatically on Apple hardware"
	fi

	# BCM4360 WiFi check
	if lspci 2>/dev/null | grep -q "BCM4360\|BCM43602\|BCM4352"; then
		bcm_dev=$(lspci | grep -E "BCM4360|BCM43602|BCM4352" | head -1)
		_warn "Broadcom WiFi found: ${bcm_dev}"
		_warn "       Needs net-wireless/broadcom-sta (wl driver) for full support"
		_warn "       bootstrap-dom0.sh emerges this automatically on Apple hardware"
		if modinfo wl >/dev/null 2>&1; then
			_pass "broadcom-sta (wl) module is installed"
		else
			_warn "wl module not yet installed — will be emerged during bootstrap"
		fi
	else
		_warn "No Broadcom BCM4360/4352 detected via lspci (may not be loaded yet)"
	fi

	# xen.efi check for Apple EFI
	if [[ -d /sys/firmware/efi ]]; then
		xen_efi=$(find /boot/efi -name "BOOTx64.EFI" -o -name "xen.efi" 2>/dev/null | head -1)
		if [[ -n "${xen_efi}" ]]; then
			_pass "Xen EFI binary present: ${xen_efi}"
		else
			_warn "xen.efi not yet installed as EFI fallback"
			_warn "       Run scripts/apple-efi-setup.sh after bootstrap to set this up"
		fi
		xen_cfg=$(find /boot/efi -name "xen.cfg" 2>/dev/null | head -1)
		if [[ -n "${xen_cfg}" ]]; then
			_pass "xen.cfg found: ${xen_cfg}"
		else
			_warn "xen.cfg not found — apple-efi-setup.sh will create it"
		fi
	fi

	# Apple kernel config supplement
	APPLE_CFG_PATH=""
	for p in \
		"$(dirname "$0")/../hardware/macbook-air-2013/kernel.config" \
		"/root/qubentoo-overlay/hardware/macbook-air-2013/kernel.config" \
		"/var/db/repos/qubentoo/hardware/macbook-air-2013/kernel.config"; do
		[[ -f "${p}" ]] && APPLE_CFG_PATH="${p}" && break
	done
	if [[ -n "${APPLE_CFG_PATH}" ]]; then
		_pass "Apple kernel config supplement found: ${APPLE_CFG_PATH}"
	else
		_warn "Apple kernel config supplement not found"
		_warn "       Expected: kernel/qubentoo-apple-mba2013.config in overlay"
	fi

	# applesmc driver (fan / temperature / backlight)
	if modinfo applesmc >/dev/null 2>&1 || lsmod 2>/dev/null | grep -q applesmc; then
		_pass "applesmc module present (fan/backlight control)"
	else
		_warn "applesmc not loaded — fan/backlight won't work until after kernel build"
	fi

else
	_info "Not Apple hardware (${APPLE_VENDOR:-unknown vendor}) — skipping Apple checks"
fi

# --- check 6: Portage and overlay health ------------------------------

_head "Portage and Overlay"

if command -v emerge >/dev/null 2>&1; then
	_pass "emerge found: $(emerge --version 2>/dev/null | head -1)"
else
	_fail "emerge not found — is this a Gentoo system?"
fi

if command -v eselect >/dev/null 2>&1; then
	if eselect repository list 2>/dev/null | grep -q "qubentoo"; then
		_pass "qubentoo overlay registered in eselect repository"
	else
		_warn "qubentoo overlay not found in eselect repository"
		_warn "       Run: eselect repository create qubentoo /path/to/qubentoo-overlay"
	fi
else
	_warn "eselect not found — cannot check overlay status"
fi

# Python version
if command -v python3 >/dev/null 2>&1; then
	py_ver=$(python3 --version 2>&1 | grep -oP '\d+\.\d+')
	case "${py_ver}" in
		3.10|3.11|3.12)
			_pass "Python ${py_ver} — supported by PYTHON_COMPAT"
			;;
		*)
			_warn "Python ${py_ver} — not in PYTHON_COMPAT=(python3_{10,11,12})"
			_warn "       Qubes Python packages may not build"
			;;
	esac
fi

# --- check 7: disk space ----------------------------------------------

_head "Disk Space"

boot_free=$(df -m /boot 2>/dev/null | awk 'NR==2{print $4}')
root_free=$(df -g / 2>/dev/null | awk 'NR==2{print $4}' || df -m / | awk 'NR==2{print int($4/1024)}')

if [[ -n "${boot_free}" ]] && (( boot_free < 200 )); then
	_fail "/boot has only ${boot_free} MiB free — need ≥200 MiB for Xen + kernel + initramfs"
elif [[ -n "${boot_free}" ]]; then
	_pass "/boot has ${boot_free} MiB free"
fi

root_free_mb=$(df -m / 2>/dev/null | awk 'NR==2{print $4}')
if [[ -n "${root_free_mb}" ]] && (( root_free_mb < 20480 )); then
	_warn "/ has $((root_free_mb / 1024)) GiB free — Xen + Qubes build recommends ≥20 GiB"
else
	_pass "/ has $((${root_free_mb:-0} / 1024)) GiB free"
fi

# --- summary ----------------------------------------------------------

echo ""
printf '\e[1;37m%s\e[0m\n' "=========================================="
printf '\e[1;37m%s\e[0m\n' "  PREFLIGHT SUMMARY"
printf '\e[1;37m%s\e[0m\n' "=========================================="
printf '\e[1;32m  PASS : %d\e[0m\n'    "${#PASSES[@]}"
printf '\e[1;33m  WARN : %d\e[0m\n'    "${#WARNINGS[@]}"
printf '\e[1;31m  FAIL : %d\e[0m\n'    "${#ERRORS[@]}"
echo ""

if (( ${#ERRORS[@]} > 0 )); then
	printf '\e[1;31mBLOCKERS:\e[0m\n'
	for e in "${ERRORS[@]}"; do printf '  ✗ %s\n' "${e}"; done
	echo ""
	printf '\e[1;31mVERDICT: NOT READY — resolve the blockers above before bootstrapping.\e[0m\n'
	EXIT_CODE=1
else
	printf '\e[1;32mVERDICT: READY — no hard blockers. Review warnings before proceeding.\e[0m\n'
	EXIT_CODE=0
fi

# --- JSON output -------------------------------------------------------

if (( USE_JSON )); then
	python3 - << PYEOF
import json, sys
data = {
    "verdict": "READY" if ${#ERRORS[@]} == 0 else "NOT_READY",
    "passes":   ${#PASSES[@]},
    "warnings": ${#WARNINGS[@]},
    "errors":   ${#ERRORS[@]},
    "error_list":   $(printf '%s\n' "${ERRORS[@]+"${ERRORS[@]}"}" | python3 -c "import sys,json; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))"),
    "warning_list": $(printf '%s\n' "${WARNINGS[@]+"${WARNINGS[@]}"}" | python3 -c "import sys,json; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))")
}
print(json.dumps(data, indent=2))
PYEOF
fi

exit ${EXIT_CODE}
