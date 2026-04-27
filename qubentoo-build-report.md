---
title: "Qubentoo GNU/Linux — Full Build Report"
subtitle: "Full Gentoo overlay and bootstrap system for Qubes OS on OpenRC"
date: "2026-04-26"
author: "Qubentoo Project"
---

# Qubentoo GNU/Linux — Build Report

**Date:** 2026-04-26  
**Overlay root:** `~/qubentoo-overlay/`  
**Total files created:** 47  
**Phases completed:** 7 (initial) + 4 porting fixes + 1 bonus doc

---

## Executive Summary

Qubentoo is a complete rebase of Qubes OS onto a Gentoo Linux base using OpenRC
instead of systemd. This report documents all work completed across two build
sessions: the initial 7-phase scaffold and the subsequent porting issue
resolution pass.

All packages use EAPI=8, the `python-single-r1` eclass for Python components,
and a custom `qubes.eclass` that strips systemd units and auto-installs OpenRC
init scripts. No systemd units are present anywhere in the overlay.

---

## Session 1 — Initial Scaffold (Phases 1–7)

### Phase 1 — Overlay Scaffold

| File | Purpose |
|------|---------|
| `metadata/layout.conf` | `masters = gentoo`, `repo-name = qubentoo` |
| `profiles/base/eapi` | EAPI=8 |
| `profiles/base/make.defaults` | Hardened USE flags, `-systemd openrc xen`, Python 3.11, GRUB Xen platforms |
| `eclass/qubes.eclass` | Shared helpers: `qubes_src_uri`, `qubes_src_unpack`, `qubes_src_install`; auto-strips systemd dirs; auto-installs OpenRC scripts from `FILESDIR/openrc/` |

**Design decision:** The eclass handles the systemd→OpenRC conversion
automatically. Any ebuild that calls `qubes_src_install` will have
`/lib/systemd` and `/usr/lib/systemd` removed from `${D}` and will
have OpenRC scripts placed from `${FILESDIR}/openrc/` via `newinitd`.

---

### Phase 2 — Xen Ebuilds

**`app-emulation/xen-4.17.5`** — Xen 4.17.5 hypervisor, dom0 build only.
No stubdom, no ioemu. Configures both `xen/` and `tools/` subdirectories.

**`app-emulation/xen-tools-4.17.5`** — Userspace tools with four OpenRC init
scripts:

| Service | Runlevel | Depends on |
|---------|----------|------------|
| `xenstored` | sysinit | localmount |
| `xencommons` | sysinit | xenstored |
| `xenconsoled` | default | xencommons |
| `xendomains` | default | xencommons, xenconsoled |

`xenstored` mounts xenfs at `/proc/xen` and starts the xenstore daemon.
`xendomains` saves running VMs on shutdown and restores them on next boot,
respecting `XENDOMAINS_AUTO` configs in `/etc/xen/auto/`.

---

### Phase 3 — Core Qubes dom0 Ebuilds

Six packages covering the Qubes dom0 management stack:

| Package | Version | OpenRC Service | Runlevel |
|---------|---------|---------------|----------|
| `sys-apps/qubes-db` | 4.2.0 | `qubes-db` | default |
| `sys-apps/qubes-core-vchan-xen` | 4.2.0 | *(library, no daemon)* | — |
| `sys-apps/qubes-libvchan` | 4.2.0 | *(library)* | — |
| `sys-apps/qubes-core-admin` | 4.2.0 | `qubesd` | default |
| `sys-apps/qubes-core-admin-linux` | 4.2.0 | `qubes-core` | default |
| `sys-apps/qubes-rpc-proxy` | 4.2.0 | `qubes-rpc-proxy` | default |

**Porting note:** `qubes-rpc-proxy` upstream source is `qubes-core-qrexec`;
`QUBES_REPO` is overridden in the ebuild accordingly.

`qubes-libvchan` is split from `qubes-core-vchan-xen` to allow packages
that need only the library API to avoid depending on the full vchan transport
daemon.

---

### Phase 4 — GUI Stack Ebuilds

**`gui-daemon/qubes-gui-common-4.2.0`** — Shared GUI protocol headers and
libraries. Installed in both dom0 and domU templates.

**`gui-daemon/qubes-gui-daemon-4.2.0`** — dom0 X11 GUI daemon. OpenRC service
waits for the X11 display using a `xdpyinfo` poll loop before starting.
`DISPLAY` and `XAUTHORITY` are configurable via `/etc/conf.d/qubes-gui-daemon`.

