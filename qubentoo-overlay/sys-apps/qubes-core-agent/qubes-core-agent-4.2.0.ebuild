# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes OS core agent — domU (template/AppVM) guest-side components"
HOMEPAGE="https://github.com/QubesOS/qubes-core-agent-linux"
QUBES_REPO="qubes-core-agent-linux"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE="networking"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-core-qubesdb
	sys-apps/qubes-libvchan
	sys-apps/qubes-rpc-proxy
	dev-python/qubesdb[${PYTHON_SINGLE_USEDEP}]
	net-firewall/nftables
	sys-apps/dbus
	virtual/udev
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/pyyaml[${PYTHON_USEDEP}]
		dev-python/dbus-python[${PYTHON_USEDEP}]
	')
"
DEPEND="${RDEPEND}"

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
		BINDIR="${EPREFIX}/usr/bin" \
		LIBDIR="${EPREFIX}/usr/lib" \
		LIBEXECDIR="${EPREFIX}/usr/libexec" \
		DATADIR="${EPREFIX}/usr/share" \
		install

	# Strip any systemd units — OpenRC only
	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# OpenRC init scripts
	newinitd "${FILESDIR}/openrc/qubes-agent"        qubes-agent
	newinitd "${FILESDIR}/openrc/qubes-qrexec-agent" qubes-qrexec-agent

	# conf.d
	newconfd "${FILESDIR}/confd/qubes-agent" qubes-agent

	# udev rules
	local rules_src="${D}/lib/udev/rules.d"
	if [[ -d "${rules_src}" ]]; then
		insinto /lib/udev/rules.d
		doins "${rules_src}"/*.rules
	fi

	# Qubes scripts directory
	keepdir /usr/lib/qubes
	keepdir /etc/qubes
	keepdir /etc/qubes/rpc

	# qrexec policy defaults — shipped by qubes-rpc-proxy but agent needs the dir
	keepdir /etc/qubes/policy.d
}

pkg_postinst() {
	elog "Add Qubes agent services to the 'default' runlevel inside the template:"
	elog "  rc-update add qubes-agent default"
	elog "  rc-update add qubes-qrexec-agent default"
}
