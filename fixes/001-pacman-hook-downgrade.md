# Fix 001 — pacman rejected every transaction

**Date:** 2026-11-09
**Layer:** pacman hook
**Status:** held

## Symptom

Any `pacman -U`, including installing a package built locally:

```
error: hook /etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook line 5: invalid value Downgrade
error: hook /etc/pacman.d/hooks/95-jetson-kernel-guard.hook line 5: invalid value Downgrade
error: failed to commit transaction (failed to run transaction hooks)
Errors occurred, no packages were upgraded.
```

## Cause

Both kernel-guard hooks declared `Operation = Downgrade` in their `[Trigger]`
section. libalpm only understands `Install`, `Upgrade`, and `Remove` there; the
parser rejects the file. Hooks are parsed for **every** transaction, whether or
not their targets are involved, so these two files made the whole package
manager unusable — installs, upgrades, and local builds alike. Written by an
earlier tool run, unnoticed until something needed installing.

## Fix

Dropped the invalid line from both hooks; `Install` and `Upgrade` already cover
the case they were written for (a kernel package replacing `boot/Image`).

```sh
sudo cp -a /etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook /etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook.bak
sudo cp -a /etc/pacman.d/hooks/95-jetson-kernel-guard.hook /etc/pacman.d/hooks/95-jetson-kernel-guard.hook.bak
sudo sed -i '/^Operation = Downgrade$/d' \
    /etc/pacman.d/hooks/94-jetson-kernel-snapshot.hook \
    /etc/pacman.d/hooks/95-jetson-kernel-guard.hook
```

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump

`/etc/pacman.d/hooks/` belongs to no package: pacman never rewrites it. But a
future agent rebuilding the kernel guard could write `Downgrade` again — that is
exactly what `checks/verify.sh` catches, and the skill forbids it.

## Verify

```sh
sh -c 'grep -h "^Operation" /etc/pacman.d/hooks/*.hook | sort -u'
# every value must be Install, Upgrade, or Remove
```

## Revert

Nothing to revert: the hooks are strictly looser than before. If a real
downgrade ever needs a hook, express it with `Operation = Upgrade` (a downgrade
is a package replacement) plus a version check in the `Exec` script.
