# handbuilt-jetson

A Jetson Orin Nano Super running Arch, Omarchy and Hyprland on NVIDIA's L4T
kernel, assembled from a bare developer kit by one person with a shell and no
release date. This repo is that machine's memory: every fix it has needed, why
the fix exists, the layer it lives in, and the check that proves it survived
the last update.

It is not a tutorial. It is a field record. If you run the same board and the
same kernel, it will save you the two worst days.

## The machine

```text
Board     Jetson Orin Nano Super Developer Kit, 8 GB unified, T234 / GA10B
Kernel    6.8.12-1021-tegra  (L4T R39.2.1, JetPack 7.2.1), aarch64, out-of-tree
Userland  Omarchy 4.5.0, Arch Linux ARM, pacman, 991 packages
Desktop   Hyprland 0.57.1
Storage   1 TB Samsung 990 EVO, /dev/nvme0n1p1 ext4, label APP
Root      an ext4 image file, loop-mounted at /  (not a partition)
glibc     2.43+r22+g8362e8ce10b2-2
GPU libs  /usr/lib/aarch64-linux-gnu, 25 vendor entries owned by the L4T image
```

Two things about that table decide everything else in this repo. The kernel is
NVIDIA's, not Arch's. And the root is a filesystem image sitting on a
partition, which means the system underneath it (Ubuntu, in the GRUB menu) is
not a spare install. It is the way back in.

## Why this repo exists

Almost nothing in the Arch ecosystem fits this board. A stock `pacman -Syu`
will offer to replace the L4T kernel with mainline `linux-aarch64`, which boots
and then has no tegra drivers. Half the AUR is written for x86 laptops. Prebuilt
Python wheels assume `x86_64`. Anything reaching into `/lib/modules/$(uname -r)`
wants kernel headers that only exist inside the NVIDIA tarball. And the GPU
stack lives outside pacman's database entirely, so pacman happily offers
`nvidia-utils` to satisfy `vulkan-driver` and overwrites NVIDIA's own files if
you let it.

Every one of those is the platform talking, not the software. But it means the
box needs a second kind of software: not packages, guards. That is what ended up
in here.

## The rule

A fix is not done when it works. It is done when it is **durable**, **recorded**
and **checked**.

**Durable** means it sits in a layer an update cannot casually rewrite: a pacman
hook, a sudoers drop-in, a systemd override, an `IgnorePkg` / `NoExtract` entry,
a local package, or `/usr/local`. Never a hand edit to a file some package owns,
because `pacman -Syu` ends those.

**Recorded** means `fixes/NNN-name.md`, same shape every time. Symptom, cause,
the artifact pasted whole, what it survives, how to verify, how to revert.

**Checked** means a case in `checks/verify.sh`. A fix that no update has ever
tested is a guess with good formatting.

The daily timer runs those checks so a reverted fix fails loudly instead of
quietly turning the machine back into the thing that broke it.

## Layout

```text
INTENT.md         what this machine is for, and the ten rules it runs on
docs/             the machine, the journey, the libc day, the kernel, the method
fixes/            one record per fix, plus INDEX.md and 000-template.md
checks/verify.sh  every fix, asserted; exit 1 when one was reverted
checks/native-audit.sh   does anything on this box execute as x86?
kernel/           the L4T kernel build and QEMU boot-test rig
guards/           jetson-kernel-guard, which keeps the L4T kernel installed
recovery/         RECOVER.sh, the repair that brought the box back from SIGBUS
packages/         jetson-vendor-stack, so pacman knows the GPU is already here
apply-recovery-hardening.sh   makes a host-side Debian unpack impossible
```

Read `INTENT.md` first if you want to understand the decisions. Read
`docs/the-libc-day.md` if you only have five minutes and want to know what not
to do.

## If your Jetson is already broken

The four failures that actually take this board down, in the order they tend to
happen:

1. **`pacman` refuses every transaction.** A bad hook file. Hooks are parsed for
   every transaction whether or not they are involved, so one invalid
   `Operation` value blocks installs, upgrades and local builds alike. See
   [fix 001](fixes/001-pacman-hook-downgrade.md).
2. **Nothing starts, but the desktop still works.** `SIGBUS` on every new
   process, shell included. Something unpacked a non-Arch `libc` over the
   dynamic loader. See [fix 005](fixes/005-host-apt-never-installs.md) and
   `docs/the-libc-day.md`. Do not `rm -rf /usr/lib/aarch64-linux-gnu`, ever.
3. **A kernel update removed the tegra drivers.** Mainline replaced the L4T
   kernel. `guards/` exists so that cannot happen.
4. **`vulkan-driver` is unfulfilled and pacman wants `nvidia-utils`.** Do not
   install it. `packages/jetson-vendor-stack` claims only what is true.

## What does not work here, on purpose

`spotify`, `steam`, `1password` and `battlenet` have no aarch64 build in the
configured repos. They are absent, not emulated. `nvidia-smi` is not on this
board, because the L4T userspace does not ship it and installing the desktop
driver to get it would break the GPU stack. CUDA is not installed either: the
toolkit is a choice you make per project, and there is no `nvcc` on this image
right now.

Nothing on this host runs under box64 or FEX. `checks/native-audit.sh` enforces
that, and it is one of the checks that runs daily.

## Running the checks yourself

```sh
checks/verify.sh                          # now, with output
systemctl --user status custom-os-verify.timer    # the daily job
tail -20 ~/.local/state/custom-os/verify.log      # history
```

Most checks are written against absolute paths on this particular machine
(`/home/dany/...`, `/opt/omarchy/...`). They are the registry for one box, not a
portable test suite. Lift what applies to you and change the paths.

## Adding a fix

1. Diagnose the layer: platform, tooling, ownership, or an upstream bug.
2. Apply it in the durable layer, not in the running file.
3. `cp fixes/000-template.md fixes/NNN-name.md`, fill it in, paste the artifact
   whole.
4. Add the check to `checks/verify.sh` and the row to `fixes/INDEX.md`.
5. Run `checks/verify.sh` and paste the output before calling it fixed.

A fix without a row and a check is not a fix. It is a thing you did once.

## License

MIT. Take it, break it, improve it. If you hit a failure this board has not
recorded yet, that is worth an issue.
