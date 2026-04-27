#!/usr/bin/env bash
# build-gentoo-template.sh — Build a minimal Gentoo PV domU Qubes template
#
# Produces: a Qubes template tarball compatible with qvm-template-install.
#
# Requires (on dom0):
#   - Xen xl toolstack running (xl list works)
#   - loopback module loaded (modprobe loop)
#   - stage3 tarball accessible (downloaded or pre-placed)
#   - portage snapshot or network access inside chroot
#
# Idempotent: re-running skips already-completed steps.

set -euo pipefail
IFS=$'\n\t'

# --- helpers -----------------------------------------------------------

info()  { printf '\e[1;34m[INFO]\e[0m  %s\n' "$*"; }
ok()    { printf '\e[1;32m[ OK ]\e[0m  %s\n' "$*"; }
warn()  { printf '\e[1;33m[WARN]\e[0m  %s\n' "$*"; }
die()   { printf '\e[1;31m[FAIL]\e[0m  %s\n' "$*" >&2; exit 1; }

cleanup() {
	info "Cleaning up mounts..."
	umount "${ROOTFS}/proc"    2>/dev/null || true
	umount "${ROOTFS}/sys"     2>/dev/null || true
	umount "${ROOTFS}/dev/pts" 2>/dev/null || true
	umount "${ROOTFS}/dev"     2>/dev/null || true
	umount "${ROOTFS}"         2>/dev/null || true
	[[ -n "${LOOP_DEV:-}" ]] && losetup -d "${LOOP_DEV}" 2>/dev/null || true
}
trap cleanup EXIT

require_root() { [[ ${EUID} -eq 0 ]] || die "Must be run as root."; }
require_root

# --- configurable variables --------------------------------------------

TEMPLATE_NAME="${TEMPLATE_NAME:-gentoo-qubentoo}"
TEMPLATE_VERSION="${TEMPLATE_VERSION:-1}"
WORK_DIR="${WORK_DIR:-/var/lib/qubes/template-build/${TEMPLATE_NAME}}"
OUTPUT_DIR="${OUTPUT_DIR:-/var/lib/qubes/vm-templates}"
IMG_SIZE_GB="${IMG_SIZE_GB:-20}"

# Stage3 — place a hardened amd64 stage3 tarball at this path, or set
# STAGE3_URL to download automatically.
STAGE3_PATH="${STAGE3_PATH:-${WORK_DIR}/stage3.tar.xz}"
STAGE3_URL="${STAGE3_URL:-https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-hardened-openrc/}"

# Overlay source (the qubentoo-overlay directory)
OVERLAY_SRC="${OVERLAY_SRC:-/var/db/repos/qubentoo}"

# Python version to use inside the template
PYTHON_VER="${PYTHON_VER:-python3_11}"

# --- directories -------------------------------------------------------

IMG="${WORK_DIR}/${TEMPLATE_NAME}.img"
ROOTFS="${WORK_DIR}/rootfs"
mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}" "${ROOTFS}"

# --- step 1: acquire stage3 tarball ------------------------------------

info "Acquiring stage3 tarball..."
if [[ ! -f "${STAGE3_PATH}" ]]; then
	info "Downloading latest hardened-openrc stage3..."
	# Resolve the actual tarball filename from the directory listing
	local_index="${WORK_DIR}/stage3-index.html"
	curl -fsSL "${STAGE3_URL}" -o "${local_index}" \
		|| die "Failed to fetch stage3 index from ${STAGE3_URL}"
	STAGE3_FILENAME=$(grep -oP 'stage3-amd64-hardened-openrc-\d{8}T\d{6}Z\.tar\.xz(?!\.DIGESTS)' \
		"${local_index}" | head -1)
	[[ -n "${STAGE3_FILENAME}" ]] || die "Could not parse stage3 filename from index"
	STAGE3_FULL_URL="${STAGE3_URL}${STAGE3_FILENAME}"
	info "Downloading: ${STAGE3_FULL_URL}"
	curl -fL# "${STAGE3_FULL_URL}" -o "${STAGE3_PATH}" \
		|| die "Stage3 download failed"
	ok "Stage3 downloaded to ${STAGE3_PATH}"
else
	ok "Stage3 already present at ${STAGE3_PATH}"
fi

# --- step 2: create disk image -----------------------------------------

