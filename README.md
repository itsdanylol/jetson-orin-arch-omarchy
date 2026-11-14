# handbuilt-jetson

A Jetson Orin Nano Super running Arch, Omarchy and Hyprland on NVIDIA's L4T
kernel. Built from a bare developer kit by one person with a shell, no release
date, and a stock package manager that is actively trying to uninstall the
display driver.

This repo is the machine's memory: every fix it has needed, why the fix exists,
the layer it lives in, and the check that proves it survived the last update.

## The week

```text
  NOV 07   the image exists      512 GB ext4 file on nvme0n1p1, first boot.
                                 Compositor up. GPU idle. llvmpipe drawing
                                 every frame at single-digit fps.

  NOV 08   the GPU path won      GBM_BACKEND=nvidia-drm, vendor EGL, real DRM
                                 modifiers, card2. Then the kernel guard,
                                 because one -Syu can replace the L4T kernel
                                 with mainline and delete the display.

  NOV 09   pacman dies           Two guard hooks said Operation = Downgrade.
                                 libalpm rejects the file, and hooks are parsed
                                 for every transaction, so the package manager
                                 stops working entirely.

  NOV 09   15:41   SIGBUS        apt unpacked Debian libc6 over Arch's dynamic
                                 loader. Every new process dies before main.
                                 The desktop keeps running. Nothing reports it.

  NOV 09   19:40   back          Repaired from Ubuntu with the image mounted.
                                 The fix registry is born the same night.

  NOV 14   thirteen fixes        34 assertions, all green, run daily.
                                 The box has not lost a boot since.
```

One week between "it boots" and "it stays booted". The middle entry is the one
worth reading: [docs/the-libc-day.md](docs/the-libc-day.md).

Every failure, in order, including the self-inflicted ones and the one still
open: [docs/trouble.md](docs/trouble.md). Twenty-three entries, no omissions.

## The driver situation

This is the reason the repo exists, and it is strange enough to deserve the
whole explanation.

On a normal Linux machine, the GPU is boring. pacman installs `mesa` and the
right Vulkan driver, the kernel has a DRM driver built in, you get
`/dev/dri/card0`, and everything talks to it. If something is wrong, the
compositor refuses to start and tells you why.

On this board, none of that is true.

**The kernel is not the distro's.** It is `6.8.12-1021-tegra`, built by NVIDIA,
out-of-tree, shipped as a 1 GB tarball per JetPack release. There is no package
for it, no AUR recipe that matches it, and no headers unless you build them
yourself.

**There are two DRM cards, and only one of them can draw the desktop.**

```text
card1   driver drm         nvidia,tegra234-host1x    host1x / syncpoints
card2   driver nv_platform nvidia,tegra234-display   the display controller
```

The compositor has to be pointed at the right one by hand:

```sh
AQ_DRM_DEVICES=/dev/dri/card2
```

Point it at `card1` and you get a black screen that is "working". There is no
error message, because nothing failed. The wrong device was told to scan out.

**EGL has two vendors installed and one of them is a trap.**

```text
/usr/share/glvnd/egl_vendor.d/10_nvidia.json   libEGL_nvidia.so.0
/usr/share/glvnd/egl_vendor.d/50_mesa.json     libEGL_mesa.so.0
```

If Mesa wins the vendor selection, your desktop still renders, on llvmpipe, in
software, at unusable frame rates. Nothing crashes. No log line says "you are on
the CPU". You find out by benchmarking a window drag. This is the same failure
class as `AQ_NO_MODIFIERS=1`, `AQ_TEGRA_LINEAR=1` and `LIBGL_ALWAYS_SOFTWARE=1`:
each one makes a symptom disappear by making the GPU stop being used. All three
are named in `INTENT.md` rule 4 so they never get tried again.

**Buffer sharing goes through NVIDIA's allocator, not Mesa's.** The
`GBM_BACKEND=nvidia-drm` path lands in `libnvidia-allocator.so`, which speaks
real DRM modifiers. Strip the modifiers and the scanout path either tears or
refuses the buffer.

**Vulkan is NVIDIA's ICD, at a version no distro package knows about.**

