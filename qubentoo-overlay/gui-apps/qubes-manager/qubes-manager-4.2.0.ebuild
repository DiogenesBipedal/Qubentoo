# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

# PORTING NOTE: qubes-manager uses PyQt5 upstream.  PyQt5 is available in the
# Gentoo tree as dev-python/PyQt5 and is not restricted under the hardened
# profile.  However the hardened profile enables PIE/SSP globally; PyQt5's C
# extensions are built by the Qt build system which respects CFLAGS, so no
# special flag handling is needed.  If PyQt5 is unavailable or blocked,
# dev-python/pyqt5-sip must also be present (it is a hard dep of PyQt5 in the
# Gentoo tree and will be pulled automatically).

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes xdg-utils

DESCRIPTION="Qubes OS dom0 graphical VM management interface (PyQt5)"
HOMEPAGE="https://github.com/QubesOS/qubes-manager"
QUBES_REPO="qubes-manager"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-core-admin
	$(python_gen_cond_dep '
		dev-python/PyQt5[${PYTHON_USEDEP}]
		dev-python/qubesadmin[${PYTHON_USEDEP}]
		dev-python/qubesdb[${PYTHON_USEDEP}]
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/dbus-python[${PYTHON_USEDEP}]
		dev-python/gbulb[${PYTHON_USEDEP}]
		dev-python/qasync[${PYTHON_USEDEP}]
	')
	x11-libs/libX11
"
DEPEND="${RDEPEND}"
BDEPEND="
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/wheel[${PYTHON_USEDEP}]
		dev-python/PyQt5[${PYTHON_USEDEP}]
	')
	dev-qt/linguist-tools
"

S="${WORKDIR}/${P}"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_unpack() {
	qubes_src_unpack
}

src_configure() {
	qubes_src_configure
}

src_compile() {
	emake PYTHON="${PYTHON}" lrelease
}

src_install() {
	emake \
		DESTDIR="${D}" \
		PYTHON="${PYTHON}" \
		SYSCONFDIR="${EPREFIX}/etc" \
		DATADIR="${EPREFIX}/usr/share" \
		BINDIR="${EPREFIX}/usr/bin" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# Desktop entry (may already be installed by make install above; this
	# ensures it ends up in the right place under Gentoo's layout)
	if [[ ! -f "${D}${EPREFIX}/usr/share/applications/qubes-manager.desktop" ]]; then
		insinto /usr/share/applications
		doins "${FILESDIR}/qubes-manager.desktop"
	fi

	python_optimize
}

pkg_postinst() {
	xdg_desktop_database_update
	elog "qubes-manager is a dom0-only application."
	elog "Launch it from your display manager's application menu or run:"
	elog "  qubes-manager"
}

pkg_postrm() {
	xdg_desktop_database_update
}
