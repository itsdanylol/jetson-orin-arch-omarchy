#!/usr/bin/env bash
# 90-rollback.sh — remove the -dany kernel completely. Stock kernel untouched.
set -euo pipefail
cd "$(dirname "$0")"
KVER=$(make -s -C src kernelrelease LOCALVERSION=-dany 2>/dev/null || echo "")
sudo rm -f /boot/Image-dany /boot/initramfs-linux-dany.img
case "$KVER" in *-dany) sudo rm -rf /usr/lib/modules/"$KVER";; esac
echo "removed -dany kernel files; the stock kernel and its boot entry are as they were"
