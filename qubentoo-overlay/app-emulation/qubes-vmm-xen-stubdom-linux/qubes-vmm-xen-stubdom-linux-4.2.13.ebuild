# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

# PORTING NOTES:
#
# qubes-vmm-xen-stubdom-linux builds a minimal Linux kernel + rootfs that runs
# as a Xen stubdomain.  The stubdomain hosts a cut-down QEMU device model,
# providing device model isolation so that a compromised emulated device cannot
# escape to dom0.
#
# The upstream build is effectively a cross-compilation environment: it uses
# buildroot (or a bundled mini-rootfs recipe) plus the Xen device model source
# to produce:
#   - stubdom-linux-rootfs   (initramfs, gzipped)
#   - stubdom-linux-kernel   (bzImage or xen-compatible Image)
#
# These are installed to /usr/lib/xen/boot/ and referenced by xl.conf /
# qemu-system-i386 via the stubdom= xl config key.
#
# Build-time dependencies include a cross-compiler (sys-devel/crossdev for
# x86_64-gentoo-linux-musl or similar) if building on a non-x86 host.  On
# amd64 a native musl toolchain (sys-libs/musl) is sufficient.
#
# OPTIONAL PACKAGE: dom0 works without this package.  Install it only if you
# need PCI passthrough with full device model isolation (IOMMU-based VMs).

EAPI=8

inherit qubes

# Stubdom versioning follows Qubes releases; track required Xen separately.
XEN_PV="4.17.5"

DESCRIPTION="Xen stubdomain Linux kernel + rootfs for device model isolation"
HOMEPAGE="https://github.com/QubesOS/qubes-vmm-xen-stubdom-linux"
QUBES_REPO="qubes-vmm-xen-stubdom-linux"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2 MIT BSD"
SLOT="0"
KEYWORDS="~amd64"

IUSE="debug"

# The stubdom build downloads a specific Linux kernel tarball and QEMU source
# internally via its Makefile.  Restrict fetching — users must run
# 'make download' from the source tree or ensure network access during emerge.
RESTRICT="network-sandbox"

RDEPEND="
	~app-emulation/xen-${XEN_PV}
	~app-emulation/xen-tools-${XEN_PV}
"
DEPEND="${RDEPEND}"
BDEPEND="
	sys-devel/bc
	sys-devel/bison
	sys-devel/flex
	app-arch/cpio
	dev-vcs/git
	sys-libs/musl
	virtual/libelf
	sys-devel/crossdev
"

S="${WORKDIR}/${P}"

pkg_pretend() {
	if ! has_version "~app-emulation/xen-${XEN_PV}"; then
		ewarn "${PN}-${PV} requires app-emulation/xen-${XEN_PV}."
		ewarn "A version mismatch will likely produce an ABI-incompatible stubdomain."
	fi
}

src_unpack() {
	qubes_src_unpack
}

src_configure() {
	export XEN_ROOT="${EPREFIX}/usr"
	export CROSS_COMPILE=""
	use debug && export STUBDOM_DEBUG=1 || export STUBDOM_DEBUG=0
}

src_compile() {
	emake \
		XEN_ROOT="${EPREFIX}/usr" \
		STUBDOM_DEBUG="${STUBDOM_DEBUG:-0}" \
		$(usex debug DEBUG=1 DEBUG=0)
}

src_install() {
	insinto /usr/lib/xen/boot
	doins "${S}/stubdom-linux-rootfs"
	doins "${S}/stubdom-linux-kernel"

	insinto /etc/xen
	doins "${FILESDIR}/stubdom.conf.example"

	if [[ -f "${S}/qemu-dm-wrapper" ]]; then
		dobin "${S}/qemu-dm-wrapper"
	fi
}

pkg_postinst() {
	elog "stubdom-linux-kernel and stubdom-linux-rootfs installed to /usr/lib/xen/boot/."
	elog ""
	elog "To enable device model isolation for a VM, add to its xl config:"
	elog "  device_model_stubdomain_override = 1"
	elog "  device_model_version = \"qemu-xen\""
	elog ""
	elog "See /etc/xen/stubdom.conf.example for a complete example config snippet."
	elog "Requires IOMMU enabled in BIOS/UEFI and iommu=on in the Xen command line."
}