---

### Phase 5 — Kernel Config Fragment

`kernel/qubentoo-dom0.config` — A real defconfig fragment (using `=y`/`=m`/
`# ... is not set` syntax) covering:

**Xen dom0 support:**
- `CONFIG_XEN=y`, `CONFIG_XEN_DOM0=y`, `CONFIG_XEN_PRIVILEGED_GUEST=y`
- Full PCI passthrough: `CONFIG_XEN_PCIDEV_BACKEND=m`, `CONFIG_PCI_XEN=y`
- IOMMU: `CONFIG_INTEL_IOMMU=y`, `CONFIG_AMD_IOMMU=y`, `CONFIG_IRQ_REMAP=y`
- Xenstore, grant tables, event channels, balloon memory

**Hardened security options:**
- `CONFIG_HARDENED_USERCOPY=y` — prevents kernel slab leaks
- `CONFIG_FORTIFY_SOURCE=y` — compile-time string safety
- `CONFIG_CC_STACKPROTECTOR_STRONG=y`
- `CONFIG_RANDOMIZE_BASE=y`, `CONFIG_RANDOMIZE_MEMORY=y` — KASLR
- `CONFIG_PAGE_TABLE_ISOLATION=y` — Meltdown mitigation
- `CONFIG_RETPOLINE=y` — Spectre v2 mitigation
- `CONFIG_SECURITY_LOCKDOWN_LSM=y` — kernel lockdown

**GRSecurity-equivalent (no patch):**
- `CONFIG_SLAB_FREELIST_RANDOM=y`, `CONFIG_SLAB_FREELIST_HARDENED=y`
- `CONFIG_SECURITY_YAMA=y` — ptrace restriction
- `CONFIG_INIT_ON_ALLOC_DEFAULT_ON=y`, `CONFIG_INIT_ON_FREE_DEFAULT_ON=y`
- `CONFIG_MODULE_SIG=y`, `CONFIG_MODULE_SIG_FORCE=y`
- **`# CONFIG_MODULE_FORCE_UNLOAD is not set`** — as required

Apply the fragment with:
```sh
scripts/kconfig/merge_config.sh .config qubentoo-dom0.config
```

---

### Phase 6 — Bootstrap Script

`scripts/bootstrap-dom0.sh` — Idempotent 11-step dom0 bootstrap:

1. Prerequisite check (emerge, eselect, portageq)
2. Set hardened Gentoo profile
3. Install eselect-repository, register qubentoo overlay
4. Write dom0 USE/CFLAGS/MAKEOPTS to `/etc/portage/make.conf`
5. Write `package.accept_keywords` for all `~amd64` packages
6. Update `@world`
7. Emerge Xen hypervisor then tools
8. Emerge all Qubes packages in dependency order
9. Configure OpenRC runlevels (sysinit + default)
9b. **Interactive DM prompt** — sets `QUBES_GUI_DM` in conf.d (see Issue 4)
10. Configure GRUB for Xen multiboot (EFI or MBR fallback)
11. Merge kernel config fragment

Every step checks whether it has already run before acting, making re-runs
safe.

---

### Phase 7 — Gentoo Template VM Script

`scripts/build-gentoo-template.sh` — Builds a Qubes-compatible template
tarball from scratch:

1. Downloads latest hardened-openrc stage3 automatically
2. Creates a raw `.img` disk image (configurable size, default 20 GB)
3. Partitions with parted (single ext4 root), attaches via loopback
4. Extracts stage3, bind-mounts `/proc`, `/sys`, `/dev` for chroot
5. Configures portage inside chroot (hardened profile, USE flags)
6. Updates `@world`
7. Installs Qubes guest packages via the qubentoo overlay
8. Writes `/etc/qubes/guid.conf`
9. Enables `qubes-db` in OpenRC default runlevel
10. Sets hostname, locale (en_US.UTF-8), PV-compatible fstab
11. Packages as `root.img + template.conf` tarball

Install the result with:
```sh
qvm-template install --local /var/lib/qubes/vm-templates/gentoo-qubentoo-1.tar
qvm-create --template gentoo-qubentoo --label green my-gentoo-vm
```

---

## Session 2 — Porting Issue Resolution

