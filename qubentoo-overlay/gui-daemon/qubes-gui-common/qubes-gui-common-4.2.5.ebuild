# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="Qubes GUI protocol shared headers and libraries (dom0 + domU)"
HOMEPAGE="https://github.com/QubesOS/qubes-gui-common"
QUBES_REPO="qubes-gui-common"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE="static-libs"

RDEPEND=""
DEPEND="
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
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
		INCLUDEDIR="${EPREFIX}/usr/include" \
		LIBDIR="${EPREFIX}/usr/lib" \
		install

	use static-libs || find "${D}" -name "*.a" -delete
}
