# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

# NOTE: Xen Python bindings are built as part of the xen-tools source tree
# (tools/python/ and tools/pygrub/).  They are packaged separately here for
# dependency graph clarity: packages that need only the Python xen.lowlevel /
# xen.xl / xenstore bindings can depend on dev-python/xen without pulling in
# the full app-emulation/xen-tools runtime daemon set.
#
# The bindings are extracted from the same upstream tarball used by
# app-emulation/xen-tools.  IUSE="-stubdom" and dom0-only flags are irrelevant
# here — we only build the Python extension modules.

EAPI=8

PYTHON_COMPAT=( python3_{10,11,12} )
inherit python-single-r1

DESCRIPTION="Python bindings for Xen libxl/xl and xenstore (xen.lowlevel, xen.xl)"
HOMEPAGE="https://xenproject.org"
SRC_URI="https://downloads.xenproject.org/release/xen/${PV}/xen-${PV}.tar.gz"

LICENSE="LGPL-2.1"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

REQUIRED_USE="${PYTHON_REQUIRED_USE}"

RDEPEND="
	${PYTHON_DEPS}
	~app-emulation/xen-tools-${PV}
"
DEPEND="${RDEPEND}"
BDEPEND="
	$(python_gen_cond_dep '
		dev-python/setuptools[${PYTHON_USEDEP}]
	')
"

# We build only from the Python subdirectory of the Xen tools tree
S="${WORKDIR}/xen-${PV}/tools/python"

pkg_setup() {
	python-single-r1_pkg_setup
}

src_configure() {
	# The Xen Python bindings expect xen headers and libxenctrl/libxenstore
	# to be already installed (provided by app-emulation/xen-tools).
	export XEN_ROOT="${EPREFIX}/usr"
}

src_compile() {
	"${PYTHON}" setup.py build \
		|| die "xen Python bindings build failed"
}

src_install() {
	"${PYTHON}" setup.py install \
		--root="${D}" \
		--prefix="${EPREFIX}/usr" \
		|| die "xen Python bindings install failed"

	# Also install pygrub (Xen Python bootloader helper) from tools/pygrub/
	local pygrub="${WORKDIR}/xen-${PV}/tools/pygrub"
	if [[ -f "${pygrub}/setup.py" ]]; then
		cd "${pygrub}" || die
		"${PYTHON}" setup.py install \
			--root="${D}" \
			--prefix="${EPREFIX}/usr" \
			|| die "pygrub install failed"
		cd "${S}" || die
	fi

	python_optimize
}
