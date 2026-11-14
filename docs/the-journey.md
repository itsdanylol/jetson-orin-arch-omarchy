# The journey

One week of building, reconstructed from file timestamps, git history and the
fix records themselves. The dates are real. Where a detail is inference rather
than a recorded fact, it says so.

## Before day one

A Jetson Orin Nano Super developer kit, a 1 TB NVMe drive, and the Ubuntu image
NVIDIA ships on it. Ubuntu works. Ubuntu is also not what this box was bought
for. So an Arch Linux ARM root was built as a 512 GB ext4 image file on the
`APP` partition, with Omarchy on top and Hyprland as the compositor.

The image-file decision is the one that shapes everything after it. The root
becomes portable, snapshot-able, and mountable from the other side of the boot
menu. It also means the boot chain stays outside the system it boots, which is
where the kernel guard and half of these rules came from.

## 2026-11-07: the image exists

`/opt/omarchy` is created, the ext4 image goes in, GRUB gains a second entry.
First boot into Omarchy. The desktop comes up on llvmpipe, not the GPU, because
the NVIDIA userspace sits in `/usr/lib/aarch64-linux-gnu` and nothing has told
the DRM path to use it yet.

Getting from llvmpipe to real DRM modifiers was the first fight, and it was
fought the wrong way first. `AQ_NO_MODIFIERS`, `AQ_TEGRA_LINEAR`,
`LIBGL_ALWAYS_SOFTWARE`: all three are the kind of setting that makes the screen
stop tearing by making the GPU stop working. They are named in `INTENT.md` rule
4 precisely so they do not get tried again. The path that actually works is
`GBM_BACKEND=nvidia-drm`, vendor EGL, real modifiers, `card2`.

Once the GPU was real, `omarchy-gpu-mode gpu` / `omarchy-gpu-mode cpu` became
the toggle, and `/var/log/omarchy-gpu-check.txt` the per-boot report.

## 2026-11-08: the kernel guard

The second fight started the moment the first one was won. A `pacman -Syu` on a
Jetson with a transplanted L4T kernel is a loaded gun: upstream `linux-aarch64`
is a valid kernel package, pacman is happy to install it, and the result boots
into a machine with no tegra display driver. Worse, `mkinitcpio` generates an
initramfs for whatever kernel it thinks is current, so the breakage lands in two
places at once.

`guards/kernel-guard` was written that evening. It does three things:

- holds `linux-aarch64` out of transactions with an `IgnorePkg`,
- snapshots `/boot/Image`, the initramfs and the mkinitcpio preset into
  `/var/backups/jetson-kernel/` before any kernel transaction,
- verifies after: read the version string out of `/boot/Image`, compare to
  `6.8.12-1021-tegra`, restore from the golden copy and rebuild the initramfs if
  it drifted, then re-export the image and initramfs to `/opt/omarchy/boot/`
  because GRUB reads the host-side copies, not the ones inside the image.

Both halves are driven from pacman hooks, and one of those hooks is what caused
the next day's outage.

## 2026-11-09, morning: pacman stops working entirely

Both guard hooks declared `Operation = Downgrade`. libalpm only knows
`Install`, `Upgrade` and `Remove`, so it rejected the hook files. Hook parsing
runs on every transaction, so the two bad files made the package manager
unusable for everything: installs, upgrades, local builds. The hooks had been
written a day earlier and nothing had needed installing since.
[Fix 001](fixes/001-pacman-hook-downgrade.md).

While that was being cleaned up, the group database was also inconsistent
(`gshadow` missing `debug` and `gpio`, so `shadow.service` failed daily), the
network stack had two owners and `systemd-networkd-wait-online` failing on every
boot, and passwordless sudo was not applying because the drop-in sorted before
`10-wheel`. Three small ones, all recorded as
[002](fixes/002-sudoers-passwordless.md),
[003](fixes/003-gshadow-debug-gpio.md),
[004](fixes/004-networkd-wait-online.md).

## 2026-11-09, 15:41: the machine dies

This is the day the repo is really about. `docs/the-libc-day.md` has the full
postmortem. Short version: a host-side `apt-get install` unpacked Debian's
`libc6 2.41` onto the Arch root, and that package's file list ends with
`/usr/lib/ld-linux-aarch64.so.1`, which on Arch is glibc's dynamic loader. Every
new process after that loaded a 2.41 loader against a 2.43 libc and died with
`SIGBUS` before `main`.

Running processes survived. The desktop kept working. Nothing new could start,
including a terminal, including a shell. The disk was fine, the kernel was fine,
the GPU was fine, and the machine was unusable.

It took a reboot into Ubuntu and a hand-written repair script to come back.
The first version of that script would have made things worse: it ended with
`rm -rf /usr/lib/aarch64-linux-gnu`, which is the entire NVIDIA userspace.
[Fix 005](fixes/005-host-apt-never-installs.md) and
`recovery/RECOVER.sh` are the corrected versions.

Two rules came out of that afternoon, and they are the two that get quoted most:

> A guard is untested code until it has blocked something.

> Never delete a shared directory. Delete named files.

## 2026-11-09, evening: the registry

By that evening the pattern was obvious. Each fix had worked, and each one was
one update away from being undone. So the fixes stopped being terminal history
and became files: symptom, cause, artifact, what it survives, how to verify, how
to revert. `checks/verify.sh` grew a case for each, and a user timer started
running it daily.

Five records, twenty-odd assertions, one commit.

## 2026-11-14: the long tail

Everything since has been smaller, and mostly about tools rather than the
system: opencode moved to mise and then needed a shim so its own `update` verb
works, a cloudflared tunnel got pointed at a service bound to `*:8787` with no
auth in front of it and had to be closed back down to loopback, an interrupted
pacman transaction left a lock file that refused every later run, and `xattr`
0.2.3 turned out to reference `libc::ENOATTR`, which does not exist on aarch64
Linux.

There is one fix in there that is not software at all: the board's Super key is
muted by its own keyboard firmware, so the key-table entry was re-encoded in the
keyboard's flash as key usage `0xE3` instead of modifier bit `0x08`. That one
survives everything except a factory reset of the keyboard, which is a strange
sentence to write in a system administration repo and also true.

## What the week taught

Not that Arch is hard. That a hand-built system has a second job after "make it
work": make it stay working when something replaces a file under it. Packages
are not the enemy. Packages that do not know about each other are, and on a
board like this that is nearly all of them.

The registry is the answer. Thirteen records, a check for each, a timer that
runs them every day, and a desktop notification when one comes back. A fix that
only lived in a terminal is not a fix.
