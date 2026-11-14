# The ten rules

Written after the machine died, revised after each near miss. Each one costs a
sentence to read and would have saved hours.

## 1. Native first

aarch64 packages, ARM builds, the vendor GPU stack. No box64 or FEX on the host
unless there is genuinely no native build and it can be contained. Emulation
that works is still emulation.

`checks/native-audit.sh` enforces it: scans `/usr/bin`, `/usr/local/bin`,
`~/.local/bin` and `/opt` for x86 executables, checks `binfmt_misc` for handlers
that would silently catch an x86 binary, and reads `%ARCH%` straight out of
every pacman database entry. box64 and the qemu static helpers are allowed to
exist. Nothing is allowed to run under them by accident.

## 2. No Debian on the Arch root

`apt` and `dpkg` write into the same `/usr` as pacman. That is not using a
Debian tool, it is overwriting the base system. It replaced glibc's dynamic
loader and made nothing start at all.

Debian software lives in `distrobox` / `podman`, never on the host. The host's
`apt` is configured to simulate only, and `dpkg` refuses to run without an
explicit token.

## 3. Never delete a shared directory. Delete named files.

`/usr/lib/aarch64-linux-gnu` is not Debian's directory. It is a shared one, and
it holds the entire NVIDIA userspace: `libcuda.so*`, `nvidia/`, `tegra/`,
`tegra-egl/`, `gbm/`, `gstreamer-1.0/`, `libvulkan.so.1`, `libilm*`, `libnvcu*`.

`rm -rf` on it takes the GPU with it. Remove the exact paths a package manifest
names, one file at a time, and nothing else. This one was nearly learned twice.

## 4. The GPU path is load-bearing

`GBM_BACKEND=nvidia-drm`, vendor EGL, real DRM modifiers, `card2`. Do not fix
tearing with `AQ_NO_MODIFIERS`, `AQ_TEGRA_LINEAR` or `LIBGL_ALWAYS_SOFTWARE`.
Those are what broke it.

A compositor that falls back to llvmpipe still draws a desktop, so this failure
looks like a performance problem and behaves like a wrong answer. The per-boot
report at `/var/log/omarchy-gpu-check.txt` exists so it is visible.

## 5. Ubuntu's boot chain is off limits

`/boot`, the ESP, NVRAM and the p1 files are not ours to edit. The image is the
thing that changes.

This is why the kernel rig prints a GRUB entry instead of writing one, and why
recovery is a script run from the Ubuntu side with the image mounted, instead of
a live USB.

## 6. Fix the system, not the app

Prefer the env var, the unit, the package, the config file, over per-app flags
and per-app wrappers.

A wrapper fixes one program and hides the problem from the next one. A unit or a
package fixes the thing they all share.

## 7. Evidence, not vibes

A probe, a number, a log line. If a route is dead, say which number killed it
and stop patching the dead snake.

Every claim in these records is paired with the command that produced it. When
this repo says the GL path uses real modifiers, there is an output behind it.

## 8. Always leave a way back

Backup before the risky edit, keep the llvmpipe mode one command away, keep
`RECOVER.sh` working.

The kernel rig has `90-rollback.sh`. The guard has a golden snapshot. The
compositor has `omarchy-gpu-mode cpu`. None of that is decoration: each one has
been the way out at least once.

## 9. A guard is untested code until it has blocked something

Anything supposed to refuse an action, whether a wrapper, a hook or a check, is
tested against a real case before the destructive operation runs behind it. A
safety net that has never caught a fall is decoration.

`apt-guard` approved every package for days because it compared `./usr/bin/foo`
against `usr/bin/foo`. The guard worked perfectly. It just never matched
anything, and nobody had handed it a collision to test.

## 10. Destructive paths get read twice

Before `rm`, `dd`, `--overwrite`, or any loop over a manifest: say out loud what
the path contains and what the glob matches. If the answer is "a directory
someone else owns", stop.

This is the rule that would have prevented the v1 recovery script from deleting
the GPU stack, and it is written as a speech act on purpose. Saying it out loud
is the check.
