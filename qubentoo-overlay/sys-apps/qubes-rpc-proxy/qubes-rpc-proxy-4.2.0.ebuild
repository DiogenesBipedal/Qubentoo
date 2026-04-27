# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1 qubes

DESCRIPTION="Qubes qrexec policy engine and RPC proxy"
HOMEPAGE="https://github.com/QubesOS/qubes-core-qrexec"
QUBES_REPO="qubes-core-qrexec"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-core-admin
	sys-apps/qubes-libvchan
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/pyyaml[${PYTHON_USEDEP}]
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
		LIBDIR="${EPREFIX}/usr/lib" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	newinitd "${FILESDIR}/openrc/qubes-rpc-proxy"  qubes-rpc-proxy
	newconfd "${FILESDIR}/confd/qubes-rpc-proxy"   qubes-rpc-proxy

	# Default policy directory — admin populates per-service files
	keepdir /etc/qubes/policy.d
	insinto /etc/qubes/policy.d
	doins "${FILESDIR}/policy/default.policy" 2>/dev/null || true
}
