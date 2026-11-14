# Fix NNN — short name

**Date:** YYYY-MM-DD
**Layer:** pacman hook | sudoers | systemd | ignore-rule | local package | /usr/local | kernel
**Status:** held | reverted-by-update | fixed upstream

## Symptom

The exact error text, verbatim, so it can be grepped next time. Include the
command that produced it.

```
```

## Cause

One paragraph. The mechanism, not the vibes.

## Fix

What the artifact is, where it lives, and the command that applied it. If it is
a file, paste it whole — this record is what a reinstall reads.

```sh
```

## Survives

- [ ] `pacman -Syu`
- [ ] `omarchy update`
- [ ] kernel bump
- [ ] nothing (and why that is acceptable)

Why it survives: does an update own this file, or is it in a layer above?

## Verify

```sh
```

## Revert

How to undo it cleanly, and what upstream change would make it unnecessary.
