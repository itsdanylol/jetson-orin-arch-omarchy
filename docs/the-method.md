# The method

Three artifacts per fix, and none of them optional. The point is not
documentation. The point is that the machine notices when it drifts back.

## 1. The record

`fixes/NNN-name.md`, from `fixes/000-template.md`. Same headings every time,
because the headings are the questions that get skipped when you are in a hurry.

```text
# Fix NNN — one line, the symptom
**Date:**   when it happened
**Layer:**  pacman hook | sudoers | systemd | local package | user config | ...
**Status:** held

## Symptom      what you saw, verbatim, including the error text
## Cause        the mechanism. not "it was broken", why it was broken
## Fix          the artifact, pasted whole. not a description of the artifact
## Survives     which updates must not undo it, as a checklist
## Verify       the command that proves it is still in place
## Revert       how to take it out, honestly, including when not to
```

The `Fix` section pastes the file. A record that says "added a sudoers rule"
is worthless in six months. A record that contains the five lines that were
added can be reapplied by someone who was not there.

`fixes/INDEX.md` is the table: number, symptom, layer, status, check name. A fix
without a row is not in the registry.

## 2. The check

`checks/verify.sh` is one POSIX shell script, no framework, no dependencies.
Each fix gets a `check` call naming the assertion and the command that asserts
it.

```sh
check "L4T kernel booted" sh -c '[ "$(uname -r)" = "6.8.12-1021-tegra" ]'
check "loader matches pacman glibc" sh -c '
    want=$(pacman -Q glibc | awk "{print \$2}" | grep -oE "^[0-9]+\.[0-9]+")
    have=$(/usr/lib/ld-linux-aarch64.so.1 --version | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
    [ "$want" = "$have" ] || { echo "want $want have $have"; exit 1; }'
```

Three design choices in that harness are load-bearing.

**A check asserts the outcome, not the mechanism.** "kernel guard installed"
tests that the binary is executable. The check that matters is the one that
boots. Where both are cheap, both are present.

**Checks that depend on hardware skip cleanly.** The keyboard check returns
success when that keyboard is not attached, so the suite is still meaningful on a
different box. A skipped check is not a false pass if the skip is explicit.

**Failures name the delta.** `want 2.43 have 2.41` in the failure line means the
next person does not start the diagnosis from zero.

Current state, 2026-11-14: **34 assertions, all passing.**

## 3. The timer

`~/.config/systemd/user/custom-os-verify.timer`, daily, `Persistent=true`,
`RandomizedDelaySec=600`. It runs the same script the human runs, appends one
line to `~/.local/state/custom-os/verify.log`, and on failure sends a critical
desktop notification:

```sh
notify-send -a "custom-os" -u critical "A fix was reverted"
```

A failure at 03:00 that nobody sees is a failure discovered the next time
something breaks. The notification is the difference between a log and an alarm.

## What qualifies as held

Not "it works right now". These:

- it lives in a layer a package update does not own,
- the record contains the artifact, not a summary of it,
- a check asserts it, and the check fails when the fix is removed,
- the check has been run against the broken state once, so its failure mode is
  known rather than assumed.

That last line is rule 9 applied to the checks themselves. A test that has never
failed is a test that has never tested anything, and `verify.sh` has had exactly
that problem: for a while, three assertions were passing because they matched
nothing at all.

## What this does not scale to

This registry is for one machine, with absolute paths, written by the person who
lives in it. It is not a portable test suite and it is not trying to be. The
transferable parts are the shape of the record and the three-step rule. Copy
those into your own registry and the specifics will follow from your hardware.
