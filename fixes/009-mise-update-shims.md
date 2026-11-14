# 009 — a mise-managed CLI's own `update` verb goes through mise

**Date:** 2026-11-14
**Layer:** user config (`~/.bashrc`, `~/.local/bin`, `~/.local/share/mise-cli-shims`)
**Status:** held

## Symptom

```
$ opencode update
■  Could not detect the installation method. Pass --method to choose how to upgrade OpenCode.
└  Failed
```

Every agent CLI on this box is installed by mise, so every one of them has the
same hole: their updater exists, but it is looking for an install it recognises
and mise's tree is not one. That leaves `mise upgrade <tool>` as the only working
update, which is one command too many to remember per tool.

## Cause

mise installs `claude`, `codex`, `crush`, `grok`, `qwen`, `opencode`, `dsh`,
`kilo`, `kimi`, `cf`, `devin`, `kiro-cli` and the rest from npm and http
backends into `~/.local/share/mise/installs/<tool>/<version>`. Their own
updaters only know curl, `npm -g`, pnpm, bun, yarn, vp, brew and winget, so they
refuse to guess — correctly, because guessing would install a second copy that
would then fight the managed one for PATH.

`opencode upgrade --method npm` and `--method curl` both make it worse, not
better: npm writes a global copy, curl writes to `~/.opencode/bin` (fix 008).

## Fix

Three parts.

**1. The dispatcher** — `~/.local/share/mise-cli-shims/_shim`, POSIX sh. For any
call it resolves the real binary from PATH with its own directory removed, then:

- `update` / `upgrade` / `self-update` → `mise upgrade <tool>` for the tool the
  bin is mapped to, then reports old and new version
- anything else → `exec` the real binary, untouched

`MISE_SHIM_PASSTHROUGH=1` forces the old behaviour for any tool, which is the
escape hatch if some CLI means something else by `update`.

**2. The generator** — `~/.local/bin/mise-cli-shims`, Python. Reads
`mise ls --json`, finds the bins of each installed tool (`node_modules/.bin`,
`bin/`, or the install root), plus bins mise already exposes lazily in
`~/.local/share/mise/shims`, and writes one symlink per bin into the shim
directory plus a `bin<TAB>tool` map. Idempotent; `--list` shows the mapping
without touching anything. A deny list keeps `node`, `npm`, `npx`, `uv`,
`playwright`, `gh` and friends out of it — shadowing them buys nothing.

**3. PATH** — appended to `~/.bashrc`, after omarchy's rc (which is what
activates mise), so the shim directory wins:

```sh
if [ -d "$HOME/.local/share/mise-cli-shims" ]; then
    case ":$PATH:" in
        *":$HOME/.local/share/mise-cli-shims:"*) ;;
        *) PATH="$HOME/.local/share/mise-cli-shims:$PATH" ;;
    esac
    export PATH
fi
```

Now both spellings are the same operation:

```
$ opencode update
==> opencode is managed by mise — updating via: mise upgrade opencode
mise All tools are up to date
==> opencode: already current (opencode v2.3.0)
```

Rebuild the links after adding a tool to `/etc/mise/conf.d/omarchy-tools.toml`:
`mise-cli-shims`.

## Survives

- [x] `pacman -Syu` — nothing here is package-owned
- [x] `omarchy update` — same, except if `omarchy-settings` rewrites
      `~/.bashrc`; the PATH block is the only piece exposed, and it is one
      `grep` away from being re-added
- [x] kernel bump
- [ ] nothing (and why that is acceptable)

Why it survives: the shim directory only holds symlinks and one script; a mise
upgrade rewrites `~/.local/share/mise/installs/` and never touches it. Deleted
new tools are the only drift (new bin, no link), which the next `mise-cli-shims`
run fixes.

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh     # cases 009a–009e
mise-cli-shims --list
```

## Revert

```sh
rm -rf ~/.local/share/mise-cli-shims
# and delete the "mise update shims" block from ~/.bashrc
```

Upstream could make this unnecessary by teaching mise to answer an update
request from inside the tool, or by the CLIs learning the mise backend. Until
then this is the layer.
