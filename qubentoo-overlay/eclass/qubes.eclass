# @ECLASS: qubes.eclass
# @MAINTAINER: qubentoo@localhost
# @BLURB: Shared helpers for Qubes OS component ebuilds
# @DESCRIPTION:
# Provides src_configure and src_install wrappers for Qubes components.
# All Qubes packages share a common upstream Makefile convention:
#   make install DESTDIR= SYSCONFDIR= SBINDIR= ...
# This eclass also suppresses any systemd unit installation and ensures
# OpenRC init scripts are installed instead.

case ${EAPI} in
	8) ;;
	*) die "${ECLASS}: EAPI ${EAPI} is not supported" ;;
esac

if [[ ! ${_QUBES_ECLASS} ]]; then
_QUBES_ECLASS=1

# @ECLASS_VARIABLE: QUBES_ORG
# @DESCRIPTION: GitHub organisation for SRC_URI construction.
QUBES_ORG="${QUBES_ORG:-QubesOS}"

# @ECLASS_VARIABLE: QUBES_REPO
# @DESCRIPTION: GitHub repository name. Defaults to ${PN}.
QUBES_REPO="${QUBES_REPO:-${PN}}"

# @FUNCTION: qubes_src_uri
# @DESCRIPTION: Returns a standard GitHub archive URI for a Qubes component.
qubes_src_uri() {
	echo "https://github.com/${QUBES_ORG}/${QUBES_REPO}/archive/v${PV}.tar.gz -> ${P}.tar.gz"
}

# @FUNCTION: qubes_src_unpack
# @DESCRIPTION: Unpacks and renames the GitHub tarball to ${P}.
qubes_src_unpack() {
	default_src_unpack
	# GitHub tarballs extract as <repo>-<ver>/; normalise to ${P}
	if [[ -d "${WORKDIR}/${QUBES_REPO}-${PV}" ]]; then
		mv "${WORKDIR}/${QUBES_REPO}-${PV}" "${WORKDIR}/${P}" || die
	fi
}

# @FUNCTION: qubes_src_configure
# @DESCRIPTION: No-op configure; Qubes components use plain Makefiles.
qubes_src_configure() {
	:
}

# @FUNCTION: qubes_make_args
# @DESCRIPTION: Returns standard make variables for Qubes installs.
qubes_make_args() {
	echo \
		DESTDIR="${D}" \
		SBINDIR="${EPREFIX}/sbin" \
		BINDIR="${EPREFIX}/usr/bin" \
		SYSCONFDIR="${EPREFIX}/etc" \
		LIBDIR="${EPREFIX}/usr/lib" \
		LIBEXECDIR="${EPREFIX}/usr/libexec" \
		INCLUDEDIR="${EPREFIX}/usr/include" \
		MANDIR="${EPREFIX}/usr/share/man" \
		DATADIR="${EPREFIX}/usr/share" \
		LOCALSTATEDIR="${EPREFIX}/var" \
		RUNDIR="${EPREFIX}/run" \
		PYTHON="${PYTHON}"
}

# @FUNCTION: qubes_src_install
# @DESCRIPTION: Runs make install with standard Qubes variables, then strips
# any installed systemd units and replaces them with OpenRC init scripts if
# a matching file exists in ${FILESDIR}.
qubes_src_install() {
	emake $(qubes_make_args) install

	# Strip systemd units — we are OpenRC-only
	if [[ -d "${D}/lib/systemd" ]]; then
		rm -rf "${D}/lib/systemd" || die "failed to remove systemd dir"
	fi
	if [[ -d "${D}/usr/lib/systemd" ]]; then
		rm -rf "${D}/usr/lib/systemd" || die "failed to remove usr systemd dir"
	fi

	# Install OpenRC init scripts supplied in FILESDIR
	local initd="${FILESDIR}/openrc"
	if [[ -d "${initd}" ]]; then
		local f
		for f in "${initd}"/*; do
			newinitd "${f}" "$(basename "${f}")"
		done
	fi

	# Install OpenRC conf.d files
	local confd="${FILESDIR}/confd"
	if [[ -d "${confd}" ]]; then
		local f
		for f in "${confd}"/*; do
			newconfd "${f}" "$(basename "${f}")"
		done
	fi
}

fi
