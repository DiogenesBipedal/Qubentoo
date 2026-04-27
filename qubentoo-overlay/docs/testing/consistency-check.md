# Qubentoo Overlay — Consistency Checklist

Manual checklist run against the overlay before tagging a release or after any
batch of ebuild changes.  All items must pass.

Run `make verify` to catch most of these automatically; items marked
**(manual)** require human inspection.

---

## EAPI and metadata

- [x] **EAPI=8** declared in every `.ebuild` file
      `grep -rL 'EAPI=8' *.ebuild` returns empty
- [x] **KEYWORDS** present in every ebuild (`~amd64` minimum)
- [x] **LICENSE** set in every ebuild
- [x] **SLOT** set in every ebuild (all `"0"` except where split)
- [x] **metadata/layout.conf** sets `repo-name = qubentoo` and
      `masters = gentoo`
- [x] **profiles/base/eapi** contains `8`

## Python packages

- [x] All Python ebuilds inherit `python-single-r1`
- [x] `PYTHON_COMPAT=( python3_{10,11,12} )` in every Python ebuild
      (CI job `python-compat-lint` enforces this)
- [x] Every Python ebuild declares `REQUIRED_USE="${PYTHON_REQUIRED_USE}"`
- [x] Every Python ebuild calls `python-single-r1_pkg_setup` from `pkg_setup()`
- [x] `dev-python/qubesdb` RDEPEND references `sys-apps/qubes-core-qubesdb`
      (not the deprecated `sys-apps/qubes-db`)
- [x] `dev-python/xen` has `pkg_pretend()` version-match warning against
      `app-emulation/xen-tools-${PV}`

## OpenRC init scripts

- [x] Every init script begins with `#!/sbin/openrc-run`
- [x] Every init script declares `keyword -lxc -openvz -prefix` in `depend()`
- [x] Every `newinitd` call has a matching file under `files/openrc/`
- [x] Every `newconfd` call has a matching file under `files/confd/`
- [x] `app-emulation/xen-tools` has conf.d for xenconsoled (matches xenstored/xendomains)
- [x] CI job `openrc-syntax` passes `bash -n` on all init + conf.d files

## Systemd stripping

- [x] Every `src_install()` contains
      `rm -rf "${D}/lib/systemd" "${D}/usr/lib/systemd" || true`
      (or the eclass `qubes_src_install()` is used which does this automatically)

## Package-specific checks

- [x] `sys-apps/qubes-core-qubesdb` conflicts with `sys-apps/qubes-db`
      via `!sys-apps/qubes-db` in RDEPEND
- [x] `sys-apps/qubes-db` directory is **absent** from the overlay
      (removed after all consumers migrated)
- [x] ALL ebuilds that previously depended on `sys-apps/qubes-db` have been
      migrated to `sys-apps/qubes-core-qubesdb`:
      qubes-core-vchan-xen, qubes-core-agent, qubes-core-admin,
      qubes-core-admin-linux, qubes-gui-daemon, dev-python/qubesdb
- [x] `net-proxy/qubes-firewall` source is `qubes-core-admin-linux` firewall/
      subdirectory; `S` is set to `${WORKDIR}/${MY_P}/firewall`
- [x] `sys-apps/qubes-input-proxy` has `REQUIRED_USE="|| ( sender receiver )"`
- [x] `gui-apps/qubes-manager` porting note documents PyQt5 hardened-profile
      compatibility in the ebuild header comment
- [x] `gui-apps/qubes-manager` desktop file installed to
      `/usr/share/applications/qubes-manager.desktop`
- [x] `app-emulation/qubes-vmm-xen-stubdom-linux` has `RESTRICT="network-sandbox"`
      and documents optional/PCI-passthrough-only status in its header
- [x] stubdom ebuild `pkg_pretend()` warns on Xen version mismatch

## Installer

