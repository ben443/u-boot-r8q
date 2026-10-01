#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0+
#
# Tests for r8q-package.sh using synthetic U-Boot outputs and the committed
# not/boot.img + not/boot/{magiskboot,dtb,header}. No cross toolchain needed.
#
# Usage: test-r8q-package.sh

set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
pkg=$script_dir/r8q-package.sh
repo_root=$(cd "$script_dir/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

# Build a fake U-Boot output directory: <dir> <root compatible>
make_build() {
	local dir=$1 compat=$2
	mkdir -p "$dir/dts/upstream/src/arm64/qcom"
	printf '/dts-v1/;\n/ { compatible = %s; model = "test"; };\n' "$compat" |
		dtc -q -I dts -O dtb -o "$dir/u-boot.dtb" -
	cp "$dir/u-boot.dtb" "$dir/dts/upstream/src/arm64/qcom/sm8250-samsung-r8q.dtb"
	head -c 65536 /dev/urandom >"$dir/u-boot-nodtb.bin"
	cat "$dir/u-boot-nodtb.bin" "$dir/u-boot.dtb" >"$dir/u-boot.bin"
}

expect_ok() {
	local name=$1; shift
	if "$@" >"$tmp/log" 2>&1; then pass "$name"; else
		fail "$name (unexpected failure)"; cat "$tmp/log"; fi
}

expect_fail() {
	local name=$1 pattern=$2; shift 2
	if "$@" >"$tmp/log" 2>&1; then
		fail "$name (unexpected success)"; cat "$tmp/log"
	elif ! grep -q -- "$pattern" "$tmp/log"; then
		fail "$name (missing '$pattern' in error)"; cat "$tmp/log"
	else
		pass "$name"
	fi
}

r8q='"samsung,r8q", "qcom,sm8250"'
make_build "$tmp/good" "$r8q"

# 1. Full packaging produces all artifacts with the expected names/content.
expect_ok "full package" "$pkg" "$tmp/good" "$tmp/art1"
for f in u-boot.bin u-boot-control.dtb sm8250-samsung-r8q.dtb u-boot-r8q-boot.img; do
	[ -s "$tmp/art1/$f" ] && pass "artifact $f exists" || fail "artifact $f missing"
done
[ ! -e "$tmp/art1/u-boot.img" ] && pass "no legacy u-boot.img" || fail "legacy u-boot.img emitted"
cmp -s "$tmp/art1/u-boot.bin" "$tmp/good/u-boot.bin" && pass "u-boot.bin copied" ||
	fail "u-boot.bin differs"
mkdir "$tmp/unpack"
cp "$tmp/art1/u-boot-r8q-boot.img" "$tmp/unpack/"
if (cd "$tmp/unpack" && "$repo_root/not/boot/magiskboot" unpack -h u-boot-r8q-boot.img) \
	>"$tmp/unpack.log" 2>&1 && grep -q '^HEADER_VER *\[2\]' "$tmp/unpack.log"; then
	pass "boot image unpacks as header v2"
else
	fail "boot image does not unpack"; cat "$tmp/unpack.log"
fi
cmp -s "$tmp/unpack/dtb" "$repo_root/not/boot/dtb" && pass "boot image dtb is stock dtb" ||
	fail "boot image dtb section wrong"

# 2. Opting out omits only the boot image.
expect_ok "no boot image" "$pkg" --no-boot-image "$tmp/good" "$tmp/art2"
[ -s "$tmp/art2/sm8250-samsung-r8q.dtb" ] && [ ! -e "$tmp/art2/u-boot-r8q-boot.img" ] &&
	pass "boot image omitted on opt-out" || fail "opt-out artifacts wrong"

# 3. Missing Linux DTB fails.
cp -r "$tmp/good" "$tmp/nolinux"
rm "$tmp/nolinux/dts/upstream/src/arm64/qcom/sm8250-samsung-r8q.dtb"
expect_fail "missing linux dtb" "Linux R8Q DTB" "$pkg" "$tmp/nolinux" "$tmp/art3"

# 4. Control DTB for another board fails.
make_build "$tmp/wrong" '"qcom,sdm845-mtp", "qcom,sdm845"'
expect_fail "wrong control dtb" "expected 'samsung,r8q'" "$pkg" "$tmp/wrong" "$tmp/art4"

# 5. u-boot.bin without the control DTB appended fails.
cp -r "$tmp/good" "$tmp/nodtb"
cp "$tmp/nodtb/u-boot-nodtb.bin" "$tmp/nodtb/u-boot.bin"
expect_fail "u-boot.bin without dtb" "CONFIG_OF_SEPARATE" "$pkg" "$tmp/nodtb" "$tmp/art5"

# 6. Missing source boot image / tool fails and emits no boot image.
expect_fail "missing source image" "source Android boot image" \
	env R8Q_SOURCE_IMG="$tmp/none.img" "$pkg" "$tmp/good" "$tmp/art6"
[ ! -e "$tmp/art6/u-boot-r8q-boot.img" ] && pass "no image on missing source" ||
	fail "image emitted without source"
mkdir "$tmp/bootdir"
cp "$repo_root/not/boot/dtb" "$repo_root/not/boot/header" "$tmp/bootdir/"
expect_fail "missing magiskboot" "repack tool" \
	env R8Q_BOOT_DIR="$tmp/bootdir" "$pkg" "$tmp/good" "$tmp/art7"

# 7. A source image that is not an Android boot image fails.
head -c 8192 /dev/zero >"$tmp/bad.img"
expect_fail "invalid source image" "ERROR" \
	env R8Q_SOURCE_IMG="$tmp/bad.img" "$pkg" "$tmp/good" "$tmp/art8"
[ ! -e "$tmp/art8/u-boot-r8q-boot.img" ] && pass "no image on invalid source" ||
	fail "image emitted from invalid source"

if [ $failures -ne 0 ]; then
	echo "$failures test(s) failed"
	exit 1
fi
echo "All r8q-package tests passed"
