# Fixes

Every fix this machine has needed, why, and how it is proven still in place.

| # | Fix | Layer | Status | Check |
| - | --- | ----- | ------ | ----- |
| [001](001-pacman-hook-downgrade.md) | pacman rejected every transaction (`Operation = Downgrade`) | pacman hook | held | `pacman hooks parse` |
| [002](002-sudoers-passwordless.md) | Passwordless sudo shadowed by `%wheel` ordering | sudoers | held | `passwordless sudo` |
| [003](003-gshadow-debug-gpio.md) | `shadow.service` failing, gshadow missing `debug` / `gpio` | system database | held | `grpck`, `shadow.service` |
| [004](004-networkd-wait-online.md) | `systemd-networkd-wait-online` failing on every boot | systemd | held | `networkd wait-online off` |
| [005](005-host-apt-never-installs.md) | `apt` on the host unpacked Debian `libc6` over Arch's loader | local package | held | loader, apt, dpkg guards |
| [008](008-opencode-mise-managed.md) | `opencode update` could not detect the install method | user config | held | `opencode comes from mise` |
| [009](009-mise-update-shims.md) | every mise-managed CLI's `update` verb failed | user config | held | `shim routes update to mise` |
| [010](010-cloudflared-loopback-brain.md) | brain bound `*:8787` with no auth in front of `/mcp` | pacman + user unit | held | `edge traffic refused without a token` |
| [011](011-super-key-not-transmitted.md) | Super key muted by keyboard firmware; re-encoded in its key table | keyboard flash | held | `key entry reads 02 02 e3` |
| [012](012-pacman-interrupted-transaction.md) | Interrupted transaction left a stale lock and a half-registered package | pacman database | held | `no stale pacman lock` |
| [013](013-xattr-enoattr-aarch64.md) | `xattr` 0.2.3 needs `libc::ENOATTR`, which aarch64 Linux does not have | project vendor patch | held | `xattr vendored patch in place` |

Numbers 006 and 007 have checks in `checks/verify.sh` but no record here: the bar
module and the native-x86 audit were small enough to be written straight into the
harness. They are still asserted daily, which is the part that matters.

Add a row when you add a fix. A fix without a row and a check is not a fix.