- [x] `scripts/install-qubentoo.sh` exists and is executable
- [x] `catalyst/qubentoo-livecd.spec` provides a Catalyst ISO recipe skeleton
- [x] `Makefile` `install` target wires up the installer script
- [x] Installer handles GPT partitioning, LUKS opt-in, fstab generation,
      hostname, timezone, chroot bootstrap
- [x] `bootstrap-dom0.sh` consumes `HOSTNAME` and `TIMEZONE` env vars
      (set hostname in `/etc/hostname` and `/etc/hosts`; timezone via symlink)
- [x] `bootstrap-dom0.sh` has `QUBENTOO_CONFIGURED` sentinel at
      `/etc/qubentoo/.bootstrapped` — re-runs are safe and skip completed work
- [x] `Makefile` `kernel` target builds dom0 kernel from `kernel/qubentoo-dom0.config`
- [x] `LICENSE` file at repo root (SPDX GPL-2.0-only)
- [x] `docs/troubleshooting/grub-xen-missing.md` exists

## Kernel configuration

- [x] `kernel/qubentoo-dom0.config` targets Linux 6.6 LTS
- [x] `CONFIG_XEN=y`, `CONFIG_XEN_DOM0=y` present
- [x] `CONFIG_INTEL_IOMMU=y`, `CONFIG_AMD_IOMMU=y` present
- [x] `CONFIG_HARDENED_USERCOPY=y` and related hardening present
- [x] `# CONFIG_XEN_PVCALLS_FRONTEND is not set` explicitly present
      (required — enabling this breaks qubesdb socket path with Xen 4.17)

## Dependency graph integrity

- [x] `docs/dependency-graph.md` Mermaid graph references
      `qubes_coredb` (not the old `qubes_db` node)
- [x] DOM0 ASCII tree shows `sys-apps/qubes-core-qubesdb` in vchan-xen RDEPEND
- [x] DomU ASCII tree shows `qubes-core-qubesdb` in vchan-xen and core-agent RDEPEND
- [x] DOM0 build order in dependency-graph lists `sys-apps/qubes-core-qubesdb`
      at position 4 (after `dev-python/xen`, before `dev-python/qubesdb`)
- [x] DomU build order includes `net-proxy/qubes-firewall` and
      `sys-apps/qubes-input-proxy`

## Bootstrap scripts

- [x] `bootstrap-dom0.sh` QUBES_PKGS contains `sys-apps/qubes-core-qubesdb`
      (not `sys-apps/qubes-db`)
- [x] `bootstrap-dom0.sh` QUBES_PKGS includes `net-proxy/qubes-firewall`,
      `sys-apps/qubes-input-proxy`, `gui-apps/qubes-manager`
- [x] `bootstrap-dom0.sh` rc-update loop uses `qubesdb` (not `qubes-db`)
      and includes `qubes-firewall`
- [x] `test-bootstrap.sh` QUBES_PKGS and QUBENTOO_ATOMS contain
      `sys-apps/qubes-core-qubesdb` (not `sys-apps/qubes-db`)
- [x] `build-gentoo-template.sh` accept_keywords uses `qubes-core-qubesdb`
- [x] `build-gentoo-template.sh` QUBES_GUEST_PKGS contains all 8 domU packages:
      qubes-core-qubesdb, qubes-libvchan, qubes-core-vchan-xen, qubes-core-agent,
      qubes-firewall, qubes-input-proxy, qubes-gui-common, qubes-gui-agent
- [x] `build-gentoo-template.sh` rc-update enables all domU services

## CI

- [x] `.github/workflows/overlay-check.yml` includes `emerge-pretend` job
      covering all dom0 packages
- [x] `.github/workflows/overlay-check.yml` includes `template-pretend` job
      covering all domU packages (separate job from emerge-pretend)
- [x] `.github/workflows/overlay-check.yml` includes `kernel-config-check` job
      verifying critical kernel flags
- [x] `.github/workflows/overlay-check.yml` includes `overlay-lint` job (pkgcheck)
- [x] All CI jobs in the `ci-passed` summary job's `needs:` list

---

**Last verified:** 2026-04-26 (session 5, applied all P0–P3 audit fixes)
