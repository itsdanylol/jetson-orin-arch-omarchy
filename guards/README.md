# Kernel guard

`jetson-kernel-guard` keeps this board on the kernel that actually drives its
display.

## Install

```sh
sudo bash install.sh
```

It refuses to run unless `/boot/Image` is already `6.8.12-1021-tegra`, because
the first thing it does is copy the current boot chain into
`/var/backups/jetson-kernel/golden/`. A guard that snapshots the wrong kernel is
worse than no guard.

## What gets installed

```text
/usr/local/bin/jetson-kernel-guard
/etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook   Install, Upgrade
/etc/pacman.d/hooks/95-jetson-kernel-guard.hook      Install, Upgrade
```

and `IgnorePkg` for `linux-aarch64` in `/etc/pacman.conf`.

## The two verbs

```sh
jetson-kernel-guard --snapshot   # before a kernel transaction
jetson-kernel-guard --verify     # after one, and daily from verify.sh
```

`--snapshot` copies `Image`, the initramfs and the mkinitcpio preset into a
timestamped directory, keeps the five most recent, never touches `golden/`.

`--verify` reads the version string out of `/boot/Image`, restores the golden
copy if it drifted, re-pins `ALL_kver` in the preset, rebuilds the initramfs if
either changed, confirms with `lsinitcpio` that the initramfs carries this
kernel's modules, then re-exports both files to `/opt/omarchy/boot/` because GRUB
reads the host-side copies and not the ones inside the loop-mounted root.

## The hook bug, if you copy this

Hook files must only use `Operation = Install`, `Upgrade` or `Remove`. libalpm
rejects the whole file otherwise, and since hooks are parsed for every
transaction, one bad hook file disables package management entirely. An earlier
version of these hooks said `Downgrade` and did exactly that. See
[fix 001](../fixes/001-pacman-hook-downgrade.md).
