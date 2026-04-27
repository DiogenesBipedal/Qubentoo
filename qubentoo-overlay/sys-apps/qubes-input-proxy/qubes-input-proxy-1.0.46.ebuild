# Copyright 2024-2025 Qubentoo Project
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit qubes

DESCRIPTION="Qubes OS input device isolation proxy (sender and receiver)"
HOMEPAGE="https://github.com/QubesOS/qubes-app-linux-input-proxy"
QUBES_REPO="qubes-app-linux-input-proxy"
SRC_URI="$(qubes_src_uri)"

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="~amd64"

# sender = dom0/input-VM side; receiver = domU side (both built from same tree)
IUSE="sender receiver"
REQUIRED_USE="|| ( sender receiver )"

RDEPEND="
	sys-apps/qubes-core-agent
	virtual/udev
"
DEPEND="${RDEPEND}
	dev-libs/libevdev
"

S="${WORKDIR}/${P}"

src_unpack() {
	qubes_src_unpack
}

src_configure() {
	qubes_src_configure
}

src_compile() {
	use sender   && emake qubes-input-sender
	use receiver && emake qubes-input-receiver
}

src_install() {
	use sender && \
		emake \
			DESTDIR="${D}" \
			SBINDIR="${EPREFIX}/sbin" \
			install-sender

	use receiver && \
		emake \
			DESTDIR="${D}" \
			SBINDIR="${EPREFIX}/sbin" \
			install-receiver

	rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true

	insinto /lib/udev/rules.d
	doins "${FILESDIR}/udev/70-qubes-input.rules"

	newinitd "${FILESDIR}/openrc/qubes-input-proxy" qubes-input-proxy
	newconfd "${FILESDIR}/confd/qubes-input-proxy"  qubes-input-proxy
}

pkg_postinst() {
	elog "Enable the appropriate role in /etc/conf.d/qubes-input-proxy, then:"
	elog "  rc-update add qubes-input-proxy default"
	elog ""
	elog "dom0 / input-VM: set QUBES_INPUT_ROLE=sender"
	elog "AppVM:           set QUBES_INPUT_ROLE=receiver"
}
