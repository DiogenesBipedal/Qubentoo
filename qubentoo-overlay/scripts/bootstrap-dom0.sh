#!/usr/bin/env bash
# bootstrap-dom0.sh — Qubentoo dom0 bootstrap
#
# Assumes: booted Gentoo stage3 (hardened/amd64 profile), network up,
#          /etc/resolv.conf populated, portage installed.
#
# Idempotent: safe to re-run; each step checks whether it has already run.

set -euo pipefail
IFS=$'\n\t'

# --- helpers -----------------------------------------------------------

info()  { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()    { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
die()   { printf '\e[1;31m[FAIL]\e[0m  %s\n' "$*" >&2; exit 1; }

require_root() {
	[[ ${EUID} -eq 0 ]] || die "Must be run as root."
}

require_root

# --- configurable variables (override via env) -------------------------

OVERLAY_DIR="${OVERLAY_DIR:-/var/db/repos/qubentoo}"
OVERLAY_SRC="${OVERLAY_SRC:-/root/qubentoo-overlay}"   # local clone
GENTOO_PROFILE="${GENTOO_PROFILE:-default/linux/amd64/23.0/hardened}"
GRUB_DISK="${GRUB_DISK:-/dev/sda}"
KERNEL_SRC="${KERNEL_SRC:-/usr/src/linux}"
XEN_VERSION="${XEN_VERSION:-4.17.5}"
DOM0_MEM_MB="${DOM0_MEM_MB:-4096}"

# --- step 0: sanity checks ---------------------------------------------

info "Checking prerequisites..."
for cmd in emerge eselect portageq; do
	command -v "${cmd}" >/dev/null 2>&1 || die "${cmd} not found — is this a Gentoo stage3?"
done
ok "Prerequisites satisfied"

# --- step 1: select hardened profile -----------------------------------

info "Setting Gentoo profile to ${GENTOO_PROFILE}..."
current_profile=$(eselect profile show 2>/dev/null | awk 'NR==2{print $1}' | xargs basename 2>/dev/null || true)
if [[ "${current_profile}" != *hardened* ]]; then
	eselect profile set "${GENTOO_PROFILE}" || die "Failed to set profile"
	ok "Profile set to ${GENTOO_PROFILE}"
else
	ok "Profile already hardened (${current_profile})"
fi

# --- step 2: install eselect-repository --------------------------------

info "Ensuring eselect-repository is installed..."
if ! portageq has_version / app-eselect/eselect-repository; then
	emerge --quiet --noreplace app-eselect/eselect-repository dev-vcs/git \
		|| die "Failed to install eselect-repository"
fi
ok "eselect-repository present"

# --- step 3: add qubentoo overlay ---------------------------------------

info "Registering qubentoo overlay..."
if ! eselect repository list | grep -q "qubentoo"; then
	# If we have a local source, register it directly; otherwise use a URI
	if [[ -d "${OVERLAY_SRC}" ]]; then
		eselect repository create qubentoo "${OVERLAY_SRC}" \
			|| die "Failed to create qubentoo overlay entry"
	else
		# Placeholder URI — replace with actual git remote when published
		eselect repository add qubentoo git \
			"https://github.com/qubentoo/qubentoo-overlay.git" \
			|| die "Failed to add qubentoo overlay"
		emaint sync -r qubentoo || die "Failed to sync qubentoo overlay"
	fi
	ok "qubentoo overlay registered"
else
	ok "qubentoo overlay already registered"
fi

# Sync to ensure manifests are current
emaint sync -r qubentoo 2>/dev/null || true

# --- step 4: write /etc/portage/make.conf dom0 additions ---------------

MAKE_CONF="/etc/portage/make.conf"
info "Configuring ${MAKE_CONF}..."

# Only write the Qubentoo block once
if ! grep -q "# qubentoo-dom0" "${MAKE_CONF}" 2>/dev/null; then
	cat >> "${MAKE_CONF}" << 'EOF'

# qubentoo-dom0 — appended by bootstrap-dom0.sh
USE="hardened openrc -systemd xen pam python dbus \
     policykit pie ssp caps ssl gnutls curl \
     X jpeg png svg \
     -kde -gnome -pulseaudio"

GRUB_PLATFORMS="xen xen-32 pc"

PYTHON_SINGLE_TARGET="python3_11"
PYTHON_TARGETS="python3_11"

ABI_X86="64"

CFLAGS="-O2 -pipe -march=native -fstack-protector-strong -D_FORTIFY_SOURCE=2"
CXXFLAGS="${CFLAGS}"
LDFLAGS="-Wl,-z,relro,-z,now"

# Parallelism — adjust to CPU count
MAKEOPTS="-j$(nproc) -l$(nproc)"
EMERGE_DEFAULT_OPTS="--jobs=$(nproc) --load-average=$(nproc)"
EOF
	ok "make.conf dom0 flags written"
else
	ok "make.conf already configured (skipping)"
fi

# --- step 5: ensure /etc/portage/package.accept_keywords ---------------

mkdir -p /etc/portage/package.accept_keywords
KEYWORDS_FILE="/etc/portage/package.accept_keywords/qubentoo"
if [[ ! -f "${KEYWORDS_FILE}" ]]; then
	cat > "${KEYWORDS_FILE}" << 'EOF'
# Qubentoo packages — testing accepted
app-emulation/xen ~amd64
app-emulation/xen-tools ~amd64
sys-apps/qubes-db ~amd64
sys-apps/qubes-core-vchan-xen ~amd64
sys-apps/qubes-libvchan ~amd64
sys-apps/qubes-core-admin ~amd64
sys-apps/qubes-core-admin-linux ~amd64
sys-apps/qubes-rpc-proxy ~amd64
gui-daemon/qubes-gui-common ~amd64
gui-daemon/qubes-gui-daemon ~amd64
EOF
	ok "package.accept_keywords written"
else
	ok "package.accept_keywords already present"
fi

# --- step 6: update world (base hardened system) -----------------------

info "Updating @world (this may take a long time on first run)..."
emerge --quiet --update --deep --newuse @world \
	|| die "@world update failed"
ok "@world updated"

# --- step 7: install Xen (hypervisor + tools) in dependency order ------

info "Emerging Xen hypervisor..."
emerge --quiet --noreplace "=app-emulation/xen-${XEN_VERSION}" \
	|| die "xen emerge failed"

info "Emerging Xen tools..."
emerge --quiet --noreplace "=app-emulation/xen-tools-${XEN_VERSION}" \
	|| die "xen-tools emerge failed"
ok "Xen ${XEN_VERSION} installed"

# --- step 8: install Qubes core components in dependency order ---------

QUBES_PKGS=(
	"sys-apps/qubes-db"
	"sys-apps/qubes-core-vchan-xen"
	"sys-apps/qubes-libvchan"
	"sys-apps/qubes-core-admin"
	"sys-apps/qubes-core-admin-linux"
	"sys-apps/qubes-rpc-proxy"
	"gui-daemon/qubes-gui-common"
	"gui-daemon/qubes-gui-daemon"
)

for pkg in "${QUBES_PKGS[@]}"; do
	info "Emerging ${pkg}..."
	emerge --quiet --noreplace "${pkg}" || die "Failed to emerge ${pkg}"
done
ok "All Qubes packages installed"

# --- step 9: configure OpenRC runlevels --------------------------------

info "Configuring OpenRC runlevels..."

# sysinit: Xen infrastructure must come up before any userspace
for svc in xenstored xencommons; do
	if ! rc-update show sysinit 2>/dev/null | grep -qw "${svc}"; then
		rc-update add "${svc}" sysinit
		ok "  Added ${svc} to sysinit"
	else
		ok "  ${svc} already in sysinit"
	fi
done

# default: everything else after login
for svc in xenconsoled xendomains qubes-db qubesd qubes-core qubes-rpc-proxy qubes-gui-daemon; do
	if ! rc-update show default 2>/dev/null | grep -qw "${svc}"; then
		rc-update add "${svc}" default
		ok "  Added ${svc} to default"
	else
		ok "  ${svc} already in default"
	fi
done

# --- step 9b: configure display manager for qubes-gui-daemon ----------

# dom0 GUI daemon needs to know which DM OpenRC service to depend on.
# We prompt interactively unless DM_CHOICE is already set in the environment.
CONFD_GUI="/etc/conf.d/qubes-gui-daemon"
if [[ -f "${CONFD_GUI}" ]]; then
	if [[ -z "${DM_CHOICE:-}" ]]; then
		# Only ask if running from a terminal; skip in non-interactive runs
		if [[ -t 0 ]]; then
			echo ""
			info "Which display manager will you use in dom0?"
			printf '  Options: xdm  lightdm  sddm  gdm\n'
			printf '  Press Enter to accept default [xdm]: '
			read -r DM_CHOICE
		fi
		DM_CHOICE="${DM_CHOICE:-xdm}"
	fi

	# Validate input against known values; warn but don't block on unknown names
	case "${DM_CHOICE}" in
		xdm|lightdm|sddm|gdm) ;;
		*) warn "Unknown DM '${DM_CHOICE}' — proceeding anyway (must be a valid OpenRC service name)" ;;
	esac

	if grep -q "^QUBES_GUI_DM=" "${CONFD_GUI}" 2>/dev/null; then
		sed -i "s/^QUBES_GUI_DM=.*/QUBES_GUI_DM=\"${DM_CHOICE}\"/" "${CONFD_GUI}" \
			|| die "Failed to update QUBES_GUI_DM in ${CONFD_GUI}"
		ok "QUBES_GUI_DM set to \"${DM_CHOICE}\" in ${CONFD_GUI}"
	else
		echo "QUBES_GUI_DM=\"${DM_CHOICE}\"" >> "${CONFD_GUI}"
		ok "QUBES_GUI_DM=\"${DM_CHOICE}\" appended to ${CONFD_GUI}"
	fi
