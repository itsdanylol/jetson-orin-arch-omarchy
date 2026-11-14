# Fix 003 — shadow.service failing on every boot

**Date:** 2026-11-09
**Layer:** system database (group/shadow)
**Status:** held

## Symptom

```
● shadow.service  loaded failed failed  Verify integrity of password and group files

Nov 09 00:00:00 alarm sh[654602]: no matching group file entry in /etc/gshadow
Nov 09 00:00:00 alarm sh[654602]: add group 'debug' in /etc/gshadow? No
Nov 09 00:00:00 alarm sh[654602]: add group 'gpio' in /etc/gshadow? No
Nov 09 00:00:00 alarm sh[654602]: grpck: no changes
Nov 09 00:00:00 alarm systemd[1]: shadow.service: Main process exited, code=exited, status=2/INVALIDARGUMENT
```

## Cause

The Jetson stack creates the `debug` and `gpio` groups during setup, but they were
added to `/etc/group` only — `/etc/gshadow` has no matching entries, so `grpck`
found two inconsistencies, printed them, and exited 2 (the interactive prompt got
EOF under systemd). Non-fatal for the running system, permanent red unit in every
`systemctl --failed`, and a real integrity gap in the shadow database.

## Fix

`grpck` is the tool for exactly this; answering yes adds the missing entries and
rewrites both files safely.

```sh
sudo sh -c 'yes | grpck'
sudo systemctl start shadow.service
```

Result: `grpck: the files have been updated`, service `active`, `grpck -r` silent.

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump

`/etc/gshadow` is a system database, not package content. Reinstalling `shadow`
does not clear it.

## Verify

```sh
sudo grpck -r && systemctl is-active shadow.service
```

## Revert

Not worth reverting — the state before was an inconsistent database. If a future
tool adds a group without gshadow again, the same two commands apply, and the
daily check reports it.
