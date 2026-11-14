# 008 — opencode is a mise tool, with no second install behind it

**Date:** 2026-11-14
**Layer:** user config (`~/.local/bin`, `~/.opencode/`)
**Status:** held

## Symptom

```
$ opencode update
┌  Upgrade
│
■  Could not detect the installation method. Pass --method to choose how to upgrade OpenCode.
│
└  Failed
```

Same text from `opencode upgrade`. `opencode --version` answered `v2.3.0`, which
was already the newest release — so nothing was actually out of date.

## Cause

Two opencode installs existed side by side.

1. **mise**, the real one: npm backend `@opencode/cli`, declared in
   `/etc/mise/conf.d/omarchy-tools.toml` (owned by `omarchy-settings`) with
   `auto_update = "4h"`, installed to
   `~/.local/share/mise/installs/opencode/2.3.0`.
2. **curl**, stale: a 243 MB standalone ELF at `~/.opencode/bin/opencode`,
   version 2.2.6, from the official install script. Its directory was prepended
   to `PATH` by `/etc/profile.d/30-user-bin.sh` and by `~/.bashrc`, both guarded
   only on `[ -d "$HOME/.opencode/bin" ]`.

mise's activation hook prepends its shims last, so mise won PATH and the stale
binary sat dormant in third place. That is why the version looked right while
the updater disagreed: `opencode upgrade` classifies installs by layout and only
knows curl / npm / pnpm / bun / yarn / vp / brew / winget. A mise npm-tree
matches none of them, so it refused to guess. `--method` was not a way out:
`curl` writes to `~/.opencode/bin` (reviving 2.2.6), `npm` writes a second global
copy — either one forks the install away from mise.

`~/.local/bin/opencode-supervise` had the same trap: `real="${OPENCODE_BIN:-$HOME/.opencode/bin/opencode}"`
hardcoded the stale path, so running the supervisor directly would have launched
2.2.6 while `opencode` on PATH was 2.3.0.

## Fix

```sh
rm -rf ~/.opencode/bin            # the curl install only; state, plugin, skills stay
```

Both PATH lines are `[ -d ... ]`-guarded, so they became no-ops with no edit.
`~/.local/bin/opencode-supervise` now resolves the binary the way the shell
does, so the supervisor always follows mise:

```sh
real="${OPENCODE_BIN:-$(command -v opencode 2>/dev/null)}"
if [ ! -x "$real" ]; then
    printf 'opencode-supervise: no opencode binary found on PATH\n' >&2
    exit 127
fi
```

Updates go through mise and nowhere else:

```sh
mise upgrade opencode            # or: mise up -y
mise latest opencode             # what upstream has
```

`auto_update = "4h"` in the omarchy tool config already pulls a new release
before launch, at most four hours behind. `opencode update` will keep failing on
this box and that is correct — it is not the installer of record here.

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump
- [ ] nothing (and why that is acceptable)

Why it survives: `auto_update` and the tool declaration live in
`/etc/mise/conf.d/omarchy-tools.toml`, owned by `omarchy-settings`, so a mise
upgrade reinstalls into `~/.local/share/mise/installs/` and never recreates
`~/.opencode/bin`. The supervisor is a user script in `~/.local/bin`, owned by
nobody. A fresh curl install is the only thing that can undo it — the check below
catches that.

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh        # cases 008a–008c
command -v opencode                            # must be the mise path
mise which opencode
```

## Revert

```sh
curl -fsSL https://opencode.ai/install | bash   # restores ~/.opencode/bin
mise install opencode@2.2.6                     # that exact old build, if wanted
```

No upstream change makes this unnecessary: the updater would have to learn the
mise backend. Until then mise is the update channel and this stays.