info "Creating ${IMG_SIZE_GB}G raw disk image..."
if [[ ! -f "${IMG}" ]]; then
	fallocate -l "${IMG_SIZE_GB}G" "${IMG}" \
		|| dd if=/dev/zero of="${IMG}" bs=1M count=$(( IMG_SIZE_GB * 1024 )) status=progress
	ok "Image created: ${IMG}"
else
	ok "Image already exists: ${IMG}"
fi

# --- step 3: partition and format image --------------------------------

info "Partitioning and formatting image..."
if ! file "${IMG}" | grep -q "ext4\|dos\|GPT"; then
	# Single root partition, no swap (template is thin — swap in AppVMs)
	parted -s "${IMG}" \
		mklabel msdos \
		mkpart primary ext4 1MiB 100% \
		set 1 boot on

	LOOP_DEV=$(losetup --find --show --partscan "${IMG}")
	mkfs.ext4 -L gentoo-root "${LOOP_DEV}p1"
	ok "Formatted ${LOOP_DEV}p1 as ext4"
else
	LOOP_DEV=$(losetup --find --show --partscan "${IMG}")
	ok "Image already partitioned, attached as ${LOOP_DEV}"
fi

# --- step 4: mount and extract stage3 ----------------------------------

info "Mounting and extracting stage3..."
mount "${LOOP_DEV}p1" "${ROOTFS}"

if [[ ! -f "${ROOTFS}/etc/gentoo-release" ]]; then
	tar xpJf "${STAGE3_PATH}" --xattrs-include='*.*' --numeric-owner \
		-C "${ROOTFS}" \
		|| die "stage3 extraction failed"
	ok "Stage3 extracted to ${ROOTFS}"
else
	ok "Stage3 already extracted (skipping)"
fi

# --- step 5: bind mounts for chroot ------------------------------------

info "Binding /proc /sys /dev into chroot..."
mount -t proc proc "${ROOTFS}/proc"
mount --rbind /sys  "${ROOTFS}/sys" && mount --make-rslave "${ROOTFS}/sys"
mount --rbind /dev  "${ROOTFS}/dev" && mount --make-rslave "${ROOTFS}/dev"
mount -t devpts devpts "${ROOTFS}/dev/pts" -o nosuid,noexec,gid=5,mode=620

# Copy resolv.conf for network access inside chroot
cp -L /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"

# --- helper: run command inside chroot --------------------------------

in_chroot() {
	chroot "${ROOTFS}" /bin/bash --login -c "$*"
}

# --- step 6: configure portage inside chroot ---------------------------

info "Configuring portage inside template..."
in_chroot "emerge-webrsync" || warn "emerge-webrsync failed — trying emaint sync"
in_chroot "emaint sync -a"  || warn "emaint sync failed — proceeding with cached tree"

in_chroot "eselect profile set default/linux/amd64/23.0/hardened" \
	|| die "Profile select failed"

cat >> "${ROOTFS}/etc/portage/make.conf" << EOF

# qubentoo template appended by build-gentoo-template.sh
USE="hardened openrc -systemd pam python dbus ssl gnutls -X -gtk -qt5"
PYTHON_SINGLE_TARGET="${PYTHON_VER}"
PYTHON_TARGETS="${PYTHON_VER}"
MAKEOPTS="-j$(nproc)"
EOF

ok "Portage configured inside template"

# --- step 7: install @world --------------------------------------------

info "Updating @world inside template (minimal set)..."
in_chroot "emerge --quiet --update --deep --newuse @world" \
	|| die "@world update failed inside template"
ok "@world updated inside template"

# --- step 8: install Qubes guest agent packages ------------------------

info "Setting up qubentoo overlay inside template..."

in_chroot "emerge --quiet --noreplace app-eselect/eselect-repository dev-vcs/git"

# Mount overlay source into chroot
mkdir -p "${ROOTFS}/var/db/repos/qubentoo"
mount --bind "${OVERLAY_SRC}" "${ROOTFS}/var/db/repos/qubentoo"

in_chroot "eselect repository create qubentoo /var/db/repos/qubentoo" || true

cat >> "${ROOTFS}/etc/portage/package.accept_keywords/qubentoo" << 'EOF'
sys-apps/qubes-core-qubesdb ~amd64
sys-apps/qubes-core-vchan-xen ~amd64
sys-apps/qubes-libvchan ~amd64
sys-apps/qubes-core-agent ~amd64
net-proxy/qubes-firewall ~amd64
sys-apps/qubes-input-proxy ~amd64
gui-daemon/qubes-gui-common ~amd64
gui-daemon/qubes-gui-agent ~amd64
EOF

