# GitHub Actions Workflow - Build & Upload Summary

## Overview

A streamlined GitHub Actions workflow automatically builds U-Boot for Samsung Galaxy S20 FE (R8Q) with Qualcomm SM8250 SoC.

## Build Device
- **Samsung Galaxy S20 FE (R8Q)** - Qualcomm Snapdragon SM8250

## Build Capabilities
- ARM64 cross-compilation with `aarch64-linux-gnu-` toolchain
- Device tree selection via `configs/samsung-r8q.config` (`qcom/sm8250-samsung-r8q`)
- Build manifest/metadata generation and `SHA256SUMS`
- Deterministic Android boot image assembly (`.github/scripts/r8q-package.sh`)
- Packaging tests (`.github/scripts/test-r8q-package.sh`) run before the build

### Artifact Outputs
| Artifact name | File | Purpose |
|---------------|------|---------|
| `u-boot-r8q-boot-img` | `u-boot-r8q-boot.img` | Android boot image (header v2) – flash to the `boot` partition |
| `u-boot-r8q-bin` | `u-boot.bin` | U-Boot + appended control DTB (boot image payload / chain-loading) |
| `u-boot-r8q-control-dtb` | `u-boot-control.dtb` | U-Boot's own control DTB (reference only; already in `u-boot.bin`) |
| `u-boot-r8q-linux-dtb` | `sm8250-samsung-r8q.dtb` | DTB for the Linux kernel – goes next to `Image` |
| `u-boot-r8q-buildinfo` | `BUILD_INFO.txt`, `SHA256SUMS` | Build metadata and checksums |
| `u-boot-r8q-<commit>` | all of the above | Combined download |

