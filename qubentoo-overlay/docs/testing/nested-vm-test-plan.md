# Nested VM Test Plan — Qubentoo dom0

This document describes how to validate the Qubentoo bootstrap sequence
inside a KVM/QEMU virtual machine before committing to real hardware.

> **Key limitation:** Xen cannot run as dom0 under KVM in a nested
> virtualisation stack for production use. What you *can* fully test inside
> KVM is everything up to the point of actually booting Xen: the emerge
> sequence, OpenRC service startup, GRUB config generation, and kernel config
> merging. Xen boot itself requires real hardware or a bare-metal hypervisor
> host.

---

## 1. Setting up the KVM test environment

### 1.1 Create a test VM

```bash
# On the KVM host (your current machine)
# Allocate ≥40 GiB disk; Xen + Qubes build needs space
qemu-img create -f qcow2 /var/lib/libvirt/images/qubentoo-test.qcow2 50G

# Download the Gentoo hardened-openrc minimal ISO
# Replace <date> with the latest from https://distfiles.gentoo.org/releases/amd64/autobuilds/
ISO="install-amd64-minimal-<date>T<time>Z.iso"
wget "https://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/${ISO}"

# Launch VM with nested virt flags for maximum CPU feature exposure
qemu-system-x86_64 \
  -enable-kvm \
  -cpu host,+vmx \          # expose VT-x to guest (enables nested virt flags in /proc/cpuinfo)
  -m 8192 \
  -smp 4 \
  -drive file=/var/lib/libvirt/images/qubentoo-test.qcow2,format=qcow2 \
  -cdrom "${ISO}" \
  -boot d \
  -net nic,model=virtio \
  -net user \
  -nographic \
  -serial mon:stdio
```

### 1.2 Inside the Gentoo installer: base setup

```bash
# Partition (adjust for your disk layout)
parted /dev/vda mklabel gpt
parted /dev/vda mkpart primary fat32 1MiB 513MiB   # EFI or BIOS boot
parted /dev/vda mkpart primary ext4  513MiB 100%
mkfs.vfat -F32 /dev/vda1
mkfs.ext4 /dev/vda2

mount /dev/vda2 /mnt/gentoo
mkdir -p /mnt/gentoo/boot/efi
mount /dev/vda1 /mnt/gentoo/boot/efi

# Download and extract stage3 (hardened-openrc)
cd /mnt/gentoo
wget <stage3-amd64-hardened-openrc-*.tar.xz URL>
tar xpJf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner

# Bind mounts and chroot
mount --rbind /proc /mnt/gentoo/proc
mount --rbind /sys  /mnt/gentoo/sys
mount --rbind /dev  /mnt/gentoo/dev
cp /etc/resolv.conf /mnt/gentoo/etc/
chroot /mnt/gentoo /bin/bash --login
```

### 1.3 Clone the overlay inside the chroot

```bash
# Inside the chroot
emerge --sync
emerge app-eselect/eselect-repository dev-vcs/git

git clone https://github.com/qubentoo/qubentoo-overlay.git /root/qubentoo-overlay
# Or if local:
# Copy via: cp -r /path/on/host /mnt/gentoo/root/qubentoo-overlay  (before chroot)

eselect repository create qubentoo /root/qubentoo-overlay
```

---

## 2. Validation checklist

Work through each item in order. Mark each ✓ before proceeding to the next.

### Stage A — Portage and overlay

- [ ] **A1** Stage3 boots and bash prompt is available inside chroot
- [ ] **A2** `emerge-webrsync` or `emaint sync -a` completes without errors
- [ ] **A3** `eselect repository list` shows `qubentoo` with status `[enabled]`
- [ ] **A4** `portageq get_repo_path / qubentoo` returns `/root/qubentoo-overlay`
- [ ] **A5** `eselect profile set default/linux/amd64/23.0/hardened` succeeds
- [ ] **A6** `emerge --info` shows `USE="... hardened openrc xen ... -systemd ..."`

### Stage B — Dependency dry run

- [ ] **B1** `make dry-run` (or `bash scripts/test-bootstrap.sh`) exits 0
- [ ] **B2** No `::gentoo` packages in pretend output for Qubes atoms
- [ ] **B3** Python single target is `python3_11` across all packages
- [ ] **B4** No `BLOCK` lines in pretend output
- [ ] **B5** `make preflight` exits 0 (or exits 1 only for Xen boot — expected inside KVM)

### Stage C — Individual package builds

- [ ] **C1** `emerge sys-apps/qubes-db` builds and installs
  ```bash
  emerge sys-apps/qubes-db && einfo "qubes-db OK"
  ```