info "Emerging Qubes guest components..."
QUBES_GUEST_PKGS=(
	"sys-apps/qubes-core-qubesdb"
	"sys-apps/qubes-libvchan"
	"sys-apps/qubes-core-vchan-xen"
	"sys-apps/qubes-core-agent"
	"net-proxy/qubes-firewall"
	"sys-apps/qubes-input-proxy"
	"gui-daemon/qubes-gui-common"
	"gui-daemon/qubes-gui-agent"
)
for pkg in "${QUBES_GUEST_PKGS[@]}"; do
	in_chroot "emerge --quiet --noreplace '${pkg}'" \
		|| die "Failed to emerge ${pkg} inside template"
done

# Unmount overlay bind
umount "${ROOTFS}/var/db/repos/qubentoo" 2>/dev/null || true
ok "Qubes guest packages installed"

# --- step 9: write /etc/qubes/guid.conf --------------------------------

info "Writing /etc/qubes/guid.conf inside template..."
mkdir -p "${ROOTFS}/etc/qubes"
cat > "${ROOTFS}/etc/qubes/guid.conf" << 'EOF'
# Qubes GUI agent configuration — inside domU template

[global]
# Allow GUI agent to connect to dom0 GUI daemon
gui_domain = dom0

# Log level: 0=error 1=info 2=debug
log_level = 1

# Clipboard integration: 1=enabled 0=disabled
clipboard = 1
EOF
ok "/etc/qubes/guid.conf written"

# --- step 10: OpenRC services inside template --------------------------

info "Enabling Qubes services in template..."
for svc in qubesdb qubes-agent qubes-qrexec-agent qubes-firewall qubes-gui-agent; do
	in_chroot "rc-update add ${svc} default" || warn "rc-update ${svc} failed (non-fatal at build time)"
done

# --- step 11: set hostname and locale ----------------------------------

echo "localhost" > "${ROOTFS}/etc/hostname"
in_chroot "ln -sf /usr/share/zoneinfo/UTC /etc/localtime" || true
echo "en_US.UTF-8 UTF-8" >> "${ROOTFS}/etc/locale.gen"
in_chroot "locale-gen" || true
in_chroot "eselect locale set en_US.utf8" || true

# --- step 12: minimal fstab for PV domU --------------------------------

cat > "${ROOTFS}/etc/fstab" << 'EOF'
# Qubes PV domU — disk is Xen virtual block device
/dev/xvda1  /        ext4  defaults,relatime  0 1
tmpfs       /tmp     tmpfs defaults,nodev     0 0
tmpfs       /run     tmpfs defaults,nodev     0 0
EOF

# --- step 13: package the template -------------------------------------

info "Packaging template as Qubes tarball..."
TARBALL="${OUTPUT_DIR}/${TEMPLATE_NAME}-${TEMPLATE_VERSION}.tar"

# Unmount everything before packaging
umount "${ROOTFS}/proc"    2>/dev/null || true
umount "${ROOTFS}/sys"     2>/dev/null || true
umount "${ROOTFS}/dev/pts" 2>/dev/null || true
umount "${ROOTFS}/dev"     2>/dev/null || true
umount "${ROOTFS}"         2>/dev/null || true

# Qubes template tarball format: root.img + a minimal metadata.tar
mkdir -p "${WORK_DIR}/pkg"
cp "${IMG}" "${WORK_DIR}/pkg/root.img"

# Template metadata expected by qvm-template-install
cat > "${WORK_DIR}/pkg/template.conf" << EOF
[main]
name = ${TEMPLATE_NAME}
summary = Gentoo Hardened OpenRC Qubentoo template
version = ${TEMPLATE_VERSION}
license = GPL-2
url = https://github.com/qubentoo
requires =
provides = template
[template]
EOF

tar --create \
	--file="${TARBALL}" \
	--directory="${WORK_DIR}/pkg" \
	root.img template.conf

ok "Template tarball: ${TARBALL}"

info "=================================================="
ok  "Gentoo template build complete."
info "=================================================="
info ""
info "Install with:"
info "  qvm-template install --local ${TARBALL}"
info ""
info "Then create an AppVM:"
info "  qvm-create --template ${TEMPLATE_NAME} --label green my-gentoo-vm"
