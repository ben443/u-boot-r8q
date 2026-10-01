#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0+
#
# Collect and validate the Samsung Galaxy S20 FE (R8Q) build outputs and,
# optionally, repack U-Boot into the repository's Android boot image.
#
# Usage: r8q-package.sh [--no-boot-image] <u-boot build dir> <artifact dir>
#
# Artifacts written to <artifact dir>:
#   u-boot.bin             U-Boot with its control DTB appended (OF_SEPARATE);
#                          this is the payload used as the boot.img "kernel".
#   u-boot-control.dtb     U-Boot's own control DTB (already inside u-boot.bin,
#                          provided for reference/debugging only).
#   sm8250-samsung-r8q.dtb Upstream R8Q DTB for the *Linux* kernel, loaded by
#                          U-Boot from the boot partition (see NETHUNTER_BOOT.md).
#   u-boot-r8q-boot.img    Android boot image (header v2) to flash to the
#                          "boot" partition. Only produced when every input is
#                          present and the result passes validation.
#
# Boot image layout (derived from not/boot.img, header v2, page size 4096):
#   kernel  = u-boot.bin (raw arm64 Image header, control DTB appended)
#   dtb     = not/boot/dtb, the stock Samsung "kona" DTBs carrying
#             qcom,msm-id/board-id. ABL needs one of these to accept the image;
#             the upstream Linux DTB has no such ids and must NOT go here.
#   header  = not/boot/header (cmdline/os_version/patch level)
#
# Environment overrides (mainly for tests):
#   R8Q_BOOT_DIR    directory with magiskboot, dtb and header (default not/boot)
#   R8Q_SOURCE_IMG  source Android boot image            (default not/boot.img)

set -euo pipefail

die() {
	echo "ERROR: $*" >&2
	exit 1
}

build_boot_image=1
if [ "${1:-}" = "--no-boot-image" ]; then
	build_boot_image=0
	shift
fi

[ $# -eq 2 ] || die "usage: $0 [--no-boot-image] <u-boot build dir> <artifact dir>"

build_dir=$1
out_dir=$2
repo_root=$(cd "$(dirname "$0")/../.." && pwd)
boot_dir=${R8Q_BOOT_DIR:-$repo_root/not/boot}
source_img=${R8Q_SOURCE_IMG:-$repo_root/not/boot.img}
linux_dtb_name=sm8250-samsung-r8q.dtb
linux_dtb=$build_dir/dts/upstream/src/arm64/qcom/$linux_dtb_name
r8q_compatible=samsung,r8q

require_file() {
	if [ ! -f "$1" ] || [ ! -s "$1" ]; then
		die "missing required file: $1 ($2)"
	fi
}

check_r8q_dtb() {
	local compat
	compat=$(fdtget -t s "$1" / compatible) || die "$1 is not a valid DTB"
	case " $compat " in
	*" $r8q_compatible "*) ;;
	*) die "$1 has root compatible '$compat', expected '$r8q_compatible'" ;;
	esac
}

command -v fdtget >/dev/null || die "fdtget not found (install device-tree-compiler)"
command -v python3 >/dev/null || die "python3 not found"

# --- U-Boot and DTB outputs -------------------------------------------------
require_file "$build_dir/u-boot.bin" "U-Boot binary"
require_file "$build_dir/u-boot-nodtb.bin" "U-Boot binary without DTB"
require_file "$build_dir/u-boot.dtb" "U-Boot control DTB"
require_file "$linux_dtb" "Linux R8Q DTB, built from dts/upstream/src/arm64/qcom/sm8250-samsung-r8q.dts"

check_r8q_dtb "$build_dir/u-boot.dtb"
check_r8q_dtb "$linux_dtb"

cat "$build_dir/u-boot-nodtb.bin" "$build_dir/u-boot.dtb" |
	cmp -s - "$build_dir/u-boot.bin" ||
	die "u-boot.bin is not u-boot-nodtb.bin + u-boot.dtb (expected CONFIG_OF_SEPARATE)"

mkdir -p "$out_dir"
rm -f "$out_dir/u-boot.bin" "$out_dir/u-boot-control.dtb" \
	"$out_dir/$linux_dtb_name" "$out_dir/u-boot-r8q-boot.img"
cp "$build_dir/u-boot.bin" "$out_dir/u-boot.bin"
cp "$build_dir/u-boot.dtb" "$out_dir/u-boot-control.dtb"
cp "$linux_dtb" "$out_dir/$linux_dtb_name"

