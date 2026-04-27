#!/usr/bin/env bash
# verify-overlay.sh — Run repoman QA scan on the qubentoo overlay.
#
# Requires: dev-util/repoman (emerge dev-util/repoman)
# Must be run from the overlay root, or pass OVERLAY_DIR.
#
# Exit codes:
#   0 — no errors (warnings are non-fatal unless --strict is passed)
#   1 — repoman reported one or more ERRORs
#   2 — repoman not found or failed to run

set -uo pipefail

OVERLAY_DIR="${OVERLAY_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
REPORT_FILE="${OVERLAY_DIR}/repoman-report.txt"
STRICT="${STRICT:-0}"   # set STRICT=1 or pass --strict to fail on warnings too

# Parse --strict flag
for arg in "$@"; do
	[[ "${arg}" == "--strict" ]] && STRICT=1
done

info()  { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()    { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
err()   { printf '\e[1;31m[ERR ]\e[0m  %s\n' "$*"; }

# --- prerequisite check -----------------------------------------------

if ! command -v repoman >/dev/null 2>&1; then
	err "repoman not found. Install it with: emerge dev-util/repoman"
	exit 2
fi

# --- run repoman -------------------------------------------------------

info "Running repoman scan on overlay: ${OVERLAY_DIR}"
info "Report will be saved to: ${REPORT_FILE}"
echo ""

cd "${OVERLAY_DIR}" || { err "Cannot cd to ${OVERLAY_DIR}"; exit 2; }

# repoman scan --if-modified only checks files modified since last commit;
# we add full for a thorough first-run scan but respect the caller's intent.
REPOMAN_ARGS=( scan )

repoman "${REPOMAN_ARGS[@]}" 2>&1 | tee "${REPORT_FILE}"
REPOMAN_EXIT=${PIPESTATUS[0]}

# --- parse results -----------------------------------------------------

echo ""
info "Parsing repoman output..."

error_count=$(grep -cE '^.*error' "${REPORT_FILE}" 2>/dev/null || true)
warning_count=$(grep -cE '^.*warning' "${REPORT_FILE}" 2>/dev/null || true)

# Also count the summary line format "N error(s), N warning(s)"
summary_errors=$(grep -oP '\d+(?= error)' "${REPORT_FILE}" | tail -1 || echo 0)
summary_warnings=$(grep -oP '\d+(?= warning)' "${REPORT_FILE}" | tail -1 || echo 0)

# Take the higher of line-count vs summary to handle repoman's output formats
[[ "${summary_errors}" -gt "${error_count}" ]] && error_count=${summary_errors}
[[ "${summary_warnings}" -gt "${warning_count}" ]] && warning_count=${summary_warnings}

echo ""
info "======== REPOMAN SUMMARY ========"
if (( error_count > 0 )); then
	err "  Errors   : ${error_count}"
else
	ok  "  Errors   : 0"
fi

if (( warning_count > 0 )); then
	warn "  Warnings : ${warning_count}"
else
	ok   "  Warnings : 0"
fi
info "  Full report: ${REPORT_FILE}"
echo ""

# --- exit logic --------------------------------------------------------

if (( error_count > 0 )); then
	err "repoman found ERRORS — fix before publishing overlay."
	exit 1
fi

if (( STRICT == 1 )) && (( warning_count > 0 )); then
	warn "STRICT mode: treating ${warning_count} warning(s) as failure."
	exit 1
fi

if (( REPOMAN_EXIT != 0 )); then
	warn "repoman exited with code ${REPOMAN_EXIT} but no errors parsed."
	warn "Check ${REPORT_FILE} manually."
	exit 1
fi

ok "Overlay QA check passed."