else
	warn "${CONFD_GUI} not found — qubes-gui-daemon not installed yet?"
	warn "After install, set QUBES_GUI_DM in ${CONFD_GUI} manually."
fi

# --- step 10: configure GRUB to boot Xen then kernel ------------------

info "Configuring GRUB for Xen multiboot..."

XEN_GZ=$(find /boot -name "xen*.gz" -o -name "xen-${XEN_VERSION%.?}.gz" 2>/dev/null | sort -V | tail -1)
KERNEL=$(find /boot -name "vmlinuz*" 2>/dev/null | sort -V | tail -1)
INITRAMFS=$(find /boot -name "initramfs*" -o -name "initrd*" 2>/dev/null | sort -V | tail -1)

if [[ -z "${XEN_GZ}" ]]; then
	warn "Could not find xen.gz under /boot — Xen may not be installed to /boot yet."
	warn "After installing Xen, copy /usr/lib/xen/boot/xen.gz to /boot/ and re-run."
fi

GRUB_CFG="/etc/default/grub"
if ! grep -q "# qubentoo-xen" "${GRUB_CFG}" 2>/dev/null; then
	cat >> "${GRUB_CFG}" << EOF

# qubentoo-xen — appended by bootstrap-dom0.sh
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
# Xen command line
GRUB_CMDLINE_XEN_DEFAULT="dom0_mem=${DOM0_MEM_MB}M,max:${DOM0_MEM_MB}M dom0_max_vcpus=4 iommu=on dom0_vcpus_pin"
# Linux dom0 command line
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
# Tell grub-mkconfig to emit a Xen multiboot entry
GRUB_MULTIBOOT_MODULE_LOAD="yes"
EOF
	ok "GRUB defaults updated"
