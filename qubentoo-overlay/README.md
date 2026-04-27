# Qubentoo GNU/Linux

**Qubes OS security architecture rebuilt on Gentoo Linux — OpenRC only, no systemd.**

[![CI](https://github.com/DiogenesBipedal/Qubentoo/actions/workflows/overlay-check.yml/badge.svg)](https://github.com/DiogenesBipedal/Qubentoo/actions/workflows/overlay-check.yml)
![Status: Alpha](https://img.shields.io/badge/status-alpha%2Fpre--boot-orange)
![Xen 4.17.5](https://img.shields.io/badge/xen-4.17.5-blue)
![EAPI 8](https://img.shields.io/badge/EAPI-8-green)

---

## What is Qubentoo?

Qubentoo is a Gentoo Linux overlay that reimplements the full [Qubes OS](https://www.qubes-os.org/)
security stack — Xen hypervisor, VM compartmentalisation, qrexec RPC, GUI multiplexing —
without systemd. Every service runs under OpenRC. The entire system compiles from source
against a hardened Gentoo profile.

**The goal:** a source-based, auditable, OpenRC-native OS where each application
lives in its own hardware-isolated VM, with the security guarantees of Qubes and
the flexibility of Gentoo.

---

## Architecture

```
GRUB / Xen EFI stub
  └── Xen 4.17.x hypervisor
        ├── dom0  — Gentoo hardened + OpenRC
        │     ├── qubesd         (admin daemon — manages all VMs)
        │     ├── qubes-gui-daemon  (X11 window multiplexer)
        │     ├── qubes-rpc-proxy   (qrexec policy engine)
        │     ├── qubes-firewall    (nftables NetVM / AppVM rules)
        │     └── xl / xenstore tools
        │
        └── domU  — Gentoo PV template VMs
              ├── qubes-core-agent    (guest-side VM agent)
              ├── qubes-gui-agent     (display protocol client)
              └── qubes-qrexec-agent  (inter-VM RPC)
```

---

## What works right now

| Component | State |
|-----------|-------|
| Overlay scaffold (metadata, eclass, profiles) | Complete |
| Xen 4.17.5 hypervisor ebuild | Complete |
| Xen tools ebuild (xl, xenstore, xendomains) | Complete |
| QubesDB daemon (`qubes-core-qubesdb`) | Complete |
| vchan transport + library | Complete |
| dom0 admin stack (qubesd, admin-linux, rpc-proxy) | Complete |
| GUI stack — dom0 daemon + domU agent | Complete |
| Qubes Manager GUI (`gui-apps/qubes-manager`) | Ebuild complete, untested |
| Input proxy (`sys-apps/qubes-input-proxy`) | Ebuild complete, untested |
| Firewall (`net-proxy/qubes-firewall`) | Ebuild complete, untested |
| Xen stubdom (`qubes-vmm-xen-stubdom-linux`) | Ebuild complete, RESTRICT=network-sandbox |
| Python bindings (qubesdb, xen) | Complete |
| Kernel config fragment (Linux 6.6 LTS + Xen dom0 hardening) | Complete |
| Bootstrap script (`bootstrap-dom0.sh`) | Complete — idempotent, HOSTNAME/TIMEZONE aware |
| Disk installer (`install-qubentoo.sh`) | Complete, untested on hardware |
| Gentoo domU template build script | Complete |
| Catalyst live ISO recipe | Skeleton — placeholder paths need updating |
| CI: emerge --pretend (dom0 + domU), kernel config check, pkgcheck | Passing |
| MacBook Air 2013 platform support | Kernel config + EFI setup complete |
| Xen boot on real hardware | **Not yet validated** |
| `qvm-*` management command suite | Not started |
| USB / audio qube configuration | Not started |

---

## Hardware support

### Generic x86-64

Any machine with:
- Intel VT-x or AMD-V
- IOMMU (VT-d / AMD-Vi) enabled in firmware
- UEFI firmware (legacy BIOS supported via GRUB multiboot2 fallback)

### MacBook Air (Mid 2013)

Full platform-specific support in `hardware/macbook-air-2013/`:

| Hardware | Status |
|----------|--------|
| Intel HD Graphics 5000 (i915) | Working |
| Apple PCIe SSD (AHCI) | Working — appears as `/dev/sda` |
| Apple Multi-Touch trackpad (BCM5974) | Working |
| BCM4360 WiFi | Partial — `brcmfmac` (open) or `broadcom-sta` (full) |
| Apple keyboard (HID) | Working |
| applesmc (fan, temp, backlight) | Working |
| Thunderbolt 2 | Working |
| CS4208 audio (Cirrus) | Working |

Apple EFI workaround: `apple-efi-setup.sh` installs `xen.efi` as
`/EFI/BOOT/BOOTx64.EFI`, bypassing Apple's refusal to honour named EFI entries.

---

## Quick start

### Prerequisites

- A machine with Intel VT-x or AMD-V and IOMMU enabled in firmware
- A booted Gentoo stage3 (`hardened/amd64/openrc` profile)
- Portage configured (`/etc/portage/make.conf`)

### 1. Clone and validate

```bash
git clone https://github.com/DiogenesBipedal/Qubentoo.git
cd Qubentoo

make preflight    # check CPU, IOMMU, kernel, disk space
make dry-run      # emerge --pretend full dom0 package set
```

### 2. Bootstrap dom0

```bash
sudo make bootstrap
# Prompts for confirmation, then installs all Qubes dom0 packages
# and configures OpenRC services
```

### 3. Build the dom0 kernel

```bash
sudo make kernel
# Merges kernel/qubentoo-dom0.config into your kernel source tree,
# builds, installs, and regenerates GRUB config
```

### 4. Build a Gentoo template VM

```bash
sudo make gentoo-template
# Produces: /var/lib/qubes/vm-templates/gentoo-qubentoo-1.tar
qvm-template install --local /var/lib/qubes/vm-templates/gentoo-qubentoo-1.tar
```

### MacBook Air 2013 — bare-metal install from live CD

```bash
sudo bash scripts/install-qubentoo.sh \
  --disk /dev/sda \
  --hostname qubentoo \
  --timezone America/New_York
# After bootstrap completes:
sudo bash hardware/macbook-air-2013/apple-efi-setup.sh
```

---

## Installer (full disk, live CD)

```bash
# Minimum — auto-detects partition layout
sudo bash scripts/install-qubentoo.sh --disk /dev/sda

# With all options
sudo bash scripts/install-qubentoo.sh \
  --disk /dev/sda \
  --hostname mymachine \
  --timezone Europe/Berlin \
  --dm lightdm \
  --luks          # enable LUKS full-disk encryption

# Or via make
sudo make install TARGET_DISK=/dev/sda HOSTNAME=mymachine TIMEZONE=UTC LUKS=1
```

---

## Makefile targets

| Target | Description |
|--------|-------------|
| `make preflight` | Check CPU, IOMMU, kernel readiness |
| `make dry-run` | `emerge --pretend` of full dom0 package set |
| `make manifests` | Generate `Manifest` files for all ebuilds |
| `make verify` | `repoman scan` / `pkgcheck` QA |
| `make verify-strict` | Same, fail on warnings |
| `make bootstrap` | Full dom0 install (root, confirms before running) |
| `make install` | Disk installer from live CD |
| `make kernel` | Build and install dom0 kernel from config fragment |
| `make gentoo-template` | Build Gentoo domU template tarball |
| `make all` | preflight + dry-run + manifests + verify |
| `make clean` | Remove generated log files |

---

## Repository layout

```
qubentoo-overlay/
├── Makefile
├── LICENSE                          ← GPL-2.0-only
├── eclass/qubes.eclass              ← shared ebuild helpers
├── metadata/layout.conf
├── profiles/base/
│
├── app-emulation/
│   ├── xen/                         ← Xen 4.17.5 hypervisor
│   ├── xen-tools/                   ← xl, xenstore, xendomains, xenconsoled
│   └── qubes-vmm-xen-stubdom-linux/ ← Xen stubdomain (optional, PCI passthrough)
│
├── sys-apps/
│   ├── qubes-core-qubesdb/          ← QubesDB C daemon
│   ├── qubes-core-vchan-xen/        ← vchan Xen transport
│   ├── qubes-libvchan/              ← vchan library
│   ├── qubes-core-admin/            ← qubesd
│   ├── qubes-core-admin-linux/      ← Linux dom0 specifics
│   ├── qubes-rpc-proxy/             ← qrexec policy engine
│   ├── qubes-core-agent/            ← domU guest agent
│   └── qubes-input-proxy/           ← input device isolation
│
├── gui-daemon/
│   ├── qubes-gui-common/
│   ├── qubes-gui-daemon/            ← dom0 X11 multiplexer
│   └── qubes-gui-agent/             ← domU display client
│
├── gui-apps/qubes-manager/          ← PyQt5 VM management GUI
├── net-proxy/qubes-firewall/        ← nftables firewall
├── dev-python/{qubesdb,xen}/        ← Python bindings
│
├── kernel/qubentoo-dom0.config      ← defconfig fragment (Linux 6.6 LTS)
│
├── hardware/
│   └── macbook-air-2013/
│       ├── README.md                ← hardware guide
│       ├── kernel.config            ← supplemental Apple hardware config
│       └── apple-efi-setup.sh       ← EFI fallback installer
│
├── scripts/
│   ├── preflight-check.sh
│   ├── bootstrap-dom0.sh
│   ├── build-gentoo-template.sh
│   ├── install-qubentoo.sh
│   ├── test-bootstrap.sh
│   ├── gen-manifests.sh
│   └── verify-overlay.sh
│
├── catalyst/qubentoo-livecd.spec    ← Catalyst ISO recipe skeleton
│
└── docs/
    ├── dependency-graph.md
    ├── display-manager.md
    ├── testing/
    │   ├── nested-vm-test-plan.md
    │   └── consistency-check.md
    └── troubleshooting/
        └── grub-xen-missing.md
```

---

## CI

GitHub Actions runs on every push and PR:

- **emerge-pretend** — `emerge --pretend` all dom0 packages in a hardened-openrc stage3 container
- **template-pretend** — `emerge --pretend` all domU packages
- **kernel-config-check** — verify `CONFIG_XEN=y`, `CONFIG_XEN_DOM0=y`, `CONFIG_XEN_PVCALLS_FRONTEND` unset, IOMMU flags set
- **openrc-syntax** — `bash -n` on all init scripts and conf.d files
- **python-compat-lint** — verify `PYTHON_COMPAT` in all Python ebuilds
- **overlay-lint** — `pkgcheck scan` (errors fail the build)
- **ci-passed** — summary gate job that all PRs must pass

---

## Roadmap

1. Validate Xen + dom0 boot on physical hardware
2. Smoke-test all OpenRC services (xenstored, xendomains, qubesd, gui-daemon)
3. Launch a domU AppVM and exercise qrexec copy-paste
4. Complete the `qvm-*` management command suite
5. Build and test live ISO via Catalyst
6. USB qube and audio qube configuration
7. LUKS + TPM measured-boot integration

---

## Contributing

Contributions welcome — especially boot reports on hardware, ebuild fixes, and
OpenRC service testing. Open an issue describing your hardware and which step
failed, or submit a PR with the fix.

Before submitting: run `make verify` and check `docs/testing/consistency-check.md`.

## License

Overlay ebuilds and scripts: [GPL-2.0-only](LICENSE)

Upstream Qubes OS components retain their own licenses (GPL-2, LGPL-2.1).
Gentoo infrastructure follows the Gentoo Foundation's licensing terms.
