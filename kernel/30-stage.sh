#!/usr/bin/env bash
# 30-stage.sh — install modules into a staging root and build an initramfs
# there. The running system is not touched.
set -euo pipefail
cd "$(dirname "$0")"
KVER=$(make -s -C src kernelrelease LOCALVERSION=-dany)
ROOT=out/root
rm -rf "$ROOT"; mkdir -p "$ROOT"

echo "staging $KVER into $ROOT"
make -C src modules_install INSTALL_MOD_PATH="$PWD/$ROOT" LOCALVERSION=-dany >/dev/null
depmod -b "$ROOT" "$KVER"

echo "building initramfs for $KVER"
mkinitcpio -r "$PWD/$ROOT" -k "$KVER" -g "$PWD/out/initramfs-linux-dany.img" 2>&1 | tail -4

ls -lh out/initramfs-linux-dany.img
echo
echo "next: 40-qemu-test.sh out/Image-dany out/initramfs-linux-dany.img"
