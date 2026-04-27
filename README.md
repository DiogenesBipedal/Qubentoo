# Qubentoo GNU/Linux

**A full rebase of Qubes OS onto a Gentoo Linux base with OpenRC — no systemd.**

> **Status: Alpha / Pre-boot**
> The overlay scaffold, all ebuilds, and bootstrap scripts are complete.
> Xen boot on real hardware has not yet been validated.
> Contributions and testing reports welcome.

![overlay-check](https://github.com/qubentoo/qubentoo-overlay/actions/workflows/overlay-check.yml/badge.svg)

---

## What is Qubentoo?

Qubentoo takes the security architecture of [Qubes OS](https://www.qubes-os.org/)
(Xen hypervisor, compartmentalised VMs, qrexec RPC) and rebuilds it on top
of [Gentoo Linux](https://www.gentoo.org/) with:

- **OpenRC** instead of systemd — every service has a hand-written init script
- **Hardened Gentoo profile** — PIE, SSP, FORTIFY, RELRO by default
- **EAPI=8 ebuilds** — a proper Gentoo overlay, not a fork
- **Gentoo template VMs** — AppVMs built from hardened Gentoo stage3
- **No binary blobs** — everything compiled from source

### Architecture

```
GRUB (multiboot2)
  └── Xen 4.17.x hypervisor
        ├── dom0: Gentoo hardened + OpenRC
        │     ├── qubesd (core admin daemon)
        │     ├── qubes-gui-daemon (X11 window multiplexer)
        │     ├── qubes-rpc-proxy (qrexec policy engine)
        │     └── xl / xenstore tools
        └── domU: Gentoo PV template VMs
              ├── qubes-core-agent
              ├── qubes-gui-agent
              └── qubes-qrexec-agent
```

---

## Quick start

### Prerequisites

- A machine with Intel VT-x or AMD-V (hardware virtualisation)
- IOMMU enabled in BIOS (VT-d / AMD-Vi)
- A booted Gentoo stage3 (hardened/amd64/openrc profile)

### 1. Clone and validate

```bash
git clone https://github.com/qubentoo/qubentoo-overlay.git
cd qubentoo-overlay

make preflight    # check CPU, IOMMU, kernel, disk space
make dry-run      # emerge --pretend of full package set
```

### 2. Bootstrap dom0

```bash
sudo make bootstrap
# Prompts: "Type YES to continue"
# Asks: "Which display manager? [xdm/lightdm/sddm]"
```

### 3. Build a Gentoo template VM

```bash
sudo make gentoo-template
# Produces: /var/lib/qubes/vm-templates/gentoo-qubentoo-1.tar
qvm-template install --local /var/lib/qubes/vm-templates/gentoo-qubentoo-1.tar
```

---

## Repository layout

```
qubentoo-overlay/
├── Makefile                    ← make preflight / dry-run / bootstrap / ...
├── eclass/
│   └── qubes.eclass            ← shared build helpers for all Qubes packages
├── metadata/layout.conf
├── profiles/base/
│   ├── eapi                    ← EAPI=8
│   └── make.defaults           ← USE="hardened openrc -systemd xen ..."
│
├── app-emulation/
│   ├── xen/                    ← Xen 4.17.5 hypervisor (dom0, no stubdom)
│   └── xen-tools/              ← xl, xenstore, xenstored, xendomains
│
├── sys-apps/
│   ├── qubes-db/               ← QubesDB key-value store
│   ├── qubes-core-vchan-xen/   ← vchan transport
│   ├── qubes-libvchan/         ← vchan library
│   ├── qubes-core-admin/       ← qubesd (dom0 admin daemon)
│   ├── qubes-core-admin-linux/ ← Linux dom0 specifics
│   ├── qubes-rpc-proxy/        ← qrexec policy engine
│   └── qubes-core-agent/       ← domU guest agent
│
├── gui-daemon/
│   ├── qubes-gui-common/       ← shared GUI protocol headers
│   ├── qubes-gui-daemon/       ← dom0 X11 GUI daemon
│   └── qubes-gui-agent/        ← domU GUI agent
│
├── dev-python/
│   ├── qubesdb/                ← Python bindings for QubesDB
│   └── xen/                    ← Python bindings for Xen (xen.lowlevel, xen.xl)
│
├── kernel/
│   └── qubentoo-dom0.config    ← kernel defconfig fragment (Xen + hardened)
│
├── scripts/
│   ├── preflight-check.sh      ← hardware/kernel readiness check
│   ├── test-bootstrap.sh       ← emerge --pretend dry run
│   ├── bootstrap-dom0.sh       ← full dom0 install
│   ├── build-gentoo-template.sh← Gentoo domU template tarball
│   ├── gen-manifests.sh        ← generate Portage Manifest files
│   └── verify-overlay.sh       ← repoman QA scan
│
└── docs/
    ├── dependency-graph.md     ← full package dependency tree + Mermaid
    ├── display-manager.md      ← DM configuration guide
    └── testing/
        └── nested-vm-test-plan.md ← KVM pre-hardware test procedure
```

---

## Makefile targets

| Target | Description |
|--------|-------------|
| `make preflight` | Check CPU, IOMMU, kernel, and disk readiness |
| `make dry-run` | Validate dependency graph with `emerge --pretend` |
| `make manifests` | Generate `Manifest` files for all ebuilds |
| `make verify` | Run `repoman scan` QA check |
| `make verify-strict` | Same but fail on warnings too |
| `make bootstrap` | Full dom0 install (requires root + YES confirmation) |
| `make gentoo-template` | Build Gentoo domU template tarball |
| `make all` | preflight → dry-run → manifests → verify |
| `make clean` | Remove generated log files |

---

## Current status

| Component | Status |
|-----------|--------|
| Overlay scaffold (metadata, eclass, profiles) | ✅ Complete |
| Xen 4.17.5 ebuilds (hypervisor + tools) | ✅ Complete |
| Qubes dom0 ebuilds (6 packages) | ✅ Complete |
| Qubes domU agent ebuilds | ✅ Complete |
| GUI stack ebuilds (dom0 + domU) | ✅ Complete |
| Python binding stubs (qubesdb, xen) | ✅ Complete |
| Kernel config fragment | ✅ Complete |
| Bootstrap script | ✅ Complete |
| Gentoo template build script | ✅ Complete |
| Manifest generation | ⏳ Needs live Portage host |
| Xen boot on real hardware | ⏳ Not yet validated |
| Qubes Manager GUI | ❌ Not started |
| `qvm-*` command suite | ❌ Not started |
| USB / audio qube configuration | ❌ Not started |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to write a new ebuild,
the OpenRC service template, and the testing checklist before opening a PR.

## License

All overlay ebuilds and scripts are GPL-2.  
Upstream Qubes OS components retain their own licenses (GPL-2, LGPL-2.1).  
Gentoo infrastructure (eclass inheritance patterns) follows the Gentoo
Foundation's licensing terms.
