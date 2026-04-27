# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# The Python bindings live in the python/ subdirectory of qubes-core-qubesdb.
# We pull the same tarball that sys-apps/qubes-db uses and build only that subdir.

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1

DESCRIPTION="Python bindings for QubesDB key-value store"
HOMEPAGE="https://github.com/QubesOS/qubes-core-qubesdb"

# qubes-core-qubesdb is the upstream repo; qubes-db is the C daemon from the same source.
# We reuse the same tarball here to avoid a redundant download.
MY_PN="qubes-core-qubesdb"
MY_P="${MY_PN}-${PV}"
SRC_URI="https://github.com/QubesOS/${MY_PN}/archive/v${PV}.tar.gz -> ${MY_P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	sys-apps/qubes-db
"
DEPEND="${RDEPEND}"
BDEPEND="
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
		dev-python/wheel[${PYTHON_USEDEP}]
	')
"

# The qubes-db C library headers and libqubesdb.so are required at build time
# They are installed by sys-apps/qubes-db

S="${WORKDIR}/${MY_P}/python"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_unpack() {
	default
	# Normalise extracted directory name
	if [[ -d "${WORKDIR}/${MY_P}" ]]; then
		: # already correct
	elif [[ -d "${WORKDIR}/qubes-core-qubesdb-${PV}" ]]; then
		mv "${WORKDIR}/qubes-core-qubesdb-${PV}" "${WORKDIR}/${MY_P}" || die
	fi
}

src_configure() {
	:
}

src_compile() {
	# The Python extension (qubesdb._qubesdb) links against libqubesdb
	"${PYTHON}" setup.py build_ext \
		--include-dirs="${EPREFIX}/usr/include" \
		--library-dirs="${EPREFIX}/usr/lib" \
		|| die "build_ext failed"
}

src_install() {
	"${PYTHON}" setup.py install \
		--root="${D}" \
		--prefix="${EPREFIX}/usr" \
		|| die "setup.py install failed"

	python_optimize
}
