# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 flag-o-matic

DESCRIPTION="Xen hypervisor — dom0 build (no stubdom)"
HOMEPAGE="https://xenproject.org"
SRC_URI="https://downloads.xenproject.org/release/xen/${PV}/xen-${PV}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE="debug flask hvm +pv +pvh"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	dev-libs/openssl:=
	sys-libs/zlib
	sys-apps/util-linux
	sys-firmware/seabios
	sys-apps/acl
"
DEPEND="${RDEPEND}
	sys-devel/bin86
	sys-devel/dev86
	dev-lang/perl
	app-arch/bzip2
"
BDEPEND="
	virtual/pkgconfig
	$(python_gen_cond_dep 'dev-python/setuptools[${PYTHON_USEDEP}]')
"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_configure() {
	local myconf=(
		--prefix=/usr
		--libdir=/usr/lib
		--libexecdir=/usr/libexec
		--sysconfdir=/etc
		--localstatedir=/var
		--disable-stubdom
		--disable-ioemu-stubdom
		--disable-pv-grub
		--disable-xenstore-stubdom
		--enable-dom0-build
		$(use_enable debug)
		$(use_enable flask xsmpolicy)
		$(use_enable hvm)
		$(use_enable pv)
		$(use_enable pvh)
	)
	# Only configure the hypervisor and tools, not stubdom
	cd "${S}/xen" || die
	./configure "${myconf[@]}" || die "xen hypervisor configure failed"

	cd "${S}/tools" || die
	./configure "${myconf[@]}" || die "xen tools configure failed"
}

src_compile() {
	# Build hypervisor
	emake -C "${S}/xen" \
		XEN_VENDORVERSION="-qubentoo" \
		$(use debug && echo "debug=y")

	# Build tools (no stubdom)
	emake -C "${S}/tools" \
		PYTHON="${PYTHON}"
}

src_install() {
	# Install hypervisor
	emake -C "${S}/xen" \
		DESTDIR="${D}" \
		install

	# Install tools
	emake -C "${S}/tools" \
		DESTDIR="${D}" \
		PYTHON="${PYTHON}" \
		install

	# Strip systemd artifacts
	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# Install udev rules to correct location
	if [[ -d "${D}/lib/udev" ]]; then
		insinto /lib/udev
		doins -r "${D}/lib/udev/"
		rm -rf "${D}/lib/udev"
	fi

	# Documentation
	dodoc "${S}/README" "${S}/CHANGELOG" || true
}

pkg_postinst() {
	elog "Xen ${PV} dom0 build installed."
	elog "Add 'GRUB_PLATFORMS=\"xen xen-32 pc\"' to /etc/portage/make.conf"
	elog "and configure grub to boot Xen before the Linux kernel."
	elog ""
	elog "Kernel must be built with XEN_DOM0 support."
	elog "See kernel/qubentoo-dom0.config in the qubentoo-overlay."
}
