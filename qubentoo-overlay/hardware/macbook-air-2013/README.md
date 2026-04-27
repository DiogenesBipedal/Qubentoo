# Qubentoo on MacBook Air Mid-2013 (A1465 / A1466)

Complete installation and hardware support guide for running Qubentoo dom0
on the 11" and 13" MacBook Air Mid-2013.

---

## Hardware compatibility

| Component | Status | Notes |
|-----------|--------|-------|
| CPU (Haswell i5-4250U / i7-4650U) | Working | VT-x + VT-d present |
| Intel HD Graphics 5000 (i915) | Working | Full KMS, requires i915 module |
| Apple PCIe SSD (AHCI → /dev/sda) | Working | AHCI protocol, NOT NVMe |
| Apple Multi-Touch trackpad (BCM5974) | Working | USB HID via `mouse_bcm5974` |
| Internal keyboard | Working | USB HID, `hid_apple` quirks |
| Broadcom BCM4360 WiFi | Partial | Needs `net-wireless/broadcom-sta` (wl driver); brcmfmac has limited support |
| Bluetooth (BCM20702A0 USB) | Working | `btusb` + firmware from `sys-firmware/broadcom-bt-firmware` |
| Thunderbolt 2 (Intel DSL5320) | Working | `thunderbolt` module |
| Intel HDA audio (Cirrus Logic CS4208) | Working | `snd_hda_codec_cirrus` |
| Apple SMC (fan, temp, kbd backlight) | Working | `applesmc` module |
| Display backlight | Working | `backlight_apple` module |
| FaceTime HD camera | Working | `uvcvideo` (USB) |
| SD card reader | Working | `sdhci_pci` |
| IOMMU (VT-d) | Working | Requires `intel_iommu=on` in kernel cmdline |
| Sleep / wake | Partial | S3 works; S4 (hibernate) needs testing |

---

## Prerequisites

Before starting:

1. **Back up all macOS data.** This process erases the entire SSD.
2. **Check your exact model:**
   - 11": MacBook Air (11-inch, Mid 2013) — Model A1465
   - 13": MacBook Air (13-inch, Mid 2013) — Model A1466
3. **Have a USB Ethernet adapter or USB-A stick ready.**
   WiFi won't work until `broadcom-sta` is emerged during bootstrap.
   A Thunderbolt-to-Ethernet adapter (Apple or third-party) is strongly recommended.
4. **SSD device:** The Apple PCIe SSD appears as `/dev/sda` (AHCI, not NVMe).
   It does **not** appear as `/dev/nvme0n1`.

---

## Step 1 — Create a Gentoo live USB

On any Linux machine:

```bash
# Download the Gentoo minimal install ISO
wget https://distfiles.gentoo.org/releases/amd64/autobuilds/current-install-amd64-minimal/install-amd64-minimal-*.iso

# Write to USB (replace /dev/sdX with your USB device)
dd if=install-amd64-minimal-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

---

## Step 2 — Boot the MacBook Air from USB

1. Hold **Option (⌥)** immediately after pressing the power button.
2. Select the **EFI Boot** entry (yellow USB icon) from the boot picker.
3. At the GRUB prompt, select the Gentoo minimal install.

> **Note:** If the USB doesn't appear, check that it was written correctly
> and is formatted as a bootable EFI device. Gentoo minimal ISOs are EFI-bootable.

---

## Step 3 — Network access on the live system

Before you can emerge anything you need network access:

**Option A — Thunderbolt / USB Ethernet (recommended):**
```bash
# The adapter appears as eth0 or enp0s... — bring it up:
ip link set eth0 up
dhcpcd eth0
```

**Option B — WiFi with wpa_supplicant on live system:**
The Gentoo minimal ISO includes `wpa_supplicant`. BCM4360 may work with the
firmware blob from linux-firmware:
```bash
modprobe brcmfmac
wpa_passphrase "YourSSID" "YourPassword" > /tmp/wpa.conf
wpa_supplicant -B -i wlan0 -c /tmp/wpa.conf
dhcpcd wlan0
```
If brcmfmac fails (common with BCM4360), the installer will add `broadcom-sta`
automatically during bootstrap.

---

## Step 4 — Partition and install

Run the Qubentoo disk installer:

```bash
# Clone the overlay
git clone https://github.com/DiogenesBipedal/Qubentoo.git /root/qubentoo-overlay

# Run the installer
# TARGET_DISK is /dev/sda — the Apple PCIe SSD
bash /root/qubentoo-overlay/scripts/install-qubentoo.sh \
    --disk /dev/sda \
    --hostname mymacbook \
    --timezone Europe/London \
    --dm xdm
```

Or with LUKS encryption:
```bash
bash /root/qubentoo-overlay/scripts/install-qubentoo.sh \
    --disk /dev/sda \
    --hostname mymacbook \
    --timezone UTC \
    --luks
