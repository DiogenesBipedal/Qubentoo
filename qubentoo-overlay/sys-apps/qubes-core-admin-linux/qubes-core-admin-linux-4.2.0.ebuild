# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes OS Linux-specific dom0 components (udev, dracut, kernel helpers)"
HOMEPAGE="https://github.com/QubesOS/qubes-core-admin-linux"
QUBES_REPO="qubes-core-admin-linux"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-core-admin
	sys-apps/qubes-db
	app-emulation/xen-tools
	virtual/udev
	$(python_gen_cond_dep 'dev-python/setuptools[${PYTHON_USEDEP}]')
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
		LIBDIR="${EPREFIX}/usr/lib" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	# udev rules
	if [[ -d "${D}/lib/udev/rules.d" ]]; then
		insinto /lib/udev/rules.d
		doins "${D}"/lib/udev/rules.d/*.rules 2>/dev/null || true
	fi

	newinitd "${FILESDIR}/openrc/qubes-core"  qubes-core
}
