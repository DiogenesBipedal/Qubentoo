#!/usr/bin/env bash
# install-qubentoo.sh — Qubentoo GNU/Linux dom0 installer
#
# Run this script from the Qubentoo live CD to install dom0 onto a target disk.
# The script partitions the disk, sets up filesystems, chroots, and installs
# the Qubentoo overlay packages using the bootstrap-dom0.sh logic.
#
# Usage (as root on the live CD):
#   bash /root/qubentoo-overlay/scripts/install-qubentoo.sh [options]
#
# Options:
#   --disk /dev/sdX      Target disk (REQUIRED)
#   --hostname NAME      Hostname for the installed system (default: qubentoo)
#   --timezone TZ        Timezone string (default: UTC)
#   --dm xdm|lightdm     Display manager (default: xdm)
#   --luks               Encrypt root partition with LUKS (optional)
#   --yes                Skip all confirmation prompts
#   --help               Show this help

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET_DISK=""
HOSTNAME="qubentoo"
TIMEZONE="UTC"
DM_CHOICE="xdm"
USE_LUKS=0
SKIP_CONFIRM=0
OVERLAY_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MOUNT_ROOT="/mnt/qubentoo"
STAGE3_URL="https://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64-hardened-openrc/stage3-amd64-hardened-openrc-latest.tar.xz"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
info()  { printf "${GREEN}>>> %s${RESET}\n" "$*"; }
warn()  { printf "${YELLOW}!!! %s${RESET}\n" "$*"; }
error() { printf "${RED}ERROR: %s${RESET}\n" "$*" >&2; exit 1; }
step()  { printf "\n${BOLD}=== %s ===${RESET}\n" "$*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)      TARGET_DISK="$2";  shift 2 ;;
        --hostname)  HOSTNAME="$2";     shift 2 ;;
        --timezone)  TIMEZONE="$2";     shift 2 ;;
        --dm)        DM_CHOICE="$2";    shift 2 ;;
        --luks)      USE_LUKS=1;        shift   ;;
        --yes)       SKIP_CONFIRM=1;    shift   ;;
        --help|-h)
            sed -n '3,20p' "$0" | sed 's/^# \?//'
            exit 0 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || error "This script must be run as root."
[[ -n "${TARGET_DISK}" ]] || error "No target disk specified. Use --disk /dev/sdX"
[[ -b "${TARGET_DISK}" ]] || error "${TARGET_DISK} is not a block device."

# ── Confirmation ──────────────────────────────────────────────────────────────
if [[ "${SKIP_CONFIRM}" -eq 0 ]]; then
    printf "\n${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
    printf "${BOLD}║  Qubentoo GNU/Linux Installer                    ║${RESET}\n"
    printf "${BOLD}╠══════════════════════════════════════════════════╣${RESET}\n"
    printf "${BOLD}║  Target disk  : %-32s  ║${RESET}\n" "${TARGET_DISK}"
    printf "${BOLD}║  Hostname     : %-32s  ║${RESET}\n" "${HOSTNAME}"
    printf "${BOLD}║  Timezone     : %-32s  ║${RESET}\n" "${TIMEZONE}"
    printf "${BOLD}║  Display mgr  : %-32s  ║${RESET}\n" "${DM_CHOICE}"
    printf "${BOLD}║  LUKS encrypt : %-32s  ║${RESET}\n" "$([ $USE_LUKS -eq 1 ] && echo yes || echo no)"
    printf "${BOLD}╠══════════════════════════════════════════════════╣${RESET}\n"
    printf "${BOLD}║  ALL DATA ON ${TARGET_DISK} WILL BE DESTROYED!    ║${RESET}\n"
    printf "${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n\n"
    read -r -p "Type YES to continue, anything else to abort: " CONFIRM
    [[ "${CONFIRM}" == "YES" ]] || { printf "Aborted.\n"; exit 0; }
fi

# ── Phase 1: Partition ────────────────────────────────────────────────────────
step "Partitioning ${TARGET_DISK}"

# GPT layout:
#   1: EFI system partition  512 MiB  vfat
#   2: /boot                 512 MiB  ext2  (Xen + kernels live here)
#   3: swap                  4 GiB
#   4: root (/)              remaining  ext4 (or LUKS → ext4)

sgdisk --zap-all "${TARGET_DISK}"
sgdisk \
    --new=1:0:+512M  --typecode=1:ef00 --change-name=1:"EFI"   \
    --new=2:0:+512M  --typecode=2:8300 --change-name=2:"boot"  \
    --new=3:0:+4G    --typecode=3:8200 --change-name=3:"swap"  \
    --new=4:0:0      --typecode=4:8300 --change-name=4:"root"  \
    "${TARGET_DISK}"

partprobe "${TARGET_DISK}"
sleep 1

# Resolve partition device names (handles both /dev/sda1 and /dev/nvme0n1p1)
part() { echo "${TARGET_DISK}$([[ ${TARGET_DISK} =~ nvme|mmcblk ]] && echo p)$1"; }

EFI_PART="$(part 1)"
BOOT_PART="$(part 2)"
SWAP_PART="$(part 3)"
ROOT_PART="$(part 4)"

# ── Phase 2: Filesystems ──────────────────────────────────────────────────────
step "Creating filesystems"

mkfs.vfat -F32 -n EFI   "${EFI_PART}"
mkfs.ext2 -L boot        "${BOOT_PART}"
mkswap    -L swap         "${SWAP_PART}"

