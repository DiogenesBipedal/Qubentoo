# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes OS GUI agent — domU X11 window forwarding to dom0"
HOMEPAGE="https://github.com/QubesOS/qubes-gui-agent-linux"
QUBES_REPO="qubes-gui-agent-linux"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	gui-daemon/qubes-gui-common
	sys-apps/qubes-core-agent
	x11-libs/libX11
	x11-libs/libXdamage
	x11-libs/libXfixes
	x11-libs/libXcomposite
	x11-libs/libXrender
	x11-libs/libXrandr
	x11-libs/libxcb
	media-libs/libpng
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
		BINDIR="${EPREFIX}/usr/bin" \
		LIBDIR="${EPREFIX}/usr/lib" \
		LIBEXECDIR="${EPREFIX}/usr/libexec" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# OpenRC service + conf.d with DM-configurable dependency (Issue 4)
	newinitd "${FILESDIR}/openrc/qubes-gui-agent" qubes-gui-agent
	newconfd "${FILESDIR}/confd/qubes-gui-agent"  qubes-gui-agent

	# GUI agent config
	insinto /etc/qubes
	doins "${FILESDIR}/guid.conf"
}

pkg_postinst() {
	elog "Set your display manager in /etc/conf.d/qubes-gui-agent:"
	elog "  QUBES_GUI_DM=\"lightdm\"   # or xdm, sddm, gdm"
	elog ""
	elog "Then enable the service:"
	elog "  rc-update add qubes-gui-agent default"
	elog ""
	elog "See /usr/share/doc/${PF}/display-manager.md for full instructions."
}
