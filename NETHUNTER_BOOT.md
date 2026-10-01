# NetHunter Pro Boot Guide for Samsung Galaxy S20 FE (SM8250)

This U-Boot fork has been enhanced to support booting mainline Linux with NetHunter Pro on the Samsung Galaxy S20 FE (codename: R8Q).

## Overview

The S20 FE uses the Snapdragon 865 Plus (SM8250) SoC and features UFS (Universal Flash Storage) for improved performance. This U-Boot build supports:

- **Native UFS Boot**: Primary boot device with automatic fallback to MMC
- **Device Tree Support**: Full device tree blob (DTB) loading for mainline kernel
- **Kernel Boot**: Support for ARM64 `booti` command and kernel image loading
- **EFI Fallback**: EFI boot system with capsule updates for redundancy
- **Fastboot Mode**: Quick kernel iteration via fastboot protocol
- **NetHunter Pro**: Full support for security tools and Kali Linux integrations

## Requirements

Before booting NetHunter Pro, you'll need:

1. **U-Boot**: `u-boot-r8q-boot.img` from the build, flashed to the device `boot` partition
2. **Kernel Image**: Mainline Linux kernel compiled for SM8250 (ARM64 `Image` format)
3. **Device Tree**: Device tree blob for S20 FE (`sm8250-samsung-r8q.dtb`)
4. **Root Filesystem**: NetHunter Pro rootfs on the UFS device partition

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
boot image; it is then omitted from the artifacts and `BUILD_INFO.txt`.

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

1. **Load Kernel & DTB**: Attempts to load from UFS boot partition
2. **Boot Linux**: Executes `booti` with kernel, DTB, and optional ramdisk
3. **EFI Fallback**: If Linux boot fails, tries EFI boot manager
4. **Boot Menu**: If EFI fails, displays interactive boot menu

## Setup Instructions

### 1. Prepare UFS Partitions

The device should have these UFS partitions:

```
Disk 0: Main rootfs (ext4)    - /dev/sda1
Disk 1: Optional dtbo         - /dev/sdb1
Disk 2: Optional dtbo         - /dev/sdc1
Disk 3: Boot partition (64MB) - /dev/sdd1
```

NetHunter Pro rootfs should be installed on `/dev/sda1` with ext4 filesystem.

### 2. Place Kernel and DTB

On the boot partition (`/dev/sdd1`), place:

- `Image` - ARM64 kernel image (mainline Linux)
- `sm8250-samsung-r8q.dtb` - Device tree blob

```bash
# Mount boot partition and copy files
mount /dev/sdd1 /mnt/boot
cp Image /mnt/boot/
cp sm8250-samsung-r8q.dtb /mnt/boot/
umount /mnt/boot
```

### 3. Configure NetHunter Pro Rootfs

Install NetHunter Pro on the root partition with proper configuration:

```bash
mount /dev/sda1 /mnt/root
# Extract NetHunter Pro rootfs
tar xzf nethunter-pro-rootfs.tar.gz -C /mnt/root
umount /mnt/root
```

## Boot Methods

### Method 1: Automatic Boot (Default)

Device will automatically boot to Linux kernel when powered on:

1. U-Boot loads kernel and DTB from boot partition
2. Kernel boots with embedded rootfs on `/dev/sda1`
3. System reaches NetHunter Pro login prompt

### Method 2: Boot Menu

Hold **Volume Down** when powering on to access boot menu:

```
1. Boot Linux Kernel (UFS)
2. Boot via Fastboot (for development)
3. Continue Boot (EFI)
4. UEFI Maintenance Menu
5. Reboot
6. Power Off
```

Select option 1 to boot Linux kernel.

### Method 3: Fastboot Kernel Boot

For rapid kernel iteration during development:

```bash
# On host machine with fastboot installed
fastboot boot Image

# Or send custom kernel over USB
fastboot -s <device-serial> download kernel.img
# Then boot via menu option 2
```

## Kernel Boot Parameters

The U-Boot environment is pre-configured with kernel boot parameters:

