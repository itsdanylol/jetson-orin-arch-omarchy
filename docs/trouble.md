# The trouble log

Every incident this machine has had, including the two that were self-inflicted
and the two that are still open. Not a highlight reel. The point of keeping this
is that a list of failure modes is the most useful document a hand-built system
can have, because the next failure is usually a cousin.

Cost is in wall-clock time, roughly, from the records.

## The ledger

| # | when | what | layer | cost |
| - | ---- | ---- | ----- | ---- |
| 01 | Nov 07 | GPU unreachable, desktop on llvmpipe | compositor env | hours |
| 02 | Nov 07 | "fixes" for the GPU made it worse | compositor env | hours |
| 03 | Nov 08 | ESP not mounted, no way to set the boot default | boot chain | minutes |
| 04 | Nov 08 | a `-Syu` can remove the L4T kernel | pacman | avoided |
| 05 | Nov 08 | initramfs built for the wrong kernel | mkinitcpio | avoided |
| 06 | Nov 08 | GRUB reads host-side copies, not the ones in the image | boot chain | hours |
| 07 | Nov 09 | `root=` raced the loop hook and would fsck p1 | initramfs | avoided |
| 08 | Nov 09 | every pacman transaction rejected | pacman hook | hours |
| 09 | Nov 09 | `shadow.service` failed daily | group database | minutes |
| 10 | Nov 09 | `systemd-networkd-wait-online` failed every boot | systemd | minutes |
| 11 | Nov 09 | passwordless sudo never applied | sudoers | minutes |
| 12 | Nov 09 15:41 | every new process died with SIGBUS | glibc | the day |
| 13 | Nov 09 | the guard meant to prevent 12 approved everything | tooling | the day |
| 14 | Nov 09 | the first recovery script would have deleted the GPU | recovery | nearly catastrophic |
| 15 | Nov 09 | agent tool layer poisoned by SIGBUS, cascading | tooling | hours |
| 16 | Nov 13 | the Super key never reached the input layer | keyboard firmware | hours |
| 17 | Nov 14 | a service bound `*:8787` with no auth in front of it | networking | minutes |
| 18 | Nov 14 | `opencode update` could not detect its own install | tooling | minutes |
| 19 | Nov 14 | every mise-managed CLI's `update` verb failed | tooling | minutes |
| 20 | Nov 14 | interrupted transaction left a lock that blocked pacman | pacman db | minutes |
| 21 | Nov 14 | `xattr` referenced `ENOATTR`, absent on aarch64 | build | minutes |
| 22 | Nov 14 | the kit's bar module silently broke after a rename | config | minutes |
| 23 | open | NVIDIA driver packages are not actually ignored | pacman | open |

Plus three permanent conditions that are not incidents: `nvidia-smi` does not
exist on this board, `spotify` / `steam` / `1password` / `battlenet` have no
aarch64 build, and nothing on the host may run under emulation.

## The big four

### 01 and 02: the GPU, and the wrong way to fix it

First boot came up at single-digit frame rates because the compositor was on
llvmpipe and nothing said so. `glxinfo -B` reported `direct rendering: Yes`, which
is true and useless. The renderer string is the only honest field.

The first attempts made it worse in a way that is hard to see from the inside:
`AQ_NO_MODIFIERS=1`, `AQ_TEGRA_LINEAR=1`, `LIBGL_ALWAYS_SOFTWARE=1`. Each one
removes a symptom by removing the path the symptom lived on. Tearing goes away
because tiled buffers go away. Crashes go away because the GPU goes away. The
desktop looks fine and does nothing.

The path that works: `GBM_BACKEND=nvidia-drm`, vendor EGL pinned through
`__EGL_VENDOR_LIBRARY_FILENAMES`, `AQ_DRM_DEVICES=/dev/dri/card2` so the
compositor scans out on the display controller and not on host1x, real DRM
modifiers left alone. `docs/the-display-path.md` has the chain.

Recorded as: `INTENT.md` rule 4, and the `GPU_*` result codes in
`/var/log/omarchy-gpu-check.txt` so the next drift is visible on boot.

### 08: the package manager that stopped working

Two hook files declared `Operation = Downgrade`. libalpm accepts `Install`,
`Upgrade` and `Remove` only, and it parses every hook on every transaction
whether or not the hook is involved. Result: installs, upgrades and local builds
all failed with `failed to commit transaction (failed to run transaction
hooks)`, which reads like a transaction error and is actually a syntax error in
a file nobody was touching.

The subtle part is that the hooks had been written the previous night and
nothing had needed installing since. A guard that only runs on kernel
transactions sat there, broken, for a day.

Recorded as: [fix 001](fixes/001-pacman-hook-downgrade.md).

### 12, 13, 14, 15: the day the machine died

The full postmortem is [docs/the-libc-day.md](docs/the-libc-day.md). The short
version: `apt` unpacked Debian's `libc6` over Arch's dynamic loader, every new
process died with `SIGBUS` before `main`, and the running desktop hid it.

Four failures stacked, and only one of them was the package:

- the package manager that did it should not have been able to,
- the guard that should have stopped it approved every package because it
  compared `./usr/bin/foo` against `usr/bin/foo`,
- the first recovery script ended with `rm -rf /usr/lib/aarch64-linux-gnu`,
  which is the NVIDIA userspace, and would have turned a broken afternoon into a
  reinstall,
- the agent process that was running at the time inherited the poisoned loader,
  so every tool call it made forked another dead child and reported it as the
  tool's own failure. That is where the "SIGBUS on `echo alive` means the
  process is poisoned, do not retry" rule came from.

Nothing was lost. `/home`, pacman's database, the kernel, the GPU stack and the
Ubuntu side were all intact the entire time. That is the part worth remembering:
a total outage of executability looks exactly like a dead machine and costs
nothing to fix if you know which file to put back.

