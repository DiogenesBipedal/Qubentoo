# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes dom0 X11 GUI daemon — renders domU windows in dom0 X session"
HOMEPAGE="https://github.com/QubesOS/qubes-gui-daemon"
QUBES_REPO="qubes-gui-daemon"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	gui-daemon/qubes-gui-common
	sys-apps/qubes-core-admin
	sys-apps/qubes-libvchan
	sys-apps/qubes-core-qubesdb
	x11-libs/libX11
	x11-libs/libXcomposite
	x11-libs/libXdamage
	x11-libs/libXfixes
	x11-libs/libXrender
	x11-libs/libXrandr
	x11-libs/libxcb
	media-libs/libpng
	$(python_gen_cond_dep 'dev-python/dbus-python[${PYTHON_USEDEP}]')
"
DEPEND="${RDEPEND}
	x11-base/xorg-proto
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
	emake PYTHON="${PYTHON}"
}

src_install() {
	emake \
		DESTDIR="${D}" \
		PYTHON="${PYTHON}" \
		SYSCONFDIR="${EPREFIX}/etc" \
		SBINDIR="${EPREFIX}/sbin" \
		LIBDIR="${EPREFIX}/usr/lib" \
		LIBEXECDIR="${EPREFIX}/usr/libexec" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	newinitd "${FILESDIR}/openrc/qubes-gui-daemon"  qubes-gui-daemon
	newconfd "${FILESDIR}/confd/qubes-gui-daemon"   qubes-gui-daemon

	# guid configuration directory
	keepdir /etc/qubes/guid.conf.d
	insinto /etc/qubes
	doins "${FILESDIR}/guid.conf"
}

pkg_postinst() {
	elog "qubes-gui-daemon must start AFTER the X11 display server."
	elog "Add it to the 'default' runlevel:"
	elog "  rc-update add qubes-gui-daemon default"
	elog ""
	elog "Ensure DISPLAY and XAUTHORITY are set correctly in /etc/conf.d/qubes-gui-daemon"
}
