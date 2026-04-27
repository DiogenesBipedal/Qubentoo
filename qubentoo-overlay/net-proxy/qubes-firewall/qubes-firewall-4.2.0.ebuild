# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# qubes-firewall lives in the firewall/ subdirectory of qubes-core-admin-linux.
# We pull the same tarball used by sys-apps/qubes-core-admin-linux and build
# only the firewall components.

inherit qubes

DESCRIPTION="Qubes OS nftables-based firewall service for NetVMs and AppVMs"
HOMEPAGE="https://github.com/QubesOS/qubes-core-admin-linux"

MY_PN="qubes-core-admin-linux"
MY_P="${MY_PN}-${PV}"
QUBES_REPO="${MY_PN}"
SRC_URI="https://github.com/QubesOS/${MY_PN}/archive/v${PV}.tar.gz -> ${MY_P}.tar.gz"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

IUSE=""

RDEPEND="
	net-firewall/nftables
	sys-apps/qubes-core-agent
"
DEPEND="${RDEPEND}"

# After unpack the archive lands as qubes-core-admin-linux-4.2.0/;
# we only build from its firewall/ subdirectory.
S="${WORKDIR}/${MY_P}/firewall"

src_unpack() {
	default
	# Normalise directory name if needed
	if [[ -d "${WORKDIR}/${MY_PN}-${PV}" ]]; then
		mv "${WORKDIR}/${MY_PN}-${PV}" "${WORKDIR}/${MY_P}" || die
	fi
}

src_configure() {
	:
}

src_compile() {
	emake
}

src_install() {
	emake \
		DESTDIR="${D}" \
		SYSCONFDIR="${EPREFIX}/etc" \
		SBINDIR="${EPREFIX}/sbin" \
		LIBEXECDIR="${EPREFIX}/usr/libexec" \
		DATADIR="${EPREFIX}/usr/share" \
		install

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	newinitd "${FILESDIR}/openrc/qubes-firewall" qubes-firewall
	newconfd "${FILESDIR}/confd/qubes-firewall"  qubes-firewall

	# nftables ruleset skeleton — populated at runtime by qubes-firewall
	keepdir /etc/qubes/firewall.d
}

pkg_postinst() {
	elog "Add qubes-firewall to the 'default' runlevel in NetVMs and AppVMs:"
	elog "  rc-update add qubes-firewall default"
}