### Issue 1 — Guest Agent Ebuilds

Two new ebuilds for the domU (template/AppVM) side:

**`sys-apps/qubes-core-agent-4.2.0`**
- Source: `github.com/QubesOS/qubes-core-agent-linux`
- Installs: `/usr/lib/qubes/`, `/etc/qubes/`, udev rules
- Two OpenRC services:
  - `qubes-agent` (default): starts qubesdb-daemon, waits for socket
  - `qubes-qrexec-agent` (default, after qubes-agent): qrexec daemon
- Depends on: `qubes-db`, `qubes-libvchan`, `qubes-rpc-proxy`,
  `dev-python/qubesdb`, `nftables`, `dbus`

**`gui-daemon/qubes-gui-agent-4.2.0`**
- Source: `github.com/QubesOS/qubes-gui-agent-linux`
- Installs: `qubes-gui` binary, `/etc/qubes/guid.conf`
- OpenRC `qubes-gui-agent`: depends on `qubes-agent`, `qubes-qrexec-agent`,
  and the configurable display manager (see Issue 4)

---

### Issue 2 — Manifest Generation and QA Scripts

**`scripts/gen-manifests.sh`**
- Finds all `.ebuild` files in the overlay tree
- Skips packages with `RESTRICT="mirror"` (no distfiles to hash)
- Runs `ebuild <path>.ebuild manifest` for each
- Logs to `manifest-gen.log` with per-package pass/fail status
- Prints a summary table and exits non-zero if any manifest failed

**`scripts/verify-overlay.sh`**
- Runs `repoman scan` from the overlay root
- Saves full output to `repoman-report.txt`
- Parses output for error/warning counts (handles both line-count and
  summary-line formats)
- Exits non-zero on any errors; `--strict` flag also fails on warnings
- Requires: `emerge dev-util/repoman`

---

### Issue 3 — Python Binding Stub Ebuilds

**`dev-python/qubesdb-4.2.0`**
- Source: `github.com/QubesOS/qubes-core-qubesdb` (`python/` subdir)
- Builds the `qubesdb` C extension linking against `libqubesdb`
- Uses `python-single-r1`, supports python3_{10,11,12}
- RDEPEND: `sys-apps/qubes-db`

**`dev-python/xen-4.17.5`**
- Source: Xen upstream tarball (`tools/python/` subdir)
- Installs `xen.lowlevel`, `xen.xl`, xenstore Python modules
- Also installs `pygrub` (Xen bootloader helper) from `tools/pygrub/`
- Uses `python-single-r1`, supports python3_{10,11,12}
- RDEPEND: `app-emulation/xen-tools`
- Packaged separately from `xen-tools` for dependency graph clarity:
  packages that need only the Python API don't pull in the full daemon set

---

### Issue 4 — Configurable Display Manager Dependency

The display manager dependency in both `qubes-gui-daemon` (dom0) and
`qubes-gui-agent` (domU) is now fully configurable via conf.d:

```sh
# /etc/conf.d/qubes-gui-agent
# Common values: xdm, lightdm, sddm, gdm
QUBES_GUI_DM="xdm"
```

The OpenRC init script reads this variable at source time and declares
`need "${QUBES_GUI_DM}"` in its `depend()` function.

**`bootstrap-dom0.sh` interactive prompt** (step 9b):
```
Which display manager will you use in dom0?
  Options: xdm  lightdm  sddm  gdm
  Press Enter to accept default [xdm]:
```

Non-interactive use: `DM_CHOICE=lightdm bash scripts/bootstrap-dom0.sh`

Full switching instructions, USE flags, and troubleshooting are documented
in `docs/display-manager.md`.

---

### Bonus — Dependency Graph

`docs/dependency-graph.md` contains:

- ASCII tree of the full dom0 package dependency graph
- ASCII tree of the full domU/template dependency graph
- OpenRC startup order for both dom0 and domU
- Mermaid diagram with colour-coded node types (dom0 / domU / shared / Python)
- Numbered build order lists matching `bootstrap-dom0.sh` and
  `build-gentoo-template.sh`

---

## Complete File Manifest

