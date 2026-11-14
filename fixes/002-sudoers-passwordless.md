# Fix 002 — passwordless sudo that actually applies

**Date:** 2026-11-09
**Layer:** sudoers
**Status:** held

## Symptom

`/etc/sudoers.d/10-opencode` contained `dany ALL=(ALL) NOPASSWD: ALL`, `visudo -c`
reported the whole set parsed clean, `sudo -l` listed `(ALL) NOPASSWD: ALL` — and
`sudo -n true` still answered *"sudo: a password is required"*.

## Cause

sudoers resolves matching entries **in order, last match wins**, and
`/etc/sudoers.d` files are included in lexical order. `10-opencode` was read
before `10-wheel` (`%wheel ALL=(ALL:ALL) ALL`) and before Omarchy's own rules, so
the wheel entry was the last match and demanded a password. A correct rule in the
wrong position is an ignored rule.

## Fix

Renamed the drop-in so it sorts after everything else, and kept the
validate-before-activate dance: `.tmp` names contain a dot, which sudoers skips
entirely, so a broken file can be parsed without being live.

```sh
sudo cp /tmp/10-opencode /etc/sudoers.d/99-opencode.tmp
sudo chown root:root /etc/sudoers.d/99-opencode.tmp
sudo chmod 0440 /etc/sudoers.d/99-opencode.tmp
sudo visudo -c -f /etc/sudoers.d/99-opencode.tmp
sudo mv /etc/sudoers.d/99-opencode.tmp /etc/sudoers.d/99-opencode
sudo visudo -c
```

Contents:

```
# Passwordless sudo for dany, so opencode (which runs as dany) can install
# packages, edit system files, and restart services without a prompt.
dany ALL=(ALL) NOPASSWD: ALL
```

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump

`/etc/sudoers.d/` is not package-owned. Omarchy ships its own files there
(`omarchy-sudo-timeout` and friends) and never removes foreign ones, and `99-`
sorts last, so nothing it adds can silently outrank this rule.

## Verify

```sh
sudo -k; sudo -n true && echo passwordless-ok
sudo -l | head -20
```

## Revert

```sh
sudo rm /etc/sudoers.d/99-opencode
```

Then `sudo -k` and confirm the password prompt is back.