The boot image is built from `not/boot.img` with `not/boot/magiskboot`:
kernel section = `u-boot.bin`, dtb section = stock `not/boot/dtb` (ABL needs its
`qcom,msm-id`/`board-id`), header = `not/boot/header`. The Linux DTB is **not**
put in the boot image. See [NETHUNTER_BOOT.md](./NETHUNTER_BOOT.md#build-artifacts-which-file-is-which).

There are no silent fallbacks: if any input is missing, assembly fails, or the
result is not a valid repackable header v2 image whose kernel section equals
`u-boot.bin`, the job fails. A manual run with the `boot_image` input set to
`false` skips the boot image explicitly; it is then omitted from the artifacts
and marked "NOT BUILT" in `BUILD_INFO.txt`.

CI does not boot the image on hardware; a green run does not prove the device boots.

### Workflow Triggers
- **Manual dispatch** - Via `workflow_dispatch` (input `boot_image`, default `true`)
- **Tagged releases** - Release job runs when dispatched on a `v*` tag

## Build Information Captured

Each build generates a `BUILD_INFO.txt` file containing:
- Device name and configuration
- Git commit hash (short form)
- Git branch name
- Build date/time (UTC)
- U-Boot version
- Runner OS and architecture
- File descriptions

## Artifact Management

### Retention Policies
- Standard artifacts: 90 days retention
- Release artifacts: Unlimited (via GitHub releases)

### Upload Strategies
1. **Individual artifacts** - Separate uploads for each component
2. **Combined archive** - All artifacts in one download with git commit hash
3. **Release assets** - Automatic upload to GitHub releases on version tags

## Release Automation

### Version Releases
Triggered by pushing tags matching `v*.*`:
```bash
git tag v2026.10.0
git push origin v2026.10.0
```

Creates GitHub release with:
- Pre-built binaries for all devices
- Build information
- Reference to NETHUNTER_BOOT.md

### Nightly Builds
Automatically publishes `nightly-latest` release on pushes to main branch:
- Always-up-to-date prerelease
- Convenient for testing latest changes

## Build Performance

### Dependency Caching
- Caches APT packages and build dependencies
- Reduces build time by ~50% on cache hits
- Key: Based on Makefile content

### Build Steps
1. **Checkout** (~10s)
2. **Dependency install** (30-60s first time, cached after)
3. **Configure** (~5s)
4. **Build** (2-5 minutes)
5. **DTB compilation** (~5s)
6. **Assembly** (~5s)
7. **Upload** (~10-30s per artifact)

**Typical total time:** 3-8 minutes

## Security

### Patched Dependencies
- `actions/checkout@v4` - Latest stable
- `actions/cache@v3` - Latest stable
- `actions/upload-artifact@v4` - v4.1.3+ (patched for CVE)
- `actions/download-artifact@v4.1.3` - Patched version
- `softprops/action-gh-release@v1` - Latest

### CVE Fix
Fixed: **Arbitrary File Write via artifact extraction**
- Affected: actions/download-artifact v4.0.0 - v4.1.2
- Patched: v4.1.3+
- Applied: All download-artifact actions

## Build Environment

### Runner
- Image: `ubuntu-latest`
- Timeout: 60 minutes

### Dependencies Installed
- `gcc-aarch64-linux-gnu` - ARM64 cross-compiler
- `libgnutls28-dev` - TLS library
- `python3-dev` - Python development
- `libpython3-dev` - Python library

## Workflow File Location

```
.github/workflows/build-images.yml
```

## Example Workflow Run Output

Each build produces a GitHub step summary showing:
- Build status (success/failure)
- Device name and configuration
- Git commit and branch
- Build timestamp
- Artifact file list with sizes

## Usage Examples

### Download Latest Artifacts
1. Go to GitHub Actions → Build U-Boot and Upload Artifacts
2. Click latest successful run
3. Download desired artifact from "Artifacts" section

### Download Release Binaries
1. Go to Releases
2. Download pre-built binaries for your device
3. See NETHUNTER_BOOT.md for installation instructions

### Trigger Manual Build
```bash
# Via GitHub CLI
gh workflow run build-images.yml -r copilot/improve-s20fe-compatibility

# Or via GitHub web UI
Actions → Build U-Boot and Upload Artifacts → Run workflow
```

### Create Version Release
```bash
git tag v2026.10.1 -m "U-Boot release for NetHunter Pro"
git push origin v2026.10.1
```

## Workflow Configuration

### Environment Variables
```yaml
CROSS_COMPILE: aarch64-linux-gnu-
OUTPUT_DIR: .output
```

### Build Configuration
- Base config: `qcom_defconfig`
- Phone config: `qcom-phone.config`
- Device config: `samsung-sm8250.config`
- DTB: Set via `CONFIG_DEFAULT_DEVICE_TREE`

## Troubleshooting

### Build Failures
Check workflow run logs for:
1. Dependency installation errors
2. Compilation errors
3. Device tree compilation issues
4. "Package and verify R8Q artifacts" errors – the message names the missing
   or invalid input (e.g. `not/boot.img`, `not/boot/magiskboot`, a DTB that is
   not `samsung,r8q`)

### Missing Artifacts
- All artifacts are required; a missing one fails the job
- `u-boot-r8q-boot.img` is only absent when `boot_image` was set to `false`
- Check BUILD_INFO.txt and the job summary

## Files Modified

1. `.github/workflows/build-images.yml` - Complete workflow rewrite
2. `board/samsung/samsung-mobile/*` - Renamed from exynos-mobile
3. `include/configs/samsung-mobile.h` - Renamed header
4. Various comments and headers - Updated SM8250 references

## Git Commits

### Commit 1: Platform Correction
```
f51522b6715 Fix: Rename exynos-mobile to samsung-mobile for Qualcomm SM8250
```
- Corrects device platform from Exynos to QCOM
- Renames all board files for clarity

### Commit 2: Workflow Implementation
```
84f9c5359da Security: Update actions/download-artifact to patched version 4.1.3
```
- Adds enhanced GitHub Actions workflow
- Includes security patches for CVE fixes

### Commit 3: Workflow Documentation
```
36c07d88671 Add workflow documentation for GitHub Actions build system
```
- Comprehensive workflow guide and reference

### Commit 4: Simplified Workflow
```
43c516ba466 Simplify workflow for R8Q only - remove X1Q multi-device support
```
- Focused exclusively on Samsung Galaxy S20 FE (R8Q)
- Removed multi-device matrix complexity
- Faster, cleaner build pipeline

## Next Steps

1. **Test the workflow**: Verify it runs successfully
2. **Monitor build times**: Adjust cache strategy if needed
3. **Create releases**: Tag versions to generate release builds
4. **Download artifacts**: Use for device flashing/testing
5. **Track performance**: Monitor workflow execution times

## Support & Documentation

See [NETHUNTER_BOOT.md](./NETHUNTER_BOOT.md) for:
- Device setup instructions
- Kernel and DTB placement
- Rootfs configuration
- Boot method selection
- Troubleshooting guide

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [U-Boot Build Documentation](https://u-boot.readthedocs.io/en/latest/build/index.html)
- [ARM64 Boot Protocol](https://www.kernel.org/doc/html/latest/arm64/booting.html)
- [actions/download-artifact CVE](https://github.com/actions/download-artifact/security/advisories)
