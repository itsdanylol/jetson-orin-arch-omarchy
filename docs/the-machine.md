# The machine

A Jetson Orin Nano Super Developer Kit, bought bare, built by hand into a
desktop that gets used every day.

## The parts that matter

```text
SoC        NVIDIA T234, GA10B GPU, 8 GB LPDDR5 shared between CPU and GPU
Board      Jetson Orin Nano Super Developer Kit
Storage    1 TB Samsung 990 EVO, NVMe
Display    one panel, driven by the tegra DRM path, real DRM modifiers
Network    NetworkManager owns it; systemd-networkd-wait-online is disabled
```

The 8 GB is one pool. There is no separate VRAM. That single fact explains most
of the tuning on this box: `zram0` exists because swapping to NVMe on a machine
where the GPU shares the same memory is miserable, and the kernel build rig caps
itself at four to six jobs because linking a kernel at `-j8` will OOM while the
compositor holds a framebuffer.

Measured right now: 7.3 GiB total, 991 pacman packages.

## The layout nobody expects

The root filesystem is not a partition.

```text
nvme0n1p1   930G  ext4  APP      the partition
  └── /opt/omarchy/omarchy.img   ext4 image, loop-mounted
        └── /                    Omarchy, Arch Linux ARM
```

GRUB lives on the host side and boots either this image or the Ubuntu install
next to it. Ubuntu is not a spare operating system. It is the recovery console,
it is the thing that repairs the image, and it has to keep working no matter
what happens to the Arch side. Rule 5 of `INTENT.md` exists because of this:
`/boot`, the ESP, NVRAM and the p1 files are not yours to edit. The image is the
thing that changes.

That arrangement is why the recovery in `recovery/RECOVER.sh` is a script you
run from Ubuntu with the image mounted at `/newroot`, instead of a live USB and
a prayer.

## The software stack, bottom up

**NVIDIA L4T R39.2.1 / JetPack 7.2.1.** The kernel is `6.8.12-1021-tegra`,
built by NVIDIA, out-of-tree, `aarch64`. The board's drivers (tegra display,
tegra EGL, GBM, the CUDA userspace, `libcuda.so`) come from this. There is no
distro package for any of it and no AUR recipe that matches.

**`/usr/lib/aarch64-linux-gnu`, 25 entries.** This directory looks like Debian
and is not. It is where NVIDIA's userspace lands on a Debian-based L4T image,
so it is where the vendor libraries live: `libcuda.so*`, `nvidia/`, `tegra/`,
`tegra-egl/`, `gbm/`, `gstreamer-1.0/`, `libvulkan.so.1`. `rm -rf` on it takes
the GPU with it. This has nearly happened twice.

**Arch Linux ARM.** pacman, 991 packages, glibc `2.43+r22+g8362e8ce10b2-2`.
There is no `apt` and no `dpkg` on the host's `PATH`. Both exist as binaries and
are wrapped by `apt-guard`, because leaving them reachable is how the board died
once already.

**Omarchy 4.5.0 + Hyprland 0.57.1.** Hyprland, the bar, the shell config. The
bar carries a custom module that reports the GPU path and the vendor stack, and
one of the daily checks asserts it still produces valid JSON.

**mise.** Most of the CLI tools (opencode, node, gh) come from mise instead of
pacman, because their pacman packages are either stale on aarch64 or do not
exist. The cost: `tool update` verbs cannot detect a mise install, so a shim
directory sits ahead of mise on `PATH` and routes those verbs to
`mise upgrade`. That whole story is [fix 008](fixes/008-opencode-mise-managed.md)
and [fix 009](fixes/009-mise-update-shims.md).

## What the box is for

From `INTENT.md`, because it is worth repeating outside it:

> Not a demo, not a pile of workarounds propping each other up. Everything runs
> natively on aarch64.

That is the standard. A machine that boots to a GPU-rendered desktop, runs every
app actually used, survives updates without breaking either of those, and can be
recovered without a USB stick. Not a screenshot.
