# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1

DESCRIPTION="Xen management tools — dom0 userspace (xencommons, xendomains, xenstored)"
HOMEPAGE="https://xenproject.org"
SRC_URI="https://downloads.xenproject.org/release/xen/${PV}/xen-${PV}.tar.gz"

LICENSE="GPL-2 LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"

IUSE="doc ocaml +python xend"

REQUIRED_USE="
	${PYTHON_REQUIRED_USE}
	xend? ( python )
"

RDEPEND="
	${PYTHON_DEPS}
	~app-emulation/xen-${PV}
	dev-libs/openssl:=
	dev-libs/glib:2
	sys-libs/zlib
	sys-apps/util-linux
	sys-apps/acl
	net-libs/libnl:3
	sys-apps/iproute2
	dev-libs/yajl
	sys-libs/pam
	$(python_gen_cond_dep '
		dev-python/pyudev[${PYTHON_USEDEP}]
		dev-python/pypci[${PYTHON_USEDEP}]
	')
"
DEPEND="${RDEPEND}
	dev-util/pkgconf
"

S="${WORKDIR}/xen-${PV}"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_configure() {
	cd "${S}/tools" || die
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib \
		--libexecdir=/usr/libexec \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-stubdom \
		$(use_enable ocaml) \
		$(use_enable python) \
		|| die "tools configure failed"
}

src_compile() {
	emake -C "${S}/tools" PYTHON="${PYTHON}"
}

src_install() {
	emake -C "${S}/tools" \
		DESTDIR="${D}" \
		PYTHON="${PYTHON}" \
		install

	# Strip all systemd units — replaced with OpenRC below
	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# OpenRC init scripts
	newinitd "${FILESDIR}/openrc/xencommons"  xencommons
	newinitd "${FILESDIR}/openrc/xendomains"  xendomains
	newinitd "${FILESDIR}/openrc/xenstored"   xenstored
	newinitd "${FILESDIR}/openrc/xenconsoled" xenconsoled

	# conf.d files
	newconfd "${FILESDIR}/confd/xendomains"  xendomains
	newconfd "${FILESDIR}/confd/xencommons"  xencommons
	newconfd "${FILESDIR}/confd/xenconsoled" xenconsoled

	# Qubes expects xl config in /etc/xen
	keepdir /etc/xen/auto

	dodoc "${S}/README" "${S}/tools/README" || true
}

pkg_postinst() {
	elog "Add xenstored and xencommons to the sysinit runlevel:"
	elog "  rc-update add xenstored sysinit"
	elog "  rc-update add xencommons sysinit"
	elog "  rc-update add xenconsoled default"
	elog "  rc-update add xendomains default"
}
