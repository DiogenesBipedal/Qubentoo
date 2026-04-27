#!/usr/bin/env bash
# test-bootstrap.sh — Dry run of the Qubentoo dom0 bootstrap sequence.
#
# Uses 'emerge --pretend' throughout to validate the dependency graph,
# detect overlay conflicts, and flag Python version mismatches — without
# actually building or installing anything.
#
# Outputs a READY / NOT READY verdict with a specific blockers list.
#
# Usage:
#   bash scripts/test-bootstrap.sh [--verbose] [--json]
#
# Options:
#   --verbose   Show full pretend output (default: summary only)
#   --json      Emit machine-readable JSON verdict at the end

set -uo pipefail

VERBOSE=0
USE_JSON=0
for arg in "$@"; do
	case "${arg}" in
		--verbose) VERBOSE=1 ;;
		--json)    USE_JSON=1 ;;
	esac
done

OVERLAY_DIR="${OVERLAY_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_FILE="${OVERLAY_DIR}/test-bootstrap.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

declare -a BLOCKERS=()
declare -a NOTICES=()
declare -a PASSES=()

_pass()   { PASSES+=("$*");   printf '\e[1;32m[PASS]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
_block()  { BLOCKERS+=("$*"); printf '\e[1;31m[BLOCK]\e[0m %s\n' "$*" | tee -a "${LOG_FILE}"; }
_notice() { NOTICES+=("$*");  printf '\e[1;33m[NOTE]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
_info()   {                   printf '\e[1;34m[INFO]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
_head()   {                   printf '\n\e[1;37m=== %s ===\e[0m\n' "$*" | tee -a "${LOG_FILE}"; }

{
  echo "========================================"
  echo "  test-bootstrap.sh  ${TIMESTAMP}"
  echo "  Overlay: ${OVERLAY_DIR}"
  echo "========================================"
} > "${LOG_FILE}"

# Full ordered package list — mirrors bootstrap-dom0.sh step 8
QUBES_PKGS=(
	"app-emulation/xen"
	"app-emulation/xen-tools"
	"dev-python/xen"
	"sys-apps/qubes-db"
	"dev-python/qubesdb"
	"sys-apps/qubes-core-vchan-xen"
	"sys-apps/qubes-libvchan"
	"sys-apps/qubes-core-admin"
	"sys-apps/qubes-core-admin-linux"
	"sys-apps/qubes-rpc-proxy"
	"gui-daemon/qubes-gui-common"
	"gui-daemon/qubes-gui-daemon"
)

XEN_VERSION="${XEN_VERSION:-4.17.5}"

# ---------------------------------------------------------------------------
# CHECK 1: emerge available
# ---------------------------------------------------------------------------
_head "Environment"

if ! command -v emerge >/dev/null 2>&1; then
	_block "emerge not found — must run on a Gentoo system"
	echo "VERDICT: NOT READY (no emerge)" | tee -a "${LOG_FILE}"
	exit 1
fi
_pass "emerge found: $(emerge --version 2>/dev/null | head -1)"

if ! eselect repository list 2>/dev/null | grep -q "qubentoo"; then
	_block "qubentoo overlay not registered — run eselect repository create/add qubentoo"
else
	_pass "qubentoo overlay registered"
fi

# ---------------------------------------------------------------------------
# CHECK 2: pretend full package set, capture output
# ---------------------------------------------------------------------------
_head "Dependency Pretend Run"
_info "Running: emerge --pretend --verbose --noreplace <all packages>"
_info "This may take a minute while Portage resolves dependencies..."

PRETEND_OUT=$(emerge \
	--pretend \
	--verbose \
	--noreplace \
	--color n \
	"=app-emulation/xen-${XEN_VERSION}" \
	"=app-emulation/xen-tools-${XEN_VERSION}" \
	"=dev-python/xen-${XEN_VERSION}" \
	"${QUBES_PKGS[@]:3}" \
	2>&1)

EMERGE_EXIT=$?
echo "${PRETEND_OUT}" >> "${LOG_FILE}"

if (( VERBOSE )); then
	echo "${PRETEND_OUT}"
fi

if (( EMERGE_EXIT != 0 )); then
	_block "emerge --pretend exited with code ${EMERGE_EXIT} — dependency resolution failed"
	# Extract the most useful error lines
	error_lines=$(echo "${PRETEND_OUT}" | grep -E '^\!|^Error|conflict|Unsatisfied|blocked' | head -20)
	if [[ -n "${error_lines}" ]]; then
		_block "Portage errors:"
		while IFS= read -r line; do
			_block "  ${line}"
		done <<< "${error_lines}"
	fi
else
	_pass "emerge --pretend succeeded (exit 0)"
fi

# ---------------------------------------------------------------------------
# CHECK 3: detect ::gentoo vs ::qubentoo conflicts
# ---------------------------------------------------------------------------
_head "Overlay Conflict Detection"

# Packages that appear from ::gentoo when they should come from ::qubentoo
QUBENTOO_ATOMS=(
	"sys-apps/qubes-db"
	"sys-apps/qubes-core-vchan-xen"
	"sys-apps/qubes-libvchan"
	"sys-apps/qubes-core-admin"
	"sys-apps/qubes-core-admin-linux"
	"sys-apps/qubes-rpc-proxy"
	"gui-daemon/qubes-gui-common"
	"gui-daemon/qubes-gui-daemon"
	"dev-python/qubesdb"
)

for atom in "${QUBENTOO_ATOMS[@]}"; do
	pkg_name="${atom##*/}"
	# In pretend output, packages from a specific repo appear as [ebuild ... ::reponame]
	if echo "${PRETEND_OUT}" | grep -qE "${pkg_name}.*::gentoo"; then
		_block "${atom} resolving from ::gentoo instead of ::qubentoo"
		_block "       Add '${atom}::qubentoo' to package.mask or ensure overlay priority is set"
	elif echo "${PRETEND_OUT}" | grep -qE "${pkg_name}.*::qubentoo"; then
		_pass "${atom} resolved from ::qubentoo"
	elif echo "${PRETEND_OUT}" | grep -qE "\[ebuild.*\] ${pkg_name}"; then
		_notice "${atom} found in pretend output (repo not specified in output)"
	else
		_notice "${atom} not in pretend output — may already be installed or not found"
	fi
done

# Detect blocked packages
blocked=$(echo "${PRETEND_OUT}" | grep -c 'BLOCK\|blocked' || true)
if (( blocked > 0 )); then
	_block "Portage reports ${blocked} blocked package(s):"
	echo "${PRETEND_OUT}" | grep -E 'BLOCK|blocked' | head -10 | while IFS= read -r line; do
		_block "  ${line}"
	done
fi

# ---------------------------------------------------------------------------
# CHECK 4: RESTRICT="test" packages
# ---------------------------------------------------------------------------
_head "RESTRICT=test Packages"

restrict_test_pkgs=()
while IFS= read -r -d '' ebuild; do
	if grep -qE 'RESTRICT=.*\btest\b' "${ebuild}" 2>/dev/null; then
		cat_pkg=$(basename "$(dirname "$(dirname "${ebuild}")")")/$(basename "$(dirname "${ebuild}")")
		restrict_test_pkgs+=( "${cat_pkg}" )
	fi
done < <(find "${OVERLAY_DIR}" -name "*.ebuild" -print0)

if (( ${#restrict_test_pkgs[@]} > 0 )); then
	for pkg in "${restrict_test_pkgs[@]}"; do
		_notice "${pkg} has RESTRICT=\"test\" — test failures will be hidden"
	done
	_notice "Consider running: FEATURES=\"test\" emerge <pkg> to force tests"
else
	_pass "No packages with RESTRICT=test found in overlay"
fi

# ---------------------------------------------------------------------------
# CHECK 5: Python version consistency
# ---------------------------------------------------------------------------
_head "Python Version Consistency"

# Collect PYTHON_COMPAT declarations from all overlay ebuilds
declare -A pkg_py_compat=()
while IFS= read -r -d '' ebuild; do
	compat_line=$(grep -oP 'PYTHON_COMPAT=\( python3_\{[^}]+\} \)' "${ebuild}" 2>/dev/null \
		|| grep -oP 'PYTHON_COMPAT=\([^)]+\)' "${ebuild}" 2>/dev/null | head -1)
	if [[ -n "${compat_line}" ]]; then
		pkg=$(basename "$(dirname "${ebuild}")")/$(basename "${ebuild}" .ebuild)
		pkg_py_compat["${pkg}"]="${compat_line}"
	fi
done < <(find "${OVERLAY_DIR}" -name "*.ebuild" -print0)

# Determine PYTHON_SINGLE_TARGET from make.conf or environment
active_py=$(portageq envvar PYTHON_SINGLE_TARGET 2>/dev/null | tr -d '[:space:]')
active_py="${active_py:-python3_11}"  # default from our make.defaults

_info "Active PYTHON_SINGLE_TARGET: ${active_py}"

mismatch_found=0
for pkg in "${!pkg_py_compat[@]}"; do
	compat="${pkg_py_compat[$pkg]}"
	# Extract individual python3_XX tokens
	py_tokens=$(echo "${compat}" | grep -oP 'python3_\d+')
	if ! echo "${py_tokens}" | grep -qx "${active_py}"; then
		_block "Python mismatch in ${pkg}"
		_block "       PYTHON_COMPAT: ${compat}"
		_block "       Active target: ${active_py} — not listed"
		mismatch_found=1
	fi
done
if (( mismatch_found == 0 )); then
	_pass "All Python packages support ${active_py}"
fi

# Cross-check: all Python qubes packages should share the same compat set
if (( ${#pkg_py_compat[@]} > 0 )); then
	# Normalise and deduplicate
	unique_compats=()
	while IFS= read -r c; do
		unique_compats+=("${c}")
	done < <(for v in "${pkg_py_compat[@]}"; do echo "${v}"; done | sort -u)
	if (( ${#unique_compats[@]} == 1 )); then
		_pass "All Python packages have identical PYTHON_COMPAT declarations"
	else
		_notice "Python packages have differing PYTHON_COMPAT declarations:"
		for pkg in "${!pkg_py_compat[@]}"; do
			_notice "  ${pkg}: ${pkg_py_compat[$pkg]}"
		done
		_notice "This is acceptable if all still include ${active_py}"
	fi
fi

# ---------------------------------------------------------------------------
# CHECK 6: key package versions consistent
# ---------------------------------------------------------------------------
_head "Version Consistency"

# All qubes-* packages should be at the same version
qubes_versions=()
while IFS= read -r -d '' ebuild; do
	case "$(dirname "${ebuild}")" in
		*xen*) continue ;;  # Xen has a different version
	esac
	ver=$(basename "${ebuild}" | grep -oP '\d+\.\d+\.\d+' | head -1)
	[[ -n "${ver}" ]] && qubes_versions+=("${ver}")
done < <(find "${OVERLAY_DIR}/sys-apps" "${OVERLAY_DIR}/gui-daemon" \
	"${OVERLAY_DIR}/dev-python" -name "*.ebuild" -print0 2>/dev/null)

unique_versions=$(printf '%s\n' "${qubes_versions[@]}" | sort -u)
version_count=$(echo "${unique_versions}" | wc -l | tr -d ' ')

if (( version_count == 1 )); then
	_pass "All Qubes packages at consistent version: ${unique_versions}"
elif (( version_count <= 2 )); then
	_notice "Qubes packages span ${version_count} versions: $(echo "${unique_versions}" | tr '\n' ' ')"
	_notice "This is expected if Xen Python bindings use Xen's version number"
else
	_block "Qubes packages span ${version_count} different versions — check for inconsistency"
	echo "${unique_versions}" | while IFS= read -r v; do _block "  ${v}"; done
fi

# ---------------------------------------------------------------------------
# CHECK 7: USE flag alignment
# ---------------------------------------------------------------------------
_head "USE Flag Sanity"

current_use=$(portageq envvar USE 2>/dev/null || true)

for required_flag in openrc xen hardened; do
	if echo " ${current_use} " | grep -q " ${required_flag} "; then
		_pass "USE flag '${required_flag}' is set"
	else
		_block "USE flag '${required_flag}' NOT found in active USE"
		_block "       Add to /etc/portage/make.conf:  USE=\"... ${required_flag} ...\""
	fi
done

for forbidden_flag in systemd; do
	if echo " ${current_use} " | grep -q " -${forbidden_flag} "; then
		_pass "USE flag '-${forbidden_flag}' is explicitly disabled"
	elif echo " ${current_use} " | grep -q " ${forbidden_flag} "; then
		_block "USE flag '${forbidden_flag}' is ENABLED — must be disabled (-${forbidden_flag})"
	else
		_notice "USE flag '${forbidden_flag}' is not explicitly disabled — add -${forbidden_flag} to be safe"
	fi
done

# ---------------------------------------------------------------------------
# VERDICT
# ---------------------------------------------------------------------------

echo "" | tee -a "${LOG_FILE}"
printf '\e[1;37m%s\e[0m\n' "==========================================" | tee -a "${LOG_FILE}"
printf '\e[1;37m%s\e[0m\n' "  DRY RUN SUMMARY" | tee -a "${LOG_FILE}"
printf '\e[1;37m%s\e[0m\n' "==========================================" | tee -a "${LOG_FILE}"
printf '\e[1;32m  PASS    : %d\e[0m\n' "${#PASSES[@]}"   | tee -a "${LOG_FILE}"
printf '\e[1;33m  NOTICES : %d\e[0m\n' "${#NOTICES[@]}"  | tee -a "${LOG_FILE}"
printf '\e[1;31m  BLOCKERS: %d\e[0m\n' "${#BLOCKERS[@]}" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"
printf 'Full log: %s\n' "${LOG_FILE}" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

if (( ${#BLOCKERS[@]} > 0 )); then
	printf '\e[1;31mBLOCKERS:\e[0m\n'
	for b in "${BLOCKERS[@]}"; do printf '  ✗ %s\n' "${b}"; done
	echo ""
	printf '\e[1;31mVERDICT: NOT READY\e[0m\n' | tee -a "${LOG_FILE}"
	printf 'Resolve the blockers above, then re-run: bash scripts/test-bootstrap.sh\n'
	VERDICT="NOT_READY"
	EXIT_CODE=1
else
	printf '\e[1;32mVERDICT: READY — safe to run bootstrap-dom0.sh\e[0m\n' | tee -a "${LOG_FILE}"
	VERDICT="READY"
	EXIT_CODE=0
fi

if (( USE_JSON )); then
	python3 - "${VERDICT}" "${#PASSES[@]}" "${#NOTICES[@]}" "${#BLOCKERS[@]}" << 'PYEOF'
import sys, json
verdict, passes, notices, blockers = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
print(json.dumps({"verdict": verdict, "passes": passes, "notices": notices, "blockers": blockers}, indent=2))
PYEOF
fi

exit ${EXIT_CODE}
