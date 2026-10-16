# NetHunter Pro Boot Guide for Samsung Galaxy S20 FE (SM8250)

This U-Boot configuration targets the Samsung Galaxy S20 FE (codename: R8Q) and provides a standard bootflow for Linux distributions such as NetHunter Pro and Mobian. Successful Linux boot still depends on a kernel and device tree that support the device.

## Overview

The S20 FE uses the Snapdragon 865 Plus (SM8250) SoC and features UFS (Universal Flash Storage) for improved performance. This U-Boot build supports:

- **UFS Boot**: UFS is scanned through U-Boot's SCSI interface
- **Distro Boot**: Scans available media for `extlinux/extlinux.conf` and EFI removable-media boot entries
- **UEFI Fallback**: Tries the UEFI boot manager if no removable-media bootflow starts
- **Recovery**: Volume Down opens a menu with serial-console, USB mass-storage, fastboot, and shell options

## Requirements

Before booting NetHunter Pro, you'll need:

1. **U-Boot**: `u-boot-r8q-boot.img` from the build, flashed to the device `boot` partition
2. **Linux boot files**: An R8Q-compatible ARM64 kernel, a matching R8Q Linux DTB, and an initramfs when required by the distribution
3. **Boot configuration**: An `extlinux/extlinux.conf` on a supported filesystem, or an EFI loader at `EFI/BOOT/BOOTAA64.EFI`
4. **Root filesystem**: Installed by the chosen distribution; identify it by UUID or PARTUUID rather than assuming a `/dev/sdX` name

## Build Artifacts: Which File Is Which

The CI workflow (`.github/workflows/build-images.yml`) builds U-Boot with
`qcom_defconfig qcom-phone.config samsung-sm8250.config samsung-r8q.config`,
which selects `qcom/sm8250-samsung-r8q` (from
`dts/upstream/src/arm64/qcom/sm8250-samsung-r8q.dts`) as the device tree.
Packaging is done by `.github/scripts/r8q-package.sh`, which fails the build
if any of the files below cannot be produced or validated.

| File | Purpose | Where it goes |
|------|---------|---------------|
| `u-boot-r8q-boot.img` | Android boot image (header v2) containing U-Boot | Flash to the `boot` partition. **This is the file to flash.** |
| `u-boot.bin` | U-Boot with its control DTB appended | Payload inside `u-boot-r8q-boot.img`; use directly only for chain-loading or repacking yourself |
| `u-boot-control.dtb` | U-Boot's own control DTB | Nothing to do – already inside `u-boot.bin`, provided for reference/debugging |
| `sm8250-samsung-r8q.dtb` | DTB for the **Linux kernel** | Copy next to `Image` on the Linux boot partition (see below) |

How `u-boot-r8q-boot.img` is assembled (from the committed `not/boot.img`
and `not/boot/` inputs, using `not/boot/magiskboot`):

- **kernel section** = `u-boot.bin`. Samsung's ABL loads this like an arm64
  Linux `Image`. U-Boot uses the control DTB appended to itself
  (`CONFIG_OF_SEPARATE`), not a DTB from ABL.
- **dtb section** = `not/boot/dtb`, the stock Qualcomm "kona" DTBs with
  `qcom,msm-id`/`qcom,board-id`. ABL needs a matching one to accept the image.
  The upstream `sm8250-samsung-r8q.dtb` has no such ids and is intentionally
  **not** placed in the boot image.
- **header** (cmdline, OS version/patch level) = `not/boot/header`.

The build verifies the result is a header v2 boot image whose kernel section
is byte-identical to `u-boot.bin` and whose dtb section is the stock DTB, and
that `magiskboot` can unpack it again. If `not/boot.img` or the `not/boot/`
inputs are missing, the build fails instead of uploading a partial image. A
manual run can set the `boot_image` input to `false` to explicitly skip the
boot image; it is then omitted from the artifacts and marked "NOT BUILT" in
`BUILD_INFO.txt`.

