# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="Qubes vchan inter-VM communication library"
HOMEPAGE="https://github.com/QubesOS/qubes-core-vchan-xen"
QUBES_REPO="qubes-core-vchan-xen"
SRC_URI="$(qubes_src_uri)"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"

IUSE="static-libs"

RDEPEND="
	sys-apps/qubes-core-vchan-xen
"
DEPEND="${RDEPEND}"

S="${WORKDIR}/qubes-core-vchan-xen-${PV}/libvchan"

src_unpack() {
	# Pull the full vchan-xen tarball; we build only the libvchan subdir
	QUBES_REPO="qubes-core-vchan-xen" qubes_src_unpack
	mv "${WORKDIR}/qubes-core-vchan-xen-${PV}" "${WORKDIR}/${P}" || die
}

src_configure() {
	qubes_src_configure
}

src_compile() {
	emake -C "${WORKDIR}/${P}" libvchan
}

src_install() {
	emake -C "${WORKDIR}/${P}" \
		DESTDIR="${D}" \
		LIBDIR="${EPREFIX}/usr/lib" \
		INCLUDEDIR="${EPREFIX}/usr/include" \
		install-libvchan

	use static-libs || find "${D}" -name "*.a" -delete
}
