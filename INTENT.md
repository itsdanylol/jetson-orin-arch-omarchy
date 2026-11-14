# OS-INTENT — what this machine is for

**Machine.** Jetson Orin Nano Super, 8 GB, T234/GA10B. Arch Linux ARM + Omarchy
+ Hyprland. The OS is not a partition: it is a 512 GB ext4 image,
`OMARCHY`, at `/opt/omarchy/omarchy.img`, loop-mounted at `/`. It lives on
`/dev/nvme0n1p1` (930 GB, ext4, label `APP`), next to Ubuntu in the GRUB menu.
Ubuntu is the recovery system and must keep working no matter what happens here.

**What I am doing.** Turning this into an actual good OS of my own — not a
demo, not a pile of workarounds propping each other up. Everything runs
**natively on aarch64**. If something only exists as x86, it is not native, and
it does not belong on the host.

## The rules

1. **Native first.** aarch64 packages, ARM builds, the vendor GPU stack.
   No box64/FEX on the host unless there is genuinely no native build and it
   can be contained. Emulation that works is still emulation.
2. **No Debian on the Arch root.** `apt`/`dpkg` write into the same `/usr` as
   pacman. That is not "using a Debian tool", that is overwriting the base
   system — it replaced glibc's dynamic loader and made nothing start at all.
   Debian software lives in `distrobox` / `podman`, never on the host.
3. **Never delete a shared directory. Delete named files.** `/usr/lib/aarch64-linux-gnu`
   is not Debian's directory — it is a shared one holding the whole NVIDIA
   userspace (`libcuda.so*`, `nvidia/`, `tegra/`, `tegra-egl/`, `gbm/`,
   `gstreamer-1.0/`, `libvulkan.so.1`, `libilm*`, `libnvcu*`). `rm -rf` on it
   takes the GPU with it. Remove the exact paths a package manifest names, one
   file at a time, and nothing else. This is written in blood, twice.
4. **The GPU path is load-bearing.** `GBM_BACKEND=nvidia-drm`, vendor EGL,
   real DRM modifiers, `card2`. Do not "fix" it with `AQ_NO_MODIFIERS`,
   `AQ_TEGRA_LINEAR` or `LIBGL_ALWAYS_SOFTWARE` — those are what broke it.
5. **Ubuntu's boot chain is off limits.** `/boot`, the ESP, NVRAM and the p1
   files are not ours to edit. The image is the thing that changes.
6. **Fix the system, not the app.** Prefer the env var, the unit, the package,
   the config file — over per-app flags and per-app wrappers.
7. **Evidence, not vibes.** A probe, a number, a log line. If a route is dead,
   say which number killed it and stop patching the dead snake.
8. **Always leave a way back.** Backup before the risky edit, keep the llvmpipe
   mode one command away, keep `RECOVER.sh` working.
9. **A guard is untested code until it has blocked something.** Anything that
   is supposed to refuse an action — a wrapper, a hook, a check — is tested
   against a real case *before* the destructive operation runs behind it. A
   safety net that has never caught a fall is decoration.
10. **Destructive paths get read twice.** Before `rm`, `dd`, `--overwrite`, or
    any loop over a manifest: say out loud what the path contains and what the
    glob matches. If the answer is "a directory someone else owns", stop.

## What happened on 2026-11-09 — and why the rules exist

A host-side `apt-get install` unpacked Debian's `libc6 2.41`. That package's
file list ends with `/usr/lib/ld-linux-aarch64.so.1` — Arch's glibc 2.43
**dynamic loader**. Every new `execve()` loaded the 2.41 loader against the
2.43 libc and faulted before `main`: SIGBUS on every new process. Running
processes survived, which is why the desktop kept working while nothing could
start. Cold file reads were fine, so the disk was never involved.

Two failures made it worse than it had to be, both mine:

- The `apt-guard` wrapper compared `./usr/bin/foo` against `usr/bin/foo`
  without stripping `./`, so it approved every package. It had never been run
  against a real collision. → rule 9.
- The first `RECOVER.sh` ended with `rm -rf /usr/lib/aarch64-linux-gnu`, which
  is exactly the NVIDIA userspace this box needs. → rule 3, rule 10.

The repair that actually worked (v2 of `RECOVER.sh`): restore the loader and
libc from Arch's own cached package, remove only the files Debian's manifest
names, rebuild `ld.so.cache`, and prove it by running `bash -c 'echo WORKING'`
through the restored loader.

## Known state right now (2026-11-09, after recovery)

- `glibc 2.43+r22+g8362e8ce10b2-2`, loader present as a real file, `ld.so` runs.
- `/usr/lib/aarch64-linux-gnu`: 25 entries, all vendor (NVIDIA/Tegra/weston).
  Debian's libraries are gone from it; the directory is intact.
- `dpkg` still lists `libc6 2.41`, `libgcc-s1`, `gcc-14-base` as `iU`
  (unpacked). Bookkeeping only — the files are gone. **Do not `dpkg --purge`
  them** to "clean up": that runs Debian's maintainer scripts against an Arch
  root. Leave the entries alone or edit the database by hand.
- `dany-deb` (Debian 13, arm64, podman/distrobox) exists and is the only place
  `apt` is allowed to install.
- `apt-guard` is installed but still the buggy version; host apt is not yet
  simulate-only. `~/Work/custom-os/apply-recovery-hardening.sh` applies the
  three layers that make a host-side Debian unpack structurally impossible.

## What "good" means here

- boots to a GPU-rendered desktop, no CPU fallback, no crash loop
- every app I actually use runs natively
- updates that don't break the two things above
- a recovery I can do without a USB stick

## The map

| what | where |
|---|---|
| the OS itself | `/opt/omarchy/omarchy.img`, 512 GB ext4, label `OMARCHY`, mounted at `/` |
| the partition it lives on | `/dev/nvme0n1p1`, 930 GB ext4, label `APP` |
| fix registry, checks, records | `~/Work/custom-os` (`fixes/`, `checks/verify.sh`) |
| kernel guard | `~/jetson-guard` |
| the libc recovery | `~/RECOVER.sh` (v2), `~/RECOVER-INSTRUCTIONS.md`, `~/RECOVERY-README.txt` |
| kernel build + test rig | `~/Work/kernel` (qemu boot test before it ever reaches the boot chain) |
| host-apt lockdown (pending) | `~/Work/custom-os/apply-recovery-hardening.sh` |
| render mode toggle | `omarchy-gpu-mode gpu` / `omarchy-gpu-mode cpu` |
| per-boot GPU report | `/var/log/omarchy-gpu-check.txt` |

## Known non-native, on purpose

`spotify`, `steam`, `1password` and `battlenet` have no aarch64 build in the
configured repos. They are absent, not emulated. If one becomes necessary it
goes in a container or under box64 **isolated**, and it gets written down here.

## Tone

I am not chasing a screenshot. I want a machine I can live in, that behaves
like a real OS should, built by hand and understood end to end.