```
bootargs=root=/dev/sda1 ro console=ttyMSM0,115200 console=tty0 \
  androidboot.selinux=permissive debug \
  earlycon=msm_geni_serial,0xa90000 \
  msm_geni_serial.con_enabled=1 \
  kvm-arm.mode=preferred \
  audit=1 audit_backlog_limit=8192 \
  loglevel=4
```

Key parameters:

- `root=/dev/sda1` - UFS root filesystem
- `console=ttyMSM0,115200` - Serial console on MSM UART
- `androidboot.selinux=permissive` - SELinux in permissive mode (required for NetHunter)
- `earlycon=msm_geni_serial` - Early console output
- `kvm-arm.mode=preferred` - Enable KVM virtualization
- `audit=1` - Enable audit subsystem

## Customizing Boot Arguments

To modify kernel boot arguments at runtime:

### Via U-Boot Serial Console

```
=> setenv bootargs "root=/dev/sda1 ro console=ttyMSM0,115200 your_custom_args_here"
=> run linux_boot
```

### Permanent Configuration

Edit `board/samsung/samsung-mobile/samsung-mobile.env` and rebuild U-Boot.

## Memory Layout

The bootloader uses the following memory addresses for kernel boot (ARM64):

- **0x40000000** - Kernel image load address (`kernel_addr_r`)
- **0x43000000** - Device tree blob load address (`fdt_addr_r`)
- **0x44000000** - Ramdisk/initrd load address (`ramdisk_addr_r`)
- **0x45000000** - Script load address (`scriptaddr`)
- **0x46000000** - PXE file load address (`pxefile_addr_r`)

These can be modified in `board/samsung/samsung-mobile/samsung-mobile.env` if needed.

## Troubleshooting

### Kernel Not Loading

1. Check that kernel image is at `/boot/Image` on boot partition
2. Verify device tree blob is at `/boot/sm8250-samsung-r8q.dtb`
3. Check U-Boot console output for error messages
4. Try booting via fastboot method to isolate issue

### Root Filesystem Not Mounting

1. Verify ext4 filesystem on `/dev/sda1`: `fsck.ext4 /dev/sda1`
2. Check that NetHunter Pro rootfs was properly extracted
3. Verify `bootargs` contains correct root device parameter
4. Check kernel console output for filesystem errors

### Serial Console Not Working

1. Verify USB serial adapter is properly connected
2. Check host serial port settings (115200 baud, 8N1)
3. Ensure early console is enabled in bootargs

### Kernel Panic at Boot

1. Check kernel build configuration matches SM8250 hardware
2. Verify all necessary drivers are compiled in (not modules)
3. Check device tree compatibility with kernel version
4. Enable `earlycon` and `debug` options to capture early panic messages

## Environment Variables

Important U-Boot environment variables for kernel boot:

```
kernel_addr_r   - Kernel load address (default: 0x40000000)
fdt_addr_r      - Device tree load address (default: 0x43000000)
ramdisk_addr_r  - Ramdisk load address (default: 0x44000000)
bootargs        - Kernel command line parameters
load_kernel     - Script to load kernel image
load_fdt        - Script to load device tree
linux_boot      - Combined script to load and boot kernel
```

View current values:
```
=> printenv
```

Modify temporarily:
```
=> setenv variable value
```

Save permanently:
```
=> saveenv
```

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

This U-Boot build targets the Samsung Galaxy S20 FE (R8Q) but should also support:

- Samsung Galaxy S20 Ultra 5G (X1Q)
- Other SM8250-based Samsung devices with similar hardware

Each device may require its own device tree blob and kernel configuration.

## Security Considerations

- **SELinux**: Running in permissive mode for compatibility
- **Verified Boot**: Disabled for flexibility in development
- **Secure Boot**: Not enforced; ensure you trust your kernel image
- **Console Access**: Serial console enabled; secure in controlled environments

For production use, consider enabling SELinux enforcement and verified boot.

## Performance Tips

1. Use native UFS boot (faster than eMMC)
2. Disable unnecessary kernel modules
3. Consider CONFIG_BOOTM_COMPRESSED if using compressed kernel
4. Minimize ramdisk size if using initrd

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
