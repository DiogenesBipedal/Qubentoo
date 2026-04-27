#!/usr/bin/env bash
# gen-manifests.sh — Generate Portage Manifest files for every ebuild in the overlay.
#
# Must be run from inside the overlay root, or pass OVERLAY_DIR.
# Requires: a functioning Portage installation with ebuild(1) on PATH.
#
# Idempotent: re-running regenerates all Manifests (safe; ebuild manifest
# only writes files it needs to write).

set -euo pipefail
IFS=$'\n\t'

OVERLAY_DIR="${OVERLAY_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
LOG_FILE="${OVERLAY_DIR}/manifest-gen.log"
TIMESTAMP=$(date '+%Y-%m-%dT%H:%M:%S')

info()  { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
ok()    { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
fail()  { printf '\e[1;31m[FAIL]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }
warn()  { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*" | tee -a "${LOG_FILE}"; }

# --- initialise log ----------------------------------------------------

{
  echo "========================================"
  echo "  gen-manifests.sh  ${TIMESTAMP}"
  echo "  Overlay: ${OVERLAY_DIR}"
  echo "========================================"
} >> "${LOG_FILE}"

info "Scanning overlay: ${OVERLAY_DIR}"

# --- counters ----------------------------------------------------------

total=0
skipped=0
success=0
failed=0
declare -a failed_list=()

# --- main loop ---------------------------------------------------------

while IFS= read -r -d '' ebuild; do
	(( total++ )) || true

	pkg_dir="$(dirname "${ebuild}")"
	pkg_name="$(basename "${pkg_dir}")"
	cat_dir="$(dirname "${pkg_dir}")"
	cat_name="$(basename "${cat_dir}")"
	atom="${cat_name}/${pkg_name}"

	# Check for RESTRICT="mirror" — if set, Portage won't fetch SRC_URI
	# and manifest generation is not needed (no distfiles to hash).
	if grep -qE 'RESTRICT=.*\bmirror\b' "${ebuild}" 2>/dev/null; then
		warn "SKIP (RESTRICT=mirror)  ${atom}  $(basename "${ebuild}")"
		(( skipped++ )) || true
		continue
	fi

	info "Generating Manifest: ${atom}/$(basename "${ebuild}")"
	if ebuild "${ebuild}" manifest >> "${LOG_FILE}" 2>&1; then
		ok "  OK  ${atom}"
		(( success++ )) || true
	else
		fail "  FAILED  ${atom}"
		(( failed++ )) || true
		failed_list+=( "${atom}" )
	fi

done < <(find "${OVERLAY_DIR}" \
	-path "${OVERLAY_DIR}/profiles" -prune -o \
	-path "${OVERLAY_DIR}/eclass"   -prune -o \
	-path "${OVERLAY_DIR}/metadata" -prune -o \
	-path "${OVERLAY_DIR}/scripts"  -prune -o \
	-path "${OVERLAY_DIR}/docs"     -prune -o \
	-name "*.ebuild" -print0 | sort -z)

# --- summary -----------------------------------------------------------

echo "" | tee -a "${LOG_FILE}"
info "======== SUMMARY ========"
info "  Total ebuilds : ${total}"
info "  Succeeded     : ${success}"
info "  Skipped       : ${skipped}"
info "  Failed        : ${failed}"

if (( failed > 0 )); then
	fail ""
	fail "Failed packages:"
	for pkg in "${failed_list[@]}"; do
		fail "  - ${pkg}"
	done
	fail ""
	fail "Check ${LOG_FILE} for details."
	exit 1
else
	ok ""
	ok "All Manifests generated successfully."
	ok "Log: ${LOG_FILE}"
fi
