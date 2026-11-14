#!/usr/bin/env bash
# 50-install.sh — put the tested kernel on the machine, beside the stock one.
#
# GATES, in order, and it stops at the first one that fails:
#   1. out/Image-dany and out/initramfs-linux-dany.img exist
#   2. out/qemu-result.txt says PASS   (40-qemu-test.sh wrote it)
#   3. text mode diff between the two kernels' configs was looked at by you
#
# It writes only NEW files, suffixed -dany. The stock kernel package, /boot/Image,
# /boot/initramfs-linux.img and the GRUB default entry are untouched. Removing
# the new files is a complete rollback.
#
# It does NOT edit the bootloader. It prints the entry to add, because on this
# machine the boot chain lives on /dev/nvme0n1p1 and OS-INTENT rule 5 says that
# is not ours to edit by script.
set -euo pipefail
cd "$(dirname "$0")"

[ -f out/Image-dany ] || { echo "no out/Image-dany — run 20-build.sh"; exit 1; }
[ -f out/initramfs-linux-dany.img ] || { echo "no initramfs — run 30-stage.sh"; exit 1; }
[ "$(sed -n 1p out/qemu-result.txt 2>/dev/null)" = "PASS" ] || {
    echo "refusing: 40-qemu-test.sh has not passed this kernel"; exit 1; }
[ "$(sed -n 2p out/qemu-result.txt)" = "$(sha256sum out/Image-dany | cut -d' ' -f1)" ] || {
    echo "refusing: the qemu PASS was for a different image than out/Image-dany"; exit 1; }
[ -f out/config-reviewed ] && [ out/config-reviewed -nt out/config.diff ] || {
    echo "refusing: read out/config.diff, then run: touch out/config-reviewed"; exit 1; }
[ ! -e /boot/Image-dany ] || echo "note: replacing existing /boot/Image-dany"

KVER=$(make -s -C src kernelrelease LOCALVERSION=-dany)
echo "kernel release: $KVER"

sudo install -m 644 out/Image-dany /boot/Image-dany
sudo install -m 644 out/initramfs-linux-dany.img /boot/initramfs-linux-dany.img
sudo cp -a out/root/usr/lib/modules/"$KVER" /usr/lib/modules/ 2>/dev/null || \
    sudo cp -a out/root/lib/modules/"$KVER" /usr/lib/modules/ 2>/dev/null || \
    echo "note: modules not copied; initramfs already embeds them"

echo
echo "installed:"
ls -lh /boot/Image-dany /boot/initramfs-linux-dany.img
ls -d /usr/lib/modules/"$KVER" 2>/dev/null

cat <<MSG

GRUB entry to add (one-shot test, default untouched):

  menuentry 'Omarchy — dany kernel (test)' --class arch --class gnu-linux {
      linux /opt/omarchy/boot/Image-dany root=... omarchy.loop=UUID=... rw
      initrd /opt/omarchy/boot/initramfs-linux-dany.img
  }

copy the linux/initrd lines from your existing entry and swap the two filenames.
set a one-shot boot with:  sudo grub-reboot '<exact menuentry title>'
that way a failed boot falls back to the stock entry by itself.

rollback at any time:  ./90-rollback.sh
MSG