Recorded as: [fix 005](fixes/005-host-apt-never-installs.md),
`recovery/RECOVER.sh`, `apply-recovery-hardening.sh`, rules 2, 3, 9, 10.

## The quiet ones

Each of these cost minutes and would have cost hours later.

**09. `shadow.service` failing daily.** `gshadow` was missing the `debug` and
`gpio` groups that `group` had, so `grpck` refused and the daily shadow check
went red. Fixed by reconciling the two files, checked by `grpck -r` and by the
service's last result. [fix 003](fixes/003-gshadow-debug-gpio.md)

**10. `systemd-networkd-wait-online` failing every boot.** Two network managers,
one winner. NetworkManager owns the interface, networkd is not even running, and
its `wait-online` unit still sat in `network-online.target` waiting for a link it
would never see. Disabled the unit, not the target.
[fix 004](fixes/004-networkd-wait-online.md)

**11. Passwordless sudo that never applied.** The drop-in was correct and sorted
before `10-wheel`, whose `%wheel ALL=(ALL:ALL) ALL` matched last and demanded a
password. sudoers is last-match-wins. Renamed to `99-*`, verified with
`sudo -k; sudo -n true`. [fix 002](fixes/002-sudoers-passwordless.md)

**03, 06. The boot chain is not in the system it boots.** The ESP is
`nvme0n1p10`, FAT32, and it is not mounted inside Omarchy. Two consequences: a
script that wants to change the boot default has to find and mount it, and GRUB
reads `/opt/omarchy/boot/Image` from the host side of the loop mount, not
`/boot/Image` inside the image, so the kernel guard has to re-export both files
after any kernel change. Miss that and you install a kernel that boots nothing.

**04, 05, 07. Three ways a good kernel bricks the box.** pacman can replace the
kernel package; `mkinitcpio` can build an initramfs for a kernel that is not the
one being booted; and passing `root=` on the command line makes the initramfs
mount, and potentially fsck, the 930 GB partition that holds the live image
before the loop hook has run. All three are held by construction now:
`IgnorePkg`, a re-pinned preset with an `lsinitcpio` assertion, and a kernel
command line that passes no `root=` at all.

**16. The keyboard that does not send the Super key.** Software was fine at
every layer, which is what made it expensive. `hyprctl` had 47 registered
superbinds, xkb rendered `Super_L` from the caps option, and the kernel saw zero
`KEY_LEFTMETA`. Reading `/dev/hidraw` directly showed 22 reports with byte 0
(the modifier bitmap) at `00` in every one while the keycodes appeared in byte 2.
The firmware has the Windows key locked and suppresses the bit. Fixed in the
keyboard's own flash by re-encoding the key-table entry as key usage `0xE3`
instead of a modifier. [fix 011](fixes/011-super-key-not-transmitted.md)

**17. A service on `*:8787` with nothing in front of it.** Not a breach, a
posture. Node's `server.listen(PORT)` without a host binds every interface, the
firewall was empty, and the `/mcp` endpoint had no principal check at all. Closed
by binding loopback, putting a Cloudflare Tunnel in front, and failing closed on
any request carrying `cf-ray` without a token. [fix 010](fixes/010-cloudflared-loopback-brain.md)

**18, 19. Two tool managers that do not know about each other.** mise installs
`opencode`, then `opencode update` says it cannot detect the installation method,
because mise is not one it knows. Then the shim layer: every CLI's `update` verb
gets routed to `mise upgrade` by a wrapper that sits ahead of mise on `PATH`.
Two problems, two small scripts, both asserted daily.
[fix 008](fixes/008-opencode-mise-managed.md),
[fix 009](fixes/009-mise-update-shims.md)

**20. A lock file with no owner.** An interrupted transaction left
`/var/lib/pacman/db.lck` behind. Every later pacman run refused with "unable to
lock database", which sounds like a live process and was not. The check is
`[ ! -e db.lck ] || pgrep -x pacman`. [fix 012](fixes/012-pacman-interrupted-transaction.md)

**21. `ENOATTR` does not exist on aarch64.** `xattr` 0.2.3 calls
`libc::ENOATTR`, which on Linux is spelled `ENODATA` and on aarch64 is simply not
there. Vendored patch, checked only if the tree is present.
[fix 013](fixes/013-xattr-enoattr-aarch64.md)

**22. A module renamed itself out of existence.** The bar module was `jetson`,
then `orin`. The check looked for the old id and went red on a working system.
Fixed by accepting both ids so the check tracks the module instead of a
historical name. Small, and a good reminder that a check can be the broken thing.

## Still open

**23. The NVIDIA ignore list is in the wrong section.** `/etc/pacman.conf` has
an `IgnorePkg` line with `nvidia-utils nvidia nvidia-dkms nvidia-open
lib32-nvidia-utils` inside `[omarchy]`, the repo section, where it is ignored.
pacman says so on every invocation:

```text
warning: directive 'IgnorePkg' in section 'omarchy' not recognized
```

The real `IgnorePkg` in `[options]` holds `linux-aarch64` and the compositor
packages, but not the driver packages. So the thing `packages/jetson-vendor-stack`
exists to prevent (pacman walking the desktop driver in and overwriting the
vendor files) is still one dependency away. Moving six names to the right section
closes it.

## What the ledger is for

Not for the story. For the shape. Twelve of these are "a tool wrote a file that
another tool reads, and the contract changed". Three are "two owners, one
resource". Two are "a guard that was never tested". One is "an assumption about
where a file lives", and one is a keyboard.

The next failure will be one of those shapes. That is why each record ends with
`Verify` and `Revert` instead of a description: the useful artifact is the check,
not the anecdote.