else
	ok "GRUB already configured for Xen (skipping)"
fi

# Install GRUB and generate config
if ! command -v grub-install >/dev/null 2>&1; then
	info "Emerging GRUB with Xen support..."
	emerge --quiet --noreplace "sys-boot/grub:2[grub_platforms_xen,grub_platforms_xen-32,grub_platforms_pc]" \
		|| die "grub emerge failed"
fi

info "Installing GRUB to ${GRUB_DISK}..."
grub-install \
	--target=x86_64-efi \
	--efi-directory=/boot/efi \
	--bootloader-id=Qubentoo \
	"${GRUB_DISK}" \
	|| grub-install \
		--target=i386-pc \
		"${GRUB_DISK}" \
		|| warn "grub-install failed — check GRUB_DISK=${GRUB_DISK} and EFI mount"

info "Generating GRUB config..."
grub-mkconfig -o /boot/grub/grub.cfg \
	|| die "grub-mkconfig failed"
ok "GRUB configured"

# --- step 11: kernel config fragment -----------------------------------

info "Applying Qubentoo dom0 kernel config fragment..."
if [[ -f "${OVERLAY_SRC}/kernel/qubentoo-dom0.config" ]]; then
	if [[ -d "${KERNEL_SRC}" ]]; then
		cd "${KERNEL_SRC}"
		if [[ -f .config ]]; then
			"${KERNEL_SRC}/scripts/kconfig/merge_config.sh" \
				.config \
				"${OVERLAY_SRC}/kernel/qubentoo-dom0.config" \
				|| warn "merge_config.sh failed — apply fragment manually"
			ok "Kernel config fragment merged into ${KERNEL_SRC}/.config"
		else
			cp "${OVERLAY_SRC}/kernel/qubentoo-dom0.config" "${KERNEL_SRC}/.config"
			make olddefconfig || true
			warn "No prior .config found — used fragment as base, ran olddefconfig"
		fi
		cd - >/dev/null
	else
		warn "Kernel source not found at ${KERNEL_SRC} — skipping config merge"
		warn "After emerging gentoo-sources, run:"
		warn "  scripts/kconfig/merge_config.sh .config ${OVERLAY_SRC}/kernel/qubentoo-dom0.config"
	fi
else
	warn "Kernel config fragment not found at ${OVERLAY_SRC}/kernel/qubentoo-dom0.config"
fi

# --- done --------------------------------------------------------------

info "=================================================="
ok  "Qubentoo dom0 bootstrap complete."
info "=================================================="
info ""
info "Next steps:"
info "  1. Build the kernel (if not done):  make -C ${KERNEL_SRC} -j\$(nproc) && make -C ${KERNEL_SRC} modules_install install"
info "  2. Copy /usr/lib/xen/boot/xen.gz to /boot/"
info "  3. Reboot and verify Xen is the bootloader: xl info"
info "  4. Verify /etc/conf.d/qubes-gui-daemon: QUBES_GUI_DM is set to your DM (${DM_CHOICE:-xdm})"
info "  5. Populate /etc/qubes/policy.d/ with your qrexec policies"