if [[ "${USE_LUKS}" -eq 1 ]]; then
    info "Setting up LUKS on ${ROOT_PART}"
    cryptsetup luksFormat --type luks2 "${ROOT_PART}"
    cryptsetup open "${ROOT_PART}" qubentoo-root
    ROOT_DEV="/dev/mapper/qubentoo-root"
else
    ROOT_DEV="${ROOT_PART}"
fi

mkfs.ext4 -L root "${ROOT_DEV}"

# ── Phase 3: Mount ────────────────────────────────────────────────────────────
step "Mounting target filesystems"

mkdir -p "${MOUNT_ROOT}"
mount "${ROOT_DEV}" "${MOUNT_ROOT}"
mkdir -p "${MOUNT_ROOT}/boot"
mount "${BOOT_PART}" "${MOUNT_ROOT}/boot"
mkdir -p "${MOUNT_ROOT}/boot/efi"
mount "${EFI_PART}" "${MOUNT_ROOT}/boot/efi"
swapon "${SWAP_PART}"

# ── Phase 4: Stage3 ───────────────────────────────────────────────────────────
step "Downloading and extracting stage3"

STAGE3_TARBALL="/tmp/stage3-amd64-hardened-openrc.tar.xz"
if [[ ! -f "${STAGE3_TARBALL}" ]]; then
    info "Fetching stage3 from Gentoo distfiles..."
    wget -q --show-progress -O "${STAGE3_TARBALL}" "${STAGE3_URL}"
fi
tar xpf "${STAGE3_TARBALL}" --xattrs-include='*.*' --numeric-owner -C "${MOUNT_ROOT}"

# ── Phase 5: Overlay + portage config ────────────────────────────────────────
step "Installing overlay and portage configuration"

cp -a "${OVERLAY_SRC}" "${MOUNT_ROOT}/root/qubentoo-overlay"
mkdir -p "${MOUNT_ROOT}/etc/portage/repos.conf"
cat > "${MOUNT_ROOT}/etc/portage/repos.conf/qubentoo.conf" <<EOF
[qubentoo]
location = /root/qubentoo-overlay
masters = gentoo
auto-sync = no
EOF

# Copy host DNS so chroot can reach the internet
cp --dereference /etc/resolv.conf "${MOUNT_ROOT}/etc/"

# ── Phase 6: Mount pseudo-filesystems ────────────────────────────────────────
step "Mounting pseudo-filesystems for chroot"

mount --types proc  proc    "${MOUNT_ROOT}/proc"
mount --rbind       /sys    "${MOUNT_ROOT}/sys"
mount --make-rslave         "${MOUNT_ROOT}/sys"
mount --rbind       /dev    "${MOUNT_ROOT}/dev"
mount --make-rslave         "${MOUNT_ROOT}/dev"

# ── Phase 7: Chroot bootstrap ─────────────────────────────────────────────────
step "Running dom0 bootstrap inside chroot"

chroot "${MOUNT_ROOT}" /usr/bin/env -i \
    HOME=/root TERM="${TERM:-xterm}" \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    DM_CHOICE="${DM_CHOICE}" \
    GRUB_DISK="${TARGET_DISK}" \
    XEN_VERSION="4.17.5" \
    OVERLAY_SRC="/root/qubentoo-overlay" \
    HOSTNAME="${HOSTNAME}" \
    TIMEZONE="${TIMEZONE}" \
    USE_LUKS="${USE_LUKS}" \
    bash /root/qubentoo-overlay/scripts/bootstrap-dom0.sh

# ── Phase 8: Finalise ─────────────────────────────────────────────────────────
step "Finalising installation"

# Hostname
echo "${HOSTNAME}" > "${MOUNT_ROOT}/etc/hostname"

# Timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" "${MOUNT_ROOT}/etc/localtime"

# fstab
ROOT_UUID="$(blkid -s UUID -o value "${ROOT_DEV}")"
BOOT_UUID="$(blkid -s UUID -o value "${BOOT_PART}")"
EFI_UUID="$(blkid  -s UUID -o value "${EFI_PART}")"
SWAP_UUID="$(blkid -s UUID -o value "${SWAP_PART}")"

cat > "${MOUNT_ROOT}/etc/fstab" <<EOF
# <fs>                              <mountpoint>  <type>  <opts>           <dump/pass>
UUID=${ROOT_UUID}  /             ext4    defaults,noatime  0 1
UUID=${BOOT_UUID}  /boot         ext2    defaults,noatime  0 2
UUID=${EFI_UUID}   /boot/efi     vfat    umask=077         0 2
UUID=${SWAP_UUID}  none          swap    sw                0 0
EOF

if [[ "${USE_LUKS}" -eq 1 ]]; then
    LUKS_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"
    echo "qubentoo-root  UUID=${LUKS_UUID}  none  luks,discard" \
        >> "${MOUNT_ROOT}/etc/crypttab"
fi

# ── Unmount ───────────────────────────────────────────────────────────────────
step "Unmounting and cleaning up"

umount -R "${MOUNT_ROOT}" 2>/dev/null || true
swapoff "${SWAP_PART}" 2>/dev/null || true
[[ "${USE_LUKS}" -eq 1 ]] && cryptsetup close qubentoo-root 2>/dev/null || true

printf "\n${GREEN}${BOLD}Installation complete!${RESET}\n"
printf "Remove the live CD and reboot into your new Qubentoo dom0.\n\n"
