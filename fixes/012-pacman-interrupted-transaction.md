# 012 — interrupted pacman transaction: stale lock and a half-registered package

**Date:** 2026-11-14
**Layer:** pacman database (`/var/lib/pacman`)
**Status:** held

## Symptom

`pacman -Dk` started reporting:

```
error: 'webkitgtk-6.0-2.54.2-1': description file is missing
error: 'webkitgtk-6.0-2.54.2-1': file list is missing
```

and `/var/lib/pacman/db.lck` was still on disk with no pacman running. Every
later transaction would have been refused with "unable to lock database".

The custom-os verify run caught it as `FAIL pacman database`.

## Cause

A `pacman -S webkitgtk-6.0` was interrupted mid-transaction (the calling process
was killed while the package was being installed). pacman had already created
the local database directory for the package but never wrote `desc` and `files`
into it, and never removed the lock file.

This is the same class as fix 001: a broken pacman state does not break one
install, it breaks *all* of them, including the timer's own checks.

## Fix

```sh
# 1. confirm nothing is actually running, then drop the stale lock
pgrep -a pacman || sudo rm -f /var/lib/pacman/db.lck

# 2. a reinstall cannot proceed while the DB entry is corrupt — remove it
sudo rm -rf /var/lib/pacman/local/webkitgtk-6.0-2.54.2-1

# 3. the package files are now unowned and block a clean install, so
#    reinstall over them; --overwrite is scoped to this one transaction
sudo pacman -S --noconfirm --overwrite '*' webkitgtk-6.0

# 4. prove the database is whole again
sudo pacman -Dk
```

Result: `No database errors have been found!` and
`pacman -Qo /usr/lib/libjavascriptcoregtk-6.0.so.1` reports
`webkitgtk-6.0 2.54.2-1` — the files are owned again.

Note on step 2: removing the local entry while the files stay on disk is safe
precisely because step 3 reinstalls the same version. Deleting the entry and
stopping there would leave unowned files, which is worse than the original
problem.

## Survives

- [x] `pacman -Syu` — the DB is in a normal state again
- [x] `omarchy update`
- [x] kernel bump
- [ ] nothing to revert — this is a repair, not a workaround

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh        # cases 012a, plus 005's pacman database
sudo pacman -Dk                               # must print "No database errors have been found!"
```

The durable check is `012a`: a lock file must never exist while no pacman
process is running. That catches the *next* interruption before it blocks a
transaction.

## Revert

None. There is nothing to undo; the machine is in the state it should have been
in before the interrupted command.