```json
{ "ICD": { "library_path": "libGLX_nvidia.so.0", "api_version": "1.4.329" } }
```

**And none of that userspace belongs to pacman.** It sits in
`/usr/lib/aarch64-linux-gnu`, a directory that looks Debian and is not: 25
entries, `libcuda.so*`, `nvidia/`, `tegra/`, `tegra-egl/`, `gbm/`, `weston/`,
`gstreamer-1.0/`, `libvulkan.so.1.4.321`, `libilm*`, `libnvcu*`. Nothing owns
those files. So pacman's dependency resolver concludes `vulkan-driver` is
unfulfilled, offers `nvidia-utils`, the desktop driver package, and if you
accept it, it overwrites `/usr/bin/nvidia-*`,
`/usr/lib/xorg/modules/drivers/nvidia_drv.so` and
`/usr/share/glvnd/egl_vendor.d/10_nvidia.json`, and the display dies. The fix for
that is `packages/jetson-vendor-stack`, which claims the virtuals without
installing a single executable.

**There is no `nvidia-smi`.** It ships inside the desktop driver package you are
not allowed to install.

**And the whole GPU stack is one `rm -rf` away from gone.** That is not a
metaphor. The first recovery script this machine ever ran ended with
`rm -rf /usr/lib/aarch64-linux-gnu`, which would have deleted the vendor stack
and turned a broken afternoon into a reinstall. Rule 3 exists because of it.

Proof, from this box right now:

```console
$ glxinfo -B | grep -E 'renderer|OpenGL version'
OpenGL renderer string: NVIDIA Tegra Orin (nvgpu)/integrated
OpenGL version string: 4.6.0 NVIDIA 595.78

$ vulkaninfo --summary | grep -E 'deviceName|apiVersion'
apiVersion  = 1.4.329
deviceName  = NVIDIA Tegra Orin (nvgpu)
```

That is a 60 W board running a full OpenGL 4.6 and Vulkan 1.4 stack on a kernel
apt, pacman and the AUR all believe does not exist.

The whole chain, link by link, with what breaks at each one:
[docs/the-display-path.md](docs/the-display-path.md).

## The machine

```text
Board     Jetson Orin Nano Super Developer Kit, 8 GB unified, T234 / GA10B
Kernel    6.8.12-1021-tegra  (L4T R39.2.1, JetPack 7.2.1), aarch64, out-of-tree
GPU       nvgpu 595.78, OpenGL 4.6, Vulkan 1.4.329, no nvidia-smi
Userland  Omarchy 4.5.0, Arch Linux ARM, pacman, 991 packages
Desktop   Hyprland 0.57.1 (aquamarine, wlroots), scanout on /dev/dri/card2
Storage   1 TB Samsung 990 EVO, /dev/nvme0n1p1 ext4, label APP
Root      an ext4 image file, loop-mounted at /  (not a partition)
glibc     2.43+r22+g8362e8ce10b2-2
```

The root is an image file on a partition, with GRUB on the host side choosing
between it and the Ubuntu install next to it. Ubuntu is not a spare OS. Ubuntu is
the recovery console, and one day it was the only thing on the machine that
could start a program.

## Why this is the hard version of Linux

| what | a normal desktop | this board |
| --- | --- | --- |
| kernel | from the distro, 50 MB package | NVIDIA tarball, 1 GB, built by hand |
| GPU driver | `mesa`, one package | `nvgpu` module + vendor EGL + vendor allocator, outside pacman |
| display | `/dev/dri/card0` | `card2`, and the compositor must be told |
| Vulkan | `vulkan-radeon` / `vulkan-intel` | `libGLX_nvidia.so.0`, api 1.4.329, unowned |
| `nvidia-smi` | present | does not exist, cannot be installed |
| updates | safe by default | pacman will offer to replace the kernel and the driver |
| recovery | live USB | Ubuntu on the other side of the boot menu |
| root | a partition | a 512 GB file inside a partition |

Nothing above is a complaint. It is the spec. Every fix in this repo exists
because one of those rows is a place where a normal assumption stops being true.

## The rule

A fix is not done when it works. It is done when it is **durable**, **recorded**
and **checked**.

