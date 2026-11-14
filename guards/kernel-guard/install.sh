#!/bin/bash
# Installs the Jetson kernel guard: holds linux-aarch64, protects /boot/Image
# and the mkinitcpio kernel pin, snapshots the boot chain before kernel
# transactions and verifies it after.
#
#   sudo bash /home/dany/jetson-guard/install.sh

set -euo pipefail

[[ $EUID -eq 0 ]] || {
  echo "run with sudo: sudo bash $0" >&2
  exit 1
}

KVER=6.8.12-1021-tegra
GOLD=/var/backups/jetson-kernel/golden
PRESET=/etc/mkinitcpio.d/linux-aarch64.preset
IMAGE=/boot/Image
GUARD=/usr/local/bin/jetson-kernel-guard
SRC=$(cd "$(dirname "$0")" && pwd)

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

say "1/6 — checking the kernel that is installed right now"
cur=$(strings -a "$IMAGE" 2>/dev/null | grep -m1 '^Linux version' || true)
cur=${cur#Linux version }
cur=${cur%% *}
if [[ $cur != "$KVER" ]]; then
  echo "refusing to run: /boot/Image is '$cur', not $KVER." >&2
  echo "the guard would save the wrong kernel as its reference copy." >&2
  exit 1
fi
echo "ok: /boot/Image is $KVER"

say "2/6 — saving the reference boot chain"
install -d -m 700 "$GOLD"
cp -a --reflink=auto "$IMAGE" "$GOLD/Image" 2>/dev/null || cp -a "$IMAGE" "$GOLD/Image"
cp -a --reflink=auto /boot/initramfs-linux.img "$GOLD/initramfs-linux.img" 2>/dev/null ||
  cp -a /boot/initramfs-linux.img "$GOLD/initramfs-linux.img"
cp -a "$PRESET" "$GOLD/linux-aarch64.preset"
cp -a /etc/pacman.conf "$GOLD/pacman.conf"
ls -lh "$GOLD"

say "3/6 — installing the guard"
install -m 755 "$SRC/jetson-kernel-guard" "$GUARD"
echo "ok: $GUARD"

say "4/6 — installing pacman hooks"
cat >/etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook <<'EOF'
# Snapshot the live boot chain before anything installs a kernel.
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Downgrade
Type = Path
Target = boot/Image

[Action]
Description = Snapshotting the Jetson L4T kernel before the transaction...
When = PreTransaction
Exec = /usr/local/bin/jetson-kernel-guard --snapshot
EOF

cat >/etc/pacman.d/hooks/95-jetson-kernel-guard.hook <<'EOF'
# Refuse to leave a mainline kernel where the L4T kernel belongs.
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Downgrade
Type = Path
Target = boot/Image
Target = boot/initramfs-linux.img

[Action]
Description = Verifying the Jetson L4T kernel and initramfs survived...
When = PostTransaction
Exec = /usr/local/bin/jetson-kernel-guard --verify
EOF
echo "ok: 94-jetson-kernel-snapshot.hook, 95-jetson-kernel-guard.hook"

say "5/6 — holding linux-aarch64 and protecting the boot files"
python3 - "$KVER" <<'PY'
import re
import shutil
import sys
import time

conf = "/etc/pacman.conf"
text = open(conf).read()
shutil.copy2(conf, f"{conf}.bak.{time.strftime('%Y%m%d-%H%M%S')}")

held = {
    "hyprland", "aquamarine", "hyprgraphics", "quickshell",
    "hyprgraphics-shim", "aquamarine-shim", "linux-aarch64",
}
lines = text.splitlines()
out = []
placed = False
for line in lines:
    if re.match(r"^\s*IgnorePkg\s*=", line):
        if not placed:
            out.append("IgnorePkg   = " + " ".join(sorted(held)))
            placed = True
        continue          # drop duplicate IgnorePkg lines
    out.append(line)

if not placed:
    for i, line in enumerate(out):
        if re.match(r"^\s*HoldPkg\s*=", line):
            out.insert(i + 1, "IgnorePkg   = " + " ".join(sorted(held)))
            break

if not any(re.match(r"^\s*NoUpgrade\s*=", l) for l in out):
    anchor = max(
        i for i, l in enumerate(out)
        if re.match(r"^\s*(IgnorePkg|HoldPkg)\s*=", l)
    )
    out[anchor + 1:anchor + 1] = [
        "# Never let a linux package replace the transplanted Jetson L4T kernel",
        "# or reset the initramfs kernel pin. jetson-kernel-guard owns these.",
        "NoUpgrade    = boot/Image boot/Image.gz etc/mkinitcpio.d/linux-aarch64.preset",
    ]

open(conf, "w").write("\n".join(out) + "\n")
print("ok: pacman.conf updated (backup written alongside)")
PY

say "6/6 — verifying"
"$GUARD" --verify

echo
echo "held packages:"
if pacman -Q linux-aarch64 >/dev/null 2>&1; then
  pacman -Q linux-aarch64
fi
echo
echo "done. 'omarchy update' will now skip linux-aarch64 and keep the L4T kernel."
echo "undo:  sudo rm /etc/pacman.d/hooks/9[45]-jetson-kernel-*.hook \\"
echo "         && sudo sed -i 's/ linux-aarch64//' /etc/pacman.conf"
