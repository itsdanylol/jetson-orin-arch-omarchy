#!/usr/bin/env bash
# 40-qemu-test.sh — boot a kernel image under QEMU and prove it reaches init.
#
# This is the "test it fully" step. A kernel that builds is not a kernel that
# boots; a kernel that boots on the dev board is not proof either, because you
# only get one shot at it. So the candidate kernel is booted here first, on an
# emulated machine that cannot touch this one.
#
# PASS = the kernel printed its banner AND started userland (init/switch-root
#        attempt). On `virt` there is no tegra hardware, so init WILL fail to
#        find the real root — that is expected and is not a failure. What we
#        are proving is: the image is executable, the decompressor works, the
#        CPU/arch code runs, modules load, and control reaches userspace.
#
# Usage:  40-qemu-test.sh <Image> [initramfs] [timeout-seconds]
# Output: serial log at out/qemu-serial.log, verdict on stdout.

set -uo pipefail

IMG=${1:?usage: 40-qemu-test.sh <Image> [initramfs] [timeout]}
INITRD=${2:-}
TIMEOUT=${3:-90}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"
LOG="$OUT/qemu-serial.log"
mkdir -p "$OUT"

[ -f "$IMG" ] || { echo "FAIL  no image at $IMG"; exit 2; }

QEMU=$(command -v qemu-system-aarch64 || true)
[ -n "$QEMU" ] || { echo "FAIL  qemu-system-aarch64 not installed"; exit 2; }

# sanity before booting: is it even an arm64 kernel image?
if ! file -b "$IMG" | grep -qi 'arm64\|aarch64\|Linux kernel'; then
    echo "FAIL  $IMG is not an aarch64 kernel image"
    file "$IMG"
    exit 2
fi

args=(
    -M virt -cpu cortex-a72 -m 2048 -smp 2 -nographic
    -kernel "$IMG"
    -append "console=ttyAMA0 earlycon=pl011,0x09000000 rdinit=/init panic=1 oops=panic"
)
# an initramfs in /boot is root-only (0600); qemu runs as us, so copy it out
if [ -n "$INITRD" ] && [ -f "$INITRD" ]; then
    if [ -r "$INITRD" ]; then
        args+=(-initrd "$INITRD")
    else
        if ! cp "$INITRD" "$OUT/initrd-test.img" 2>/dev/null; then
            sudo -n cp "$INITRD" "$OUT/initrd-test.img" 2>/dev/null &&
                sudo -n chown "$(id -u):$(id -g)" "$OUT/initrd-test.img" &&
                chmod 644 "$OUT/initrd-test.img"
        fi
        [ -r "$OUT/initrd-test.img" ] || { echo "FAIL  cannot stage $INITRD"; exit 2; }
        args+=(-initrd "$OUT/initrd-test.img")
    fi
fi

echo "booting $(basename "$IMG") for ${TIMEOUT}s ..."
: >"$LOG"
timeout "$TIMEOUT" "$QEMU" "${args[@]}" >"$LOG" 2>&1
rc=$?

banner=$(grep -cE "Booting Linux|Linux version" "$LOG" 2>/dev/null || true)
init=$(grep -cE "Run /init as init process|systemd\[1\]" "$LOG" 2>/dev/null || true)
panic=$(grep -cE "Kernel panic|Unable to mount root|not syncing" "$LOG" 2>/dev/null || true)

echo "serial log: $LOG  ($(wc -l <"$LOG") lines, qemu rc=$rc)"
echo "  kernel banner : $banner"
echo "  reached init  : $init"
echo "  panics        : $panic"

rm -f "$OUT/qemu-result.txt"
if [ "$banner" -gt 0 ] && [ "$init" -gt 0 ]; then
    echo "PASS  kernel executes and reaches userspace"
    # bind the verdict to the exact bytes tested, so 50-install.sh cannot
    # accept a result that belongs to a different image or initramfs
    { echo "PASS"; sha256sum "$IMG" | cut -d' ' -f1
      if [ -n "$INITRD" ] && [ -f "$INITRD" ]; then sudo -n sha256sum "$INITRD" 2>/dev/null || sha256sum "$INITRD" 2>/dev/null; fi | cut -d' ' -f1
    } > "$OUT/qemu-result.txt"
    exit 0
fi
echo "FAIL  kernel did not reach userspace — see $LOG"
tail -20 "$LOG" 2>/dev/null
exit 1
