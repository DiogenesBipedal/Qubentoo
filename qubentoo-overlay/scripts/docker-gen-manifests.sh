#!/usr/bin/env bash
# docker-gen-manifests.sh — Run gen-manifests.sh inside a Gentoo container.
#
# Requires: Docker running on the host.
# Caches the Portage tree (~250 MB) and distfiles in ~/.cache/qubentoo-*
# so subsequent runs are much faster.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERLAY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGE="gentoo/stage3:amd64-hardened-openrc"
DISTFILES_CACHE="${HOME}/.cache/qubentoo-distfiles"
PORTAGE_CACHE="${HOME}/.cache/qubentoo-portage-repo"

# --- checks ---------------------------------------------------------------

if ! docker info &>/dev/null 2>&1; then
    printf '\e[1;31m[ERROR]\e[0m Docker is not running.\n' >&2
    exit 1
fi

mkdir -p "${DISTFILES_CACHE}" "${PORTAGE_CACHE}"

# --- container entrypoint (written to a temp file) ------------------------

TMPSCRIPT=$(mktemp /tmp/qubentoo-container-XXXXX.sh)
trap 'rm -f "${TMPSCRIPT}"' EXIT

cat > "${TMPSCRIPT}" << 'CONTAINER_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Portage repository config
mkdir -p /etc/portage/repos.conf
cat > /etc/portage/repos.conf/qubentoo.conf << 'EOF'
[qubentoo]
location = /overlay
masters = gentoo
auto-sync = no
EOF

# Disable sandboxing (Docker provides its own isolation) and
# allow network access so ebuild manifest can fetch SRC_URI files.
cat >> /etc/portage/make.conf << 'EOF'
FEATURES="-ipc-sandbox -network-sandbox -pid-sandbox -usersandbox"
ACCEPT_KEYWORDS="~amd64"
EOF

# Register any custom categories declared in the overlay.
if [[ -f /overlay/profiles/categories ]]; then
    while IFS= read -r cat; do
        grep -qxF "${cat}" /etc/portage/categories 2>/dev/null || \
            echo "${cat}" >> /etc/portage/categories
    done < /overlay/profiles/categories
fi

# Sync the Gentoo tree if not already cached (provides eclasses).
if [[ ! -f /var/db/repos/gentoo/eclass/python-single-r1.eclass ]]; then
    echo "==> Syncing Gentoo portage tree (first run — approx 80 MB)..."
    emerge-webrsync
else
    echo "==> Portage tree already cached, skipping sync."
fi

exec bash /overlay/scripts/gen-manifests.sh
CONTAINER_EOF

chmod +x "${TMPSCRIPT}"

# --- run ------------------------------------------------------------------

printf '\e[1;34m[INFO]\e[0m Pulling %s...\n' "${IMAGE}"
docker pull "${IMAGE}"

printf '\e[1;34m[INFO]\e[0m Starting manifest generation container\n'
printf '         Overlay   : %s\n' "${OVERLAY_DIR}"
printf '         Distfiles : %s\n' "${DISTFILES_CACHE}"
printf '         Portage   : %s\n\n' "${PORTAGE_CACHE}"

docker run --rm \
    -v "${OVERLAY_DIR}:/overlay" \
    -v "${DISTFILES_CACHE}:/var/cache/distfiles" \
    -v "${PORTAGE_CACHE}:/var/db/repos/gentoo" \
    -v "${TMPSCRIPT}:/tmp/container-setup.sh:ro" \
    "${IMAGE}" \
    bash /tmp/container-setup.sh

printf '\n\e[1;32m[ OK ]\e[0m Manifest files written to %s\n' "${OVERLAY_DIR}"