```

The installer will:
1. Partition `/dev/sda` with GPT (EFI + boot + swap + root)
2. Download and extract a Gentoo hardened-openrc stage3
3. Chroot and run `bootstrap-dom0.sh`
4. Bootstrap detects Apple hardware and automatically:
   - Adds `--removable` to GRUB install (required for Apple EFI)
   - Adds `intel_iommu=on applesmc.power=1` to Linux kernel cmdline
   - Merges `kernel/qubentoo-apple-mba2013.config` into the kernel config
   - Emerges `net-wireless/broadcom-sta` for BCM4360 WiFi
   - Runs `apple-efi-setup.sh` to install xen.efi as `/EFI/BOOT/BOOTx64.EFI`

---

## Step 5 — Build the kernel

After bootstrap completes:

```bash
# From inside the chroot (bootstrap leaves you there), or after reboot to live:
make -C /root/qubentoo-overlay kernel
```

This:
1. Merges `qubentoo-dom0.config` + `qubentoo-apple-mba2013.config`
2. Verifies critical flags (XEN, XEN_DOM0, PVCALLS_FRONTEND disabled)
3. Builds and installs the kernel
4. Runs `grub-mkconfig`

---

## Step 6 — Apple EFI setup (if not done by bootstrap)

If bootstrap ran without a kernel in place, run the EFI setup after building the kernel:

```bash
bash /root/qubentoo-overlay/scripts/apple-efi-setup.sh
```

This installs:
- `/boot/efi/EFI/BOOT/BOOTx64.EFI` → `xen.efi` (Apple EFI fallback)
- `/boot/efi/EFI/BOOT/xen.cfg` → Xen boot config
- `/boot/efi/EFI/qubentoo/vmlinuz-*` → dom0 kernel
- `/boot/efi/EFI/qubentoo/initramfs-*` → dom0 initramfs

---

## Step 7 — First boot

1. Hold **Option (⌥)** on power-up.
2. Select **EFI Boot** (the Qubentoo entry, or the unlabeled EFI icon).
3. Xen should load, then the Linux dom0 kernel.

Verify Xen is running:
```bash
xl info | grep xen_version   # → Xen 4.17.x
xl list                      # → Domain-0 entry
```

---

## WiFi setup after first boot

During bootstrap, `broadcom-sta` is emerged and brcmfmac is blacklisted.
The `wl` module loads automatically. To connect to WiFi:

```bash
# Load wl module (should auto-load via udev)
modprobe wl

# Use wpa_supplicant
wpa_passphrase "YourSSID" "YourPassword" > /etc/wpa_supplicant/wpa_supplicant.conf
rc-service wpa_supplicant start
dhcpcd wlan0
```

> **Qubes note:** Once dom0 is running, assign the WiFi PCI device (`lspci | grep Broadcom`)
> to a dedicated NetVM using `qvm-pci`. Dom0 should not have network access in
> a fully configured Qubes system.

---

## Known issues and workarounds

### Boot hangs after "Xen 4.17.x"
CONFIG_XEN_PVCALLS_FRONTEND is enabled. This causes dom0 to hang at boot
with Xen 4.17 on Linux 6.6. Our kernel config explicitly disables it, but
verify:
```bash
grep PVCALLS /boot/config-$(uname -r)
# Must show: # CONFIG_XEN_PVCALLS_FRONTEND is not set
```

### GRUB menu missing Xen entry
Apple EFI may boot directly to GRUB without showing the Xen entry.
See [grub-xen-missing.md](../troubleshooting/grub-xen-missing.md).
The primary fix is `apple-efi-setup.sh` which bypasses GRUB entirely by
placing xen.efi at the Apple EFI fallback path.

### Fan running at full speed
The `applesmc` module is not loaded. After kernel build:
```bash
modprobe applesmc
# Make permanent:
echo "applesmc" >> /etc/modules-load.d/apple.conf
```

### Display backlight uncontrollable
`backlight_apple` module not loaded:
```bash
modprobe backlight_apple
# Then use: echo 800 > /sys/class/backlight/apple_backlight/brightness
# (max is typically 938 on 2013 MBA)
```

### No sound
CS4208 codec detected but no output:
```bash
modprobe snd_hda_codec_cirrus
# Check: aplay -l  (should show Intel HDA)
```

### WiFi not working after broadcom-sta emerge
```bash
# Verify brcmfmac is blacklisted
cat /etc/modprobe.d/broadcom-wl.conf
# Load wl explicitly
modprobe wl
# Check kernel log
dmesg | grep -i "wl\|broadcom"
```

---

## dom0 memory recommendation

The MacBook Air 2013 ships with 4 GB or 8 GB RAM.

- **4 GB model:** Set `DOM0_MEM_MB=2048` — leaves 2 GB for AppVMs
- **8 GB model:** Set `DOM0_MEM_MB=3072` — leaves 5 GB for AppVMs

```bash
# In /etc/default/grub, change:
GRUB_CMDLINE_XEN_DEFAULT="dom0_mem=2048M,max:2048M ..."
# Then: grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Assigning WiFi to a NetVM (post-install)

```bash
# Find the Broadcom PCIe address
lspci | grep Broadcom
# Example output: 03:00.0 Network controller: Broadcom BCM4360

# Assign to net-wifi VM (create it first with qvm-create)
qvm-pci attach net-wifi dom0:03_00.0 --persistent -o no-strict-reset=True
```

The `no-strict-reset=True` option is often needed for Broadcom cards which
do not support PCIe function-level reset cleanly.
