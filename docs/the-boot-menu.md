# The boot menu

GRUB is not installed by a distro on this machine. It is a hand-written
`grub.cfg` on the ESP that knows about two systems, one of which boots out of a
filesystem image. That file is the reason the machine can be recovered at all,
so it is written down here line by line.

The tool that switches the default entry is a separate project,
[fancy-dual-boot](https://github.com/itsdanylol/fancy-dual-boot). This page is
the config it manages.

## The layout

```text
/dev/nvme0n1p10   64M    vfat    EFI      the ESP, not mounted in the running system
/dev/nvme0n1p1    930G   ext4    APP      the outer filesystem
  /opt/omarchy/omarchy.img  512G  ext4     the actual root, loop-mounted at /
  /opt/omarchy/boot/         Image, initramfs-linux.img, tegra.dtb
```

Ubuntu is installed the vendor-supported way and is the recovery system.
NVIDIA's `L4tLauncher.efi` owns its boot path and reads `extlinux.conf` off the
boot partition, so Ubuntu's kernel arguments are not GRUB's business.

Omarchy boots from an image file, so GRUB has to read a kernel out of the outer
filesystem and tell it how to find the image.

## The file, annotated

Lives at `/boot/efi/EFI/grub/grub.cfg`. `EFI/grub/grub.cfg` is the case-insensitive
path to the same thing.

```text
set default=1
set timeout=5
set timeout_style=menu

set omarchy_uuid=<uuid of nvme0n1p1>
```

`default=1` is Omarchy. Five seconds is short on purpose: this board gets used as
a desktop, and five seconds is enough to catch with an arrow key on the way past.

The UUID identifies the outer filesystem so GRUB can read the kernel and
initramfs. It also reaches the kernel inside `omarchy.loop=`, and it is used for
nothing else. `blkid -s UUID -o value /dev/nvme0n1p1` must match it.

```text
menuentry "Ubuntu" --class ubuntu {
    chainloader /EFI/BOOT/BOOTAA64.efi
}
```

Hand off to NVIDIA's launcher, add no arguments, change nothing about how Ubuntu
boots. The vendor owns that path and GRUB only needs a menu line for it.

```text
menuentry "Omarchy" --class arch {
    if search --no-floppy --fs-uuid --set=omarchy_root "$omarchy_uuid"; then
        linux ($omarchy_root)/opt/omarchy/boot/Image \
            omarchy.loop=UUID=$omarchy_uuid:/opt/omarchy/omarchy.img \
            rw rootwait rootfstype=ext4 mminit_loglevel=4 \
            console=ttyTCU0,115200 console=tty0 firmware_class.path=/etc/firmware \
            fbcon=map:0 video=efifb:off efi=runtime pci=pcie_bus_perf \
            nvme.use_threaded_interrupts=1 quiet loglevel=3
        initrd ($omarchy_root)/opt/omarchy/boot/initramfs-linux.img
        devicetree ($omarchy_root)/opt/omarchy/boot/tegra.dtb
    else
        echo "omarchy: cannot resolve UUID $omarchy_uuid"
    fi
}
```

Four things in there are load-bearing:

**No `root=`.** The initramfs hook mounts the root itself. Passing `root=` makes
the initramfs try to mount the same filesystem first, and potentially fsck a
930 GB ext4 that is currently in use. The hook resolves the outer filesystem,
the image and the inner root on its own.

**A private variable.** `omarchy_root` instead of `$root`, so a failed Omarchy
boot cannot leave the Ubuntu entry pointing at the wrong filesystem.

**`devicetree`.** The board needs the tegra DTB and it is not inside the image's
`/boot`.

**`video=efifb:off`** plus the console arguments, because the firmware
framebuffer fights the tegra display driver.

The whole body sits inside an `if`, so the failure mode is a printed message
instead of a kernel panic with a UUID in it.

```text
submenu "Advanced options" {
    menuentry "Omarchy (rescue shell)" --class arch {
        ... the same linux line, plus omarchy.break=1 ...
    }
}
```

Same kernel, same initramfs, same DTB, and it stops in the initramfs busybox
shell before `switch_root`. That is enough to inspect or repair the image from
inside the machine, with no USB stick and no second computer. It lives in a
submenu so the timeout cannot land on it by accident, and it is addressed as
`2>0` in GRUB's numbering.

```text
if loadfont $prefix/fonts/unicode.pf2; then
    set gfxmode=auto
    terminal_output gfxterm
    set theme=$prefix/theme/theme.txt
    export theme
fi
```

Theme last, and behind the font check. Missing font means the plain text menu
and a machine that still boots. A theme is never allowed to be load-bearing.

## The ESP is outside the system

Two consequences that cost hours:

1. **GRUB reads the host-side copies.** It loads
   `/opt/omarchy/boot/Image` from the outer filesystem, not `/boot/Image` inside
   the loop-mounted image. So the kernel guard has to re-export both files after
   any kernel change. Install a kernel and skip the export, and you have
   installed a kernel that boots nothing.
2. **Nothing mounts the ESP for you.** Changing the default entry means
   mounting a FAT32 partition first, which means root, which means a script that
   finds the partition by fstype. That script is now
   [fancy-dual-boot](https://github.com/itsdanylol/fancy-dual-boot), with a
   backup and `grub-script-check` in front of the write.

## Swapping the default

```sh
sudo bootpick list
sudo bootpick set omarchy
sudo bootpick --dry-run set '2>0'
```

And for testing a kernel without risking a boot, the one-shot:

```sh
sudo grub-reboot 'Omarchy'
sudo reboot
```

A failed boot falls back to the entry that works, with nobody at the keyboard.
