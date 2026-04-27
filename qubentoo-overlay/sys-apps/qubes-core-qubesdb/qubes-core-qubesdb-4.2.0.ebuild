# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="QubesDB C daemon and client library (qubesdb-daemon, libqubesdb)"
HOMEPAGE="https://github.com/QubesOS/qubes-core-qubesdb"
QUBES_REPO="qubes-core-qubesdb"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

# sys-apps/qubes-db is an older/incompatible ebuild targeting the same daemon
# binary; the two must not coexist.
RDEPEND="
	!sys-apps/qubes-db
	app-emulation/xen-tools
"
DEPEND="${RDEPEND}"

S="${WORKDIR}/${P}"

src_unpack() {
	qubes_src_unpack
}

src_configure() {
	qubes_src_configure
}

src_compile() {
	emake daemon client
}

src_install() {
	emake \
		DESTDIR="${D}" \
		SBINDIR="${EPREFIX}/sbin" \
		SYSCONFDIR="${EPREFIX}/etc" \
		LIBDIR="${EPREFIX}/usr/lib" \
		INCLUDEDIR="${EPREFIX}/usr/include" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	newinitd "${FILESDIR}/openrc/qubesdb" qubesdb
	newconfd "${FILESDIR}/confd/qubesdb"  qubesdb

	keepdir /var/run/qubes
}

pkg_postinst() {
	elog "Add qubesdb to the appropriate runlevel:"
	elog "  dom0 (sysinit):   rc-update add qubesdb sysinit"
	elog "  domU (default):   rc-update add qubesdb default"
	elog ""
	elog "Packages that previously depended on sys-apps/qubes-db should be"
	elog "updated to depend on sys-apps/qubes-core-qubesdb instead."
}
