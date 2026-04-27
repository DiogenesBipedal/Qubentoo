# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="Qubes vchan implementation over Xen shared memory"
HOMEPAGE="https://github.com/QubesOS/qubes-core-vchan-xen"
QUBES_REPO="qubes-core-vchan-xen"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

RDEPEND="
	app-emulation/xen-tools
	sys-apps/qubes-core-qubesdb
"
DEPEND="${RDEPEND}
	app-emulation/xen
"

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
		LIBDIR="${EPREFIX}/usr/lib" \
		INCLUDEDIR="${EPREFIX}/usr/include" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true
}