- [ ] **C2** `qubesdb-daemon --help` runs without error
- [ ] **C3** `rc-update add qubes-db default` succeeds
- [ ] **C4** `rc-service qubes-db start` — starts (may fail if xenstore not running; expected)
  - Expected output: `* Starting Qubes guest agent ...`
  - If it reports `xenstored not running` — that is correct behaviour for a non-Xen kernel

- [ ] **C5** `emerge sys-apps/qubes-core-vchan-xen` builds
- [ ] **C6** `emerge sys-apps/qubes-libvchan` builds, `libvchan.so` present in `/usr/lib/`
- [ ] **C7** `emerge dev-python/qubesdb` builds Python extension
  ```bash
  python3 -c "import qubesdb; print('qubesdb import OK')"
  ```

### Stage D — Xen build (longest step)

> **Time estimate on typical hardware:**
>
> | Hardware | Xen hypervisor | Xen tools | Total |
> |----------|---------------|-----------|-------|
> | 4-core @ 3 GHz, 8 GiB RAM | ~25 min | ~40 min | ~65 min |
> | 8-core @ 4 GHz, 16 GiB RAM | ~12 min | ~20 min | ~32 min |
> | 16-core @ 4 GHz, 32 GiB RAM | ~7 min | ~12 min | ~19 min |
>
> Inside a KVM VM, add ~30–50% to the above estimates due to
> virtualisation overhead.

- [ ] **D1** `emerge app-emulation/xen` completes (hypervisor only)
- [ ] **D2** `/usr/lib/xen/boot/xen.gz` or `/usr/lib/xen/boot/xen-<ver>.gz` exists
- [ ] **D3** `emerge app-emulation/xen-tools` completes (xl, xenstore, xenstored)
- [ ] **D4** `xl info` — will fail with "cannot open /proc/xen/capabilities" inside KVM; that is expected
- [ ] **D5** `xenstored --help` runs without error
- [ ] **D6** `rc-update add xenstored sysinit` and `rc-update add xencommons sysinit` succeed

### Stage E — GRUB configuration

- [ ] **E1** `emerge sys-boot/grub:2` with `GRUB_PLATFORMS="xen xen-32 pc"` (or `efi-64`)
- [ ] **E2** `grub-install` completes (BIOS: `/dev/vda`; EFI: `--target=x86_64-efi`)
- [ ] **E3** `grub-mkconfig -o /boot/grub/grub.cfg` generates config
- [ ] **E4** `grep -i xen /boot/grub/grub.cfg` shows a multiboot2 entry
  ```
  Expected lines:
    multiboot2  /boot/xen-4.17.5.gz placeholder
    module2     /boot/vmlinuz-...   placeholder root=...
    module2     /boot/initramfs-... placeholder
  ```

### Stage F — OpenRC runlevel check

- [ ] **F1** `rc-update show sysinit` lists `xenstored` and `xencommons`
- [ ] **F2** `rc-update show default` lists `xenconsoled`, `xendomains`,
  `qubes-db`, `qubesd`, `qubes-core`, `qubes-rpc-proxy`, `qubes-gui-daemon`
- [ ] **F3** `rc-status` shows expected runlevel assignments

### Stage G — Xen boot (real hardware or bare-metal VM host only)

> These steps **cannot** be completed inside KVM. They require a machine
> booting the Gentoo dom0 kernel directly under Xen as the hypervisor.

- [ ] **G1** Machine boots to GRUB, Xen entry is the default
- [ ] **G2** Xen loads, Linux kernel and initramfs load as modules
- [ ] **G3** dom0 boots to login prompt
- [ ] **G4** `xl info` reports Xen version, memory, and dom0
- [ ] **G5** `xenstore-ls /` lists root xenstore entries
- [ ] **G6** `rc-service xenstored status` → started
- [ ] **G7** `rc-service qubes-db status` → started
- [ ] **G8** `rc-service qubesd status` → started

---

## 3. Known gotchas

### Gotcha 1 — Xen 4.17 + Linux 6.6: `CONFIG_XEN_PVCALLS_FRONTEND`

**Symptom:** dom0 hangs at boot after "Xen: initializing" message.

**Cause:** `CONFIG_XEN_PVCALLS_FRONTEND=y` in Linux 6.6 conflicts with
Xen 4.17's PVCALLS socket backend initialisation order.

**Fix:** Ensure this is in the kernel config (it is in `qubentoo-dom0.config`):
```
# CONFIG_XEN_PVCALLS_FRONTEND is not set
```

Verify with:
```bash
zcat /proc/config.gz | grep PVCALLS
# Must show: # CONFIG_XEN_PVCALLS_FRONTEND is not set
```

---

### Gotcha 2 — QubesDB socket path: 4.1 vs 4.2

