# Catalyst release spec — Qubentoo GNU/Linux Live+Install CD
#
# Builds a bootable ISO that can:
#   1. Boot into a live Gentoo/Qubentoo environment
#   2. Run scripts/install-qubentoo.sh to install dom0 to a target disk
#
# Usage (as root, with Catalyst installed):
#   catalyst -f catalyst/qubentoo-livecd.spec
#
# Prerequisites:
#   emerge dev-util/catalyst
#   A current Gentoo portage snapshot in /var/db/repos/gentoo
#   This overlay registered (eselect repository create qubentoo <path>)

subarch: amd64
target: livecd-stage2
version_stamp: qubentoo-4.2.0
rel_type: default
profile: default/linux/amd64/17.1/hardened
snapshot: latest
source_subpath: default/linux/amd64/17.1/hardened/livecd-stage1/qubentoo-4.2.0

# Where Catalyst stores build artifacts
storedir: /var/tmp/catalyst

# ── Portage settings ────────────────────────────────────────────────────────
portage_confdir: /etc/portage
portage_overlay:
    /path/to/qubentoo-overlay

# ── Live CD boot configuration ───────────────────────────────────────────────
livecd:
    type: gentoo-release-livecd
    cdtar: /var/tmp/catalyst/default/linux/amd64/17.1/hardened/livecd-stage1/qubentoo-4.2.0/livecd-stage1.tar.bz2

boot/kernel:
    # Use the same 6.6 LTS kernel configuration as dom0
    qubentoo-dom0:
        sources: sys-kernel/gentoo-sources
        config: /path/to/qubentoo-overlay/kernel/qubentoo-dom0.config
        packages:
            sys-kernel/linux-firmware

# ── Packages included on the live ISO ────────────────────────────────────────
# These are the minimal set needed to run the installer.
# Full Qubes packages are NOT installed on the live image — the installer
# emerges them onto the target system.
packages:
    # Core tools
    app-admin/sysklogd
    app-editors/nano
    app-editors/vim
    app-misc/screen
    net-misc/openssh
    sys-apps/gptfdisk
    sys-apps/lvm2
    sys-block/parted
    sys-fs/cryptsetup
    sys-fs/dosfstools
    sys-fs/e2fsprogs
    sys-fs/xfsprogs

    # Xen hypervisor — so the live environment can boot as dom0
    app-emulation/xen
    app-emulation/xen-tools

    # Network
    net-misc/dhcpcd
    net-wireless/wpa_supplicant

    # Installer script dependencies
    dev-lang/python:3.12
    app-shells/bash
    sys-apps/util-linux

# ── Overlay USE flags for the live image ─────────────────────────────────────
use:
    hardened openrc -systemd xen pam python dbus -doc -test

# ── Init / boot ───────────────────────────────────────────────────────────────
# The live CD boots via GRUB2 with a Xen entry.
# The installer script handles GRUB setup on the target disk.
rcadd:
    default:
        - sshd
        - dhcpcd

# ── Post-build hooks ──────────────────────────────────────────────────────────
# Copy the overlay and installer script into the ISO's /root/
livecd/iso: qubentoo-4.2.0-amd64-livecd.iso
livecd/volid: QUBENTOO_42
