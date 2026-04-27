# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes OS core admin daemon — dom0 management layer"
HOMEPAGE="https://github.com/QubesOS/qubes-core-admin"
QUBES_REPO="qubes-core-admin"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2 LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"

IUSE="doc test"
RESTRICT="!test? ( test )"

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-db
	sys-apps/qubes-core-vchan-xen
	sys-apps/qubes-libvchan
	app-emulation/xen-tools
	$(python_gen_cond_dep '
		dev-python/lxml[${PYTHON_USEDEP}]
		dev-python/dbus-python[${PYTHON_USEDEP}]
		dev-python/qubesdb[${PYTHON_USEDEP}]
		dev-python/xen[${PYTHON_USEDEP}]
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/docutils[${PYTHON_USEDEP}]
		dev-python/jinja2[${PYTHON_USEDEP}]
		dev-python/pyyaml[${PYTHON_USEDEP}]
		dev-python/pyxdg[${PYTHON_USEDEP}]
		dev-python/gbulb[${PYTHON_USEDEP}]
		dev-python/qubes-rpc-multiplexer[${PYTHON_USEDEP}]
	')
"
DEPEND="${RDEPEND}
	$(python_gen_cond_dep 'dev-python/wheel[${PYTHON_USEDEP}]')
"
BDEPEND="
	test? (
		$(python_gen_cond_dep '
			dev-python/pytest[${PYTHON_USEDEP}]
			dev-python/pytest-asyncio[${PYTHON_USEDEP}]
			dev-python/mock[${PYTHON_USEDEP}]
		')
	)
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
	# Core admin uses a Python build with a C extension for the qubesd socket
	emake all PYTHON="${PYTHON}"
}

src_install() {
	emake \
		DESTDIR="${D}" \
		PYTHON="${PYTHON}" \
		SYSCONFDIR="${EPREFIX}/etc" \
		SBINDIR="${EPREFIX}/sbin" \
		LIBDIR="${EPREFIX}/usr/lib" \
		DATADIR="${EPREFIX}/usr/share" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	newinitd "${FILESDIR}/openrc/qubesd"  qubesd
	newconfd "${FILESDIR}/confd/qubesd"   qubesd

	# Policy directory
	keepdir /etc/qubes/policy.d
	keepdir /etc/qubes/backup
}

src_test() {
	"${PYTHON}" -m pytest tests/ -v || die "tests failed"
}