**Durable** means it sits in a layer an update cannot casually rewrite: a pacman
hook, a sudoers drop-in, a systemd override, an `IgnorePkg` / `NoExtract` entry,
a local package, or `/usr/local`. Never a hand edit to a file some package owns,
because `pacman -Syu` ends those.

**Recorded** means `fixes/NNN-name.md`, same shape every time. Symptom, cause,
the artifact pasted whole, what it survives, how to verify, how to revert.

**Checked** means a case in `checks/verify.sh`. A fix no update has ever tested
is a guess with good formatting.

A timer runs those checks daily, so a reverted fix fails loudly instead of
quietly turning the board back into the thing that broke it.

## Layout

```text
INTENT.md         what this machine is for, and the ten rules it runs on
docs/             the machine, the journey, the trouble log, the libc day, the
                  display path, the kernel, the rules, the method
fixes/            one record per fix, plus INDEX.md and 000-template.md
checks/verify.sh  every fix, asserted; exit 1 when one was reverted
checks/native-audit.sh   does anything on this box execute as x86?
kernel/           the L4T kernel build and QEMU boot-test rig
guards/           jetson-kernel-guard, which keeps the L4T kernel installed
recovery/         RECOVER.sh, the repair that brought the box back from SIGBUS
packages/         jetson-vendor-stack, so pacman knows the GPU is already here
apply-recovery-hardening.sh   makes a host-side Debian unpack impossible
```

Start with `INTENT.md`. If you only have five minutes, read
[docs/the-libc-day.md](docs/the-libc-day.md).

## If your Jetson is already broken

The four failures that actually take this board down, in the order they tend to
happen:

1. **`pacman` refuses every transaction.** A bad hook file. Hooks parse for every
   transaction whether or not they are involved, so one invalid `Operation`
   value blocks installs, upgrades and local builds alike. See
   [fix 001](fixes/001-pacman-hook-downgrade.md).
2. **Nothing starts, but the desktop still works.** `SIGBUS` on every new
   process, shell included. Something unpacked a non-Arch `libc` over the
   dynamic loader. See [fix 005](fixes/005-host-apt-never-installs.md). Do not
   `rm -rf /usr/lib/aarch64-linux-gnu`, ever.
3. **A kernel update removed the tegra drivers.** Mainline replaced the L4T
   kernel. `guards/` exists so that cannot happen.
4. **`vulkan-driver` is unfulfilled and pacman wants `nvidia-utils`.** Do not
   install it. `packages/jetson-vendor-stack` claims only what is true.

## What does not work here, on purpose

`spotify`, `steam`, `1password` and `battlenet` have no aarch64 build in the
configured repos. They are absent, not emulated. `nvidia-smi` is not on this
board and installing the package that provides it breaks the display. CUDA is not
installed: the toolkit is a per-project decision and there is no `nvcc` on this
image.

Nothing on this host runs under box64 or FEX. `checks/native-audit.sh` enforces
it, and it runs daily.

## Running the checks

```sh
checks/verify.sh                                  # now, with output
systemctl --user status custom-os-verify.timer    # the daily job
tail -20 ~/.local/state/custom-os/verify.log      # history
```

Most checks use absolute paths on this particular machine (`/home/dany/...`,
`/opt/omarchy/...`). It is a registry for one box, not a portable test suite.
Lift what applies and change the paths.

## Adding a fix

1. Diagnose the layer: platform, tooling, ownership, or an upstream bug.
2. Apply it in the durable layer, not in the running file.
3. `cp fixes/000-template.md fixes/NNN-name.md`, fill it in, paste the artifact
   whole.
4. Add the check to `checks/verify.sh` and the row to `fixes/INDEX.md`.
5. Run `checks/verify.sh` and paste the output before calling it fixed.

A fix without a row and a check is not a fix. It is a thing you did once.

## Related

- **fancy-dual-boot**, the boot picker that came out of this machine's GRUB
  setup: one command to switch the default entry, backed up and validated.
  https://github.com/itsdanylol/fancy-dual-boot

## License

GNU General Public License v3.0 or later. Take it, break it, improve it, ship it
under the same terms. If you hit a failure this board has not recorded yet, that
is worth an issue.