> **Note:** CI only proves that the files build and the image layout is
> valid. Booting on real R8Q hardware is not tested by CI. Flashing requires
> an unlocked bootloader; flash `u-boot-r8q-boot.img` to the `boot`
> partition with your usual Samsung tool (Odin/Heimdall – check the partition
> name in your device's PIT). Keep a copy of your stock `boot.img` to restore.

`sm8250-samsung-r8q.dtb` is built from this repository's
`dts/upstream` snapshot. If your Linux kernel is much newer or older, prefer
the DTB built from that kernel's own source tree.

## Boot Sequence

The default boot sequence is:

1. **Scan media**: UFS and USB are initialized; standard boot scans available boot devices.
2. **Boot a distribution entry**: U-Boot tries extlinux and EFI removable-media entries, which provide their own kernel arguments and optional initramfs.
3. **UEFI fallback**: If no scanned entry boots, U-Boot tries the EFI boot manager.
4. **Recovery menu**: On failure, the menu offers boot retry and recovery tools. Hold Volume Down during startup to open it directly.

## Setup Instructions

### Prepare boot files

Install NetHunter Pro or Mobian using that project's device-specific instructions. On a FAT or ext4 partition visible to U-Boot, place the kernel, a DTB built for the same kernel, and any required initramfs. The packaged `sm8250-samsung-r8q.dtb` is a convenience; using the DTB from the exact kernel build is preferable.

For direct Linux boot, add `extlinux/extlinux.conf` to that partition. For example, adjust the paths and replace the root placeholder with the root filesystem's PARTUUID:

```text
DEFAULT linux
LABEL linux
  LINUX /Image
  FDT /sm8250-samsung-r8q.dtb
  INITRD /initrd.img
  APPEND root=PARTUUID=replace-with-root-partition-guid rw console=ttyMSM0,115200 console=tty0
```

Omit `INITRD` only when the kernel can mount the root filesystem without an initramfs. Distribution installers may provide their own extlinux configuration or EFI bootloader; use those files when available. U-Boot scans UFS/SCSI, USB, and other enabled boot devices instead of relying on a fixed partition number or Linux block-device name.

## Boot Methods

### Method 1: Automatic Boot (Default)

The bootloader scans supported media for a distribution boot entry:

1. U-Boot loads the kernel, DTB, initramfs, and command line from extlinux or an EFI entry.
2. The Linux command line identifies the installed root filesystem, preferably by UUID or PARTUUID.

### Method 2: Boot Menu

Hold **Volume Down** while powering on to access the recovery menu:

```
1. Boot from available media
2. Boot UEFI boot manager
3. Enable USB serial console
4. Enable USB mass storage
5. Enable fastboot mode
6. Drop to U-Boot shell
7. Reset device
8. Power off
```

Select option 1 to scan for an OS boot entry. Fastboot is provided as a recovery/flashing mode; direct `fastboot boot Image` is not configured by this build.

## Kernel Boot Parameters

The R8Q environment does not hard-code a root device or Linux command line. An extlinux entry supplies its command line with `APPEND`; an EFI distribution supplies its own boot configuration. Prefer stable identifiers such as `root=UUID=...` or `root=PARTUUID=...`, since Linux device names can change.

## Customizing Boot Arguments

Edit the distribution's extlinux configuration or EFI entry. To change U-Boot's boot scan or recovery menu, edit `board/qualcomm/samsung-r8q.env` and rebuild U-Boot. The default U-Boot environment is compiled into this build and is not saved across resets.

## Memory Layout

Standard boot selects load addresses from the configured U-Boot environment. Avoid changing them unless the full R8Q memory map and image sizes have been checked.

## Troubleshooting

### Kernel Not Loading

1. Check that U-Boot can read the boot filesystem and find `extlinux/extlinux.conf` or `EFI/BOOT/BOOTAA64.EFI`.
2. Check the kernel, DTB, and initramfs paths in that entry.
3. Use a DTB built for the exact kernel version and R8Q variant.
4. Check U-Boot console output; the Volume Down menu also provides serial and USB recovery options.

### Root Filesystem Not Mounting

1. Verify the installed root filesystem and its UUID/PARTUUID.
2. Check that the kernel command line references the correct identifier.
3. Ensure required storage and filesystem drivers are built into the kernel or available in its initramfs.
4. Check kernel console output for filesystem errors.

### Serial Console Not Working

1. Verify USB serial adapter is properly connected
2. Check host serial port settings (115200 baud, 8N1)
3. Verify that a console device and baud rate are specified in the distribution's kernel command line.

### Kernel Panic at Boot

1. Check kernel build configuration matches SM8250 hardware
2. Verify all necessary drivers are compiled in (not modules)
3. Check device tree compatibility with kernel version
4. Enable `earlycon` and `debug` options to capture early panic messages

## Environment Variables

The R8Q environment uses standard bootflow scanning rather than fixed kernel/DTB filenames:

```
bootcmd         - Starts R8Q bootflow scanning
r8q_boot        - Scans extlinux/EFI entries, then tries the EFI boot manager
bootmenu_*      - Boot and recovery options
preboot         - Initializes UFS/SCSI and USB before scanning
```

View current values:
```
=> printenv
```

Modify temporarily:
```
=> setenv variable value
```

The configured environment is built into U-Boot; runtime changes are not persistent across resets.

## Rebuilding U-Boot

To rebuild U-Boot with custom configurations:

```bash
make CROSS_COMPILE=aarch64-linux-gnu- O=.output \
  qcom_defconfig qcom-phone.config samsung-sm8250.config samsung-r8q.config
make CROSS_COMPILE=aarch64-linux-gnu- O=.output -j$(nproc)
make CROSS_COMPILE=aarch64-linux-gnu- O=.output dtbs

# Collect artifacts and repack not/boot.img (needs fdtget from device-tree-compiler)
.github/scripts/r8q-package.sh .output artifacts/r8q
```

This produces `artifacts/r8q/u-boot-r8q-boot.img`, `u-boot.bin`,
`u-boot-control.dtb` and `sm8250-samsung-r8q.dtb` as described in
[Build Artifacts](#build-artifacts-which-file-is-which). The packaging logic is
tested by `.github/scripts/test-r8q-package.sh`.

## Device Support

This configuration targets the Samsung Galaxy S20 FE (R8Q) only. The boot image's Samsung ABL DTB and the Linux kernel DTB are device-specific; other SM8250 devices need their own boot image, device tree, and tested configuration.

## Security Considerations

- U-Boot does not force SELinux into permissive mode; configure this through the Linux distribution.
- This development boot flow does not establish a verified-boot chain for the Linux kernel. Only boot images and kernels you trust.
- U-Boot serial and USB recovery interfaces may expose privileged access; use them only in a controlled environment.

For production use, configure the Linux distribution's security policy and a verified boot chain appropriate to the device.

## Performance Tips

1. Keep the kernel, DTB, and initramfs from the same distribution/kernel build.
2. Use an initramfs only when the distribution needs one for storage discovery or root filesystem setup.

## Additional Resources

- [U-Boot Documentation](https://u-boot.readthedocs.io/)
- [ARM64 Linux Booting](https://www.kernel.org/doc/html/latest/arm64/booting.html)
- [NetHunter Documentation](https://www.kali.org/docs/nethunter/)
- [Device Tree Specification](https://devicetree-specification.readthedocs.io/)

## Support

For issues specific to this U-Boot build:

1. Check U-Boot console output for error messages
2. Verify device tree and kernel compatibility
3. Check that all boot files are present and readable
4. Consult U-Boot and Linux kernel documentation
5. File issues with detailed console logs and hardware information

## License

This U-Boot fork is licensed under GPL-2.0, maintaining compatibility with the upstream U-Boot project.