**Symptom:** `qubesdb-daemon` starts but `qubesdb-read` or Python `import qubesdb`
cannot find the socket.

**Cause:** Qubes 4.1 used `/var/run/qubesdb.sock`; Qubes 4.2 uses
`/run/qubes/qubesdb.sock`. The Qubentoo overlay is pinned to 4.2.

**Fix:** Ensure `/etc/conf.d/qubes-agent` contains:
```sh
QUBESDB_SOCKET="/run/qubes/qubesdb.sock"
```
And that `/run/qubes/` directory is created with correct permissions.
The `qubes-agent` and `qubes-db` OpenRC scripts both call:
```sh
checkpath -d -m 0755 /run/qubes
```

If you see the old path hardcoded anywhere in upstream source, patch it:
```bash
grep -r '/var/run/qubesdb' /usr/lib/qubes/  # should return nothing
```

---

### Gotcha 3 — OpenRC `depend()` evaluated at start, not install time

**Symptom:** `qubes-gui-agent` or `qubes-gui-daemon` fails to start with
"service not found" even though the DM is installed.

**Cause:** OpenRC resolves `depend()` when the service is *started*, not
when it is installed. If the display manager package was installed *after*
the qubes-gui-agent was enabled via `rc-update`, OpenRC may not re-read
the conf.d variable.

**Fix:**
1. Verify the DM OpenRC service name matches exactly:
   ```bash
   ls /etc/init.d/ | grep -E 'xdm|lightdm|sddm|gdm'
   ```
2. Verify `QUBES_GUI_DM` in conf.d matches that exact name:
   ```bash
   grep QUBES_GUI_DM /etc/conf.d/qubes-gui-agent
   ```
3. Restart the service after any conf.d change:
   ```bash
   rc-service qubes-gui-agent restart
   ```

The `start_pre()` function in the init script will warn if the DM service
is not currently running when `qubes-gui-agent` starts.

---

### Gotcha 4 — Missing `/proc/xen` inside KVM

**Symptom:** `xenstored`, `xencommons`, `qubes-db` all report errors about
`/proc/xen` not existing.

**Cause:** `/proc/xen` (xenfs) is only present on a Xen dom0 kernel.
Inside KVM, the running kernel has no Xen support.

**This is expected during KVM testing.** The OpenRC scripts detect this and
emit a warning rather than failing hard:
```sh
ewarn "Could not mount xenfs — is this a Xen dom0 kernel?"
```

To verify the scripts themselves are syntactically correct without xenfs:
```bash
# Syntax check only (does not run)
bash -n /etc/init.d/xenstored
bash -n /etc/init.d/qubes-db
bash -n /etc/init.d/qubesd
echo "All init scripts: syntax OK"
```

---

### Gotcha 5 — EFI Xen boot requires `xen.efi`, not just `xen.gz`

**Symptom:** GRUB shows an EFI entry but fails to boot Xen.

**Cause:** On EFI systems, GRUB's `multiboot2` command loads `xen.gz` in
BIOS mode. EFI systems require GRUB to chainload `xen.efi` directly.

**Fix:**
```bash
# Copy the EFI binary (built by app-emulation/xen)
cp /usr/lib/xen/boot/xen.efi /boot/efi/EFI/qubentoo/xen.efi

# /boot/grub/grub.cfg should contain (grub-mkconfig generates this
# if GRUB_PLATFORMS includes 'xen' and 'efi-64'):
#
#   insmod xen_efi
#   xen /EFI/qubentoo/xen.efi placeholder dom0_mem=4096M
#   module2 /boot/vmlinuz-... placeholder root=...
#   module2 /boot/initramfs-...
```

See [docs/display-manager.md](../display-manager.md) and the
[Gentoo Xen wiki](https://wiki.gentoo.org/wiki/Xen#UEFI) for full details.

---

## 4. Quick KVM launch script

Save this as `scripts/launch-test-vm.sh` for convenience:

```bash
#!/usr/bin/env bash
# Quick KVM VM for Qubentoo testing
IMG="${1:-/var/lib/libvirt/images/qubentoo-test.qcow2}"
MEM="${2:-8192}"
SMP="${3:-4}"

[[ -f "${IMG}" ]] || { echo "Image not found: ${IMG}"; exit 1; }

exec qemu-system-x86_64 \
  -enable-kvm \
  -cpu host,+vmx \
  -m "${MEM}" \
  -smp "${SMP}" \
  -drive "file=${IMG},format=qcow2,if=virtio" \
  -net nic,model=virtio \
  -net user,hostfwd=tcp::2222-:22 \
  -nographic \
  -serial mon:stdio
```

SSH into the VM once sshd is configured:
```bash
ssh -p 2222 root@localhost
```
