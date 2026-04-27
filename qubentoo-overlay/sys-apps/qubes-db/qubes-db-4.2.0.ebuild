# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="QubesDB — key-value store for dom0/domU communication"
HOMEPAGE="https://github.com/QubesOS/qubes-db"
QUBES_REPO="qubes-db"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

RDEPEND="
	app-emulation/xen-tools
	sys-libs/pam
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
	emake
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

	newinitd "${FILESDIR}/openrc/qubes-db"  qubes-db
	newconfd "${FILESDIR}/confd/qubes-db"   qubes-db

	keepdir /var/run/qubes
}