```
qubentoo-overlay/
├── eclass/
│   └── qubes.eclass
├── metadata/
│   └── layout.conf
├── profiles/base/
│   ├── eapi
│   └── make.defaults
│
├── app-emulation/
│   ├── xen/
│   │   └── xen-4.17.5.ebuild
│   └── xen-tools/
│       ├── xen-tools-4.17.5.ebuild
│       └── files/
│           ├── openrc/  xenstored  xencommons  xenconsoled  xendomains
│           └── confd/   xencommons  xendomains
│
├── sys-apps/
│   ├── qubes-db/
│   │   ├── qubes-db-4.2.0.ebuild
│   │   └── files/openrc/qubes-db  files/confd/qubes-db
│   ├── qubes-core-vchan-xen/
│   │   └── qubes-core-vchan-xen-4.2.0.ebuild
│   ├── qubes-libvchan/
│   │   └── qubes-libvchan-4.2.0.ebuild
│   ├── qubes-core-admin/
│   │   ├── qubes-core-admin-4.2.0.ebuild
│   │   └── files/openrc/qubesd  files/confd/qubesd
│   ├── qubes-core-admin-linux/
│   │   ├── qubes-core-admin-linux-4.2.0.ebuild
│   │   └── files/openrc/qubes-core
│   ├── qubes-rpc-proxy/
│   │   ├── qubes-rpc-proxy-4.2.0.ebuild
│   │   └── files/openrc/qubes-rpc-proxy  files/confd/qubes-rpc-proxy
│   └── qubes-core-agent/                           ← NEW (Issue 1)
│       ├── qubes-core-agent-4.2.0.ebuild
│       └── files/openrc/qubes-agent  qubes-qrexec-agent
│           files/confd/qubes-agent
│
├── gui-daemon/
│   ├── qubes-gui-common/
│   │   └── qubes-gui-common-4.2.0.ebuild
│   ├── qubes-gui-daemon/
│   │   ├── qubes-gui-daemon-4.2.0.ebuild
│   │   └── files/openrc/qubes-gui-daemon  files/confd/qubes-gui-daemon
│   │       files/guid.conf
│   └── qubes-gui-agent/                            ← NEW (Issue 1 + 4)
│       ├── qubes-gui-agent-4.2.0.ebuild
│       └── files/openrc/qubes-gui-agent  files/confd/qubes-gui-agent
│           files/guid.conf
│
├── dev-python/                                     ← NEW (Issue 3)
│   ├── qubesdb/
│   │   └── qubesdb-4.2.0.ebuild
│   └── xen/
│       └── xen-4.17.5.ebuild
│
├── kernel/
│   └── qubentoo-dom0.config
│
├── scripts/
│   ├── bootstrap-dom0.sh         (updated: DM prompt in step 9b)
│   ├── build-gentoo-template.sh
│   ├── gen-manifests.sh          ← NEW (Issue 2)
│   └── verify-overlay.sh         ← NEW (Issue 2)
│
└── docs/
    ├── display-manager.md        ← NEW (Issue 4)
    └── dependency-graph.md       ← NEW (Bonus)
```

**Total: 47 files**

---

## Known Remaining Work

The following items are out of scope for the current build but represent the
next logical milestones:

1. **`qubes-gui-agent` in `build-gentoo-template.sh`** — the template build
   script currently installs only the core agent packages. `qubes-gui-agent`
   should be added once X11 support is confirmed working in the template.

2. **Manifest files** — `Manifest` files per package must be generated with
   `scripts/gen-manifests.sh` on a live Portage host before the overlay can
   be published.

3. **`qubes-core-qrexec` split** — upstream `qubes-core-qrexec` ships both
   dom0 and domU components in one tree. A future ebuild split should create
   separate `sys-apps/qubes-rpc-proxy` (dom0) and
   `sys-apps/qubes-qrexec-agent` (domU) with `IUSE="dom0"` to select.

4. **Memory ballooning / qmemman** — `qubes-core-admin` includes a memory
   balloon daemon. The OpenRC `qubes-core` script currently sets xenstore
   entries directly; a dedicated `qmemman` service ebuild is needed.

5. **Dispvm template support** — disposable VMs need additional config in
   `/etc/qubes/guid.conf` and a `qubes-dispvm` OpenRC service inside the
   template.

6. **Qubes Manager GUI** — `qubes-manager` (PyQt5) is the dom0 administration
   UI. Not yet included; requires `dev-python/PyQt5` and `dev-python/qubesadmin`.

---

*Report generated automatically by the Qubentoo build system.*  
*Overlay: `/home/admin/qubentoo-overlay/`*