if [ $build_boot_image -eq 0 ]; then
	echo "Boot image assembly not requested: u-boot-r8q-boot.img omitted."
	exit 0
fi

# --- Android boot image -----------------------------------------------------
magiskboot=$boot_dir/magiskboot
require_file "$source_img" "source Android boot image for R8Q"
require_file "$boot_dir/dtb" "stock Samsung DTB section for the boot image"
require_file "$boot_dir/header" "boot image header (cmdline/os_version)"
require_file "$magiskboot" "boot image repack tool"
[ -x "$magiskboot" ] || die "$magiskboot is not executable"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cp "$source_img" "$work/source.img"
(cd "$work" && "$magiskboot" unpack -h source.img) >"$work/unpack.log" 2>&1 ||
	{ cat "$work/unpack.log" >&2; die "magiskboot could not unpack $source_img"; }
grep -q '^HEADER_VER *\[2\]' "$work/unpack.log" ||
	{ cat "$work/unpack.log" >&2; die "$source_img is not an Android boot image header v2"; }

# Replace the payload; drop the split-off appended DTB so the kernel section
# is exactly u-boot.bin (which already carries the control DTB).
rm -f "$work/kernel" "$work/kernel_dtb" "$work/ramdisk.cpio" "$work/second"
cp "$build_dir/u-boot.bin" "$work/kernel"
cp "$boot_dir/dtb" "$work/dtb"
cp "$boot_dir/header" "$work/header"

(cd "$work" && "$magiskboot" repack source.img u-boot-r8q-boot.img) >"$work/repack.log" 2>&1 ||
	{ cat "$work/repack.log" >&2; die "magiskboot repack failed"; }
require_file "$work/u-boot-r8q-boot.img" "repacked boot image"

# Independent layout check of the result (does not rely on magiskboot).
python3 - "$work/u-boot-r8q-boot.img" "$build_dir/u-boot.bin" "$boot_dir/dtb" <<'EOF'
import struct, sys

img, kernel, dtb = (open(p, "rb").read() for p in sys.argv[1:4])

def fail(msg):
    sys.exit("ERROR: boot image validation: " + msg)

if img[:8] != b"ANDROID!":
    fail("bad magic")
(kernel_size, _, ramdisk_size, _, second_size, _, _, page_size,
 header_version, _) = struct.unpack_from("<10I", img, 8)
if header_version != 2:
    fail("header version %d, expected 2" % header_version)
if page_size != 4096:
    fail("page size %d, expected 4096" % page_size)
recovery_dtbo_size = struct.unpack_from("<I", img, 1632)[0]
dtb_size = struct.unpack_from("<I", img, 1648)[0]

def pages(n):
    return (n + page_size - 1) // page_size * page_size

kernel_off = page_size
dtb_off = (kernel_off + pages(kernel_size) + pages(ramdisk_size) +
           pages(second_size) + pages(recovery_dtbo_size))

if (ramdisk_size, second_size, recovery_dtbo_size) != (0, 0, 0):
    fail("unexpected ramdisk/second/recovery_dtbo sections")
if img[kernel_off:kernel_off + kernel_size] != kernel:
    fail("kernel section does not match u-boot.bin")
if dtb_size != len(dtb) or img[dtb_off:dtb_off + dtb_size] != dtb:
    fail("dtb section does not match the stock Samsung DTB")
print("Boot image layout OK: header v2, kernel=u-boot.bin (%d bytes), "
      "dtb=stock (%d bytes)" % (kernel_size, dtb_size))
EOF

# The result must also be parseable/repackable by the same tool.
mkdir "$work/verify"
cp "$work/u-boot-r8q-boot.img" "$work/verify/"
(cd "$work/verify" && "$magiskboot" unpack -h u-boot-r8q-boot.img) >"$work/verify.log" 2>&1 ||
	{ cat "$work/verify.log" >&2; die "repacked image cannot be unpacked again"; }
unpacked=("$work/verify/kernel")
[ -f "$work/verify/kernel_dtb" ] && unpacked+=("$work/verify/kernel_dtb")
cat "${unpacked[@]}" | cmp -s - "$build_dir/u-boot.bin" ||
	die "re-unpacked kernel does not match u-boot.bin"

cp "$work/u-boot-r8q-boot.img" "$out_dir/u-boot-r8q-boot.img"
echo "Created $out_dir/u-boot-r8q-boot.img"
