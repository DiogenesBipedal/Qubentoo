# Troubleshooting: Xen stanza missing from GRUB menu

After running `grub-mkconfig`, the boot menu has no Xen entry, or the system
boots the Linux kernel directly instead of Xen.

---

## 1. Why this happens

`grub-mkconfig` only generates a Xen multiboot2 entry when **all three** of
these conditions are true:

| Condition | What to check |
|-----------|---------------|
| `xen*.gz` exists under `/boot` | `ls /boot/xen*.gz` |
| `/etc/grub.d/20_linux_xen` is executable | `ls -l /etc/grub.d/20_linux_xen` |
| `GRUB_PLATFORMS` includes `xen` | `grep GRUB_PLATFORMS /etc/portage/make.conf` |

If any of these is missing, grub-mkconfig silently skips the Xen entry.

---

## 2. Verify xen.gz is in /boot

```bash
ls /boot/xen*.gz
```

Expected output (exact filename varies by build):

```
/boot/xen-4.17.gz
```

If the file is absent, copy it from the Xen install:

```bash
cp /usr/lib/xen/boot/xen.gz /boot/xen-4.17.gz
```

---

## 3. Verify grub.d script is executable

```bash
ls -l /etc/grub.d/20_linux_xen
```

If absent, the `sys-boot/grub` package was not built with `GRUB_PLATFORMS="xen"`.
Re-emerge with:

```bash
GRUB_PLATFORMS="xen xen-32 pc" emerge --oneshot sys-boot/grub:2
```

---

## 4. Manual GRUB stanza (fallback)

If auto-detection still fails, add this block to `/etc/grub.d/40_custom`,
replacing the filenames with the output of `ls /boot/`:

```
menuentry 'Qubentoo GNU/Linux (Xen 4.17)' {
    insmod part_gpt
    insmod ext2
    search --no-floppy --label --set=root boot
    multiboot2 /xen-4.17.gz dom0_mem=4096M,max:4096M dom0_max_vcpus=4 iommu=on
    module2 /vmlinuz-6.6-gentoo root=/dev/sda4 ro quiet
    module2 /initramfs-6.6-gentoo.img
}
```

Check actual filenames first:

```bash
ls /boot/xen*.gz /boot/vmlinuz* /boot/initramfs*
```

---

## 5. Re-generate GRUB config

After fixing the cause:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
grep -A5 'Xen\|xen' /boot/grub/grub.cfg   # verify entry appears
```

---

## 6. EFI systems

On UEFI, `xen.efi` must be in the EFI partition, and the grub stanza changes:

```bash
# Copy Xen EFI binary
cp /usr/lib/xen/boot/xen.efi /boot/efi/EFI/qubentoo/xen.efi
```

The multiboot2 entry in `/etc/grub.d/40_custom` becomes:

```
menuentry 'Qubentoo GNU/Linux (Xen EFI)' {
    insmod part_gpt
    insmod fat
    search --no-floppy --label --set=root EFI
    chainloader /EFI/qubentoo/xen.efi
}
```

Then regenerate:

```bash
grub-mkconfig -o /boot/grub/grub.cfg
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Qubentoo
```

---

## 7. Verify Xen is running after reboot

```bash
xl info | grep xen_version   # should print Xen 4.17.x
xl list                      # should show Domain-0
```

If `xl` is not found, Xen did not boot as the hypervisor — the Linux kernel
booted directly. Re-check the GRUB entry and repeat from step 2.
