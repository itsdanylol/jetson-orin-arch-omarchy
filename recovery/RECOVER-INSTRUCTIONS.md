# RECOVER-INSTRUCTIONS.md (v2, rewritten 2026-11-09)

Repairs the Arch/Omarchy system on this machine from the Ubuntu side of the
dual boot, after a Debian package overwrote Arch's dynamic loader.

## What broke

A Debian `libc6` package was unpacked onto the Arch root (via `apt`/`dpkg`,
installed at 15:41 today). Debian's file list ends with
`/usr/lib/ld-linux-aarch64.so.1`, which on Arch **is** glibc's dynamic loader.
dpkg replaced it with a symlink into `/usr/lib/aarch64-linux-gnu/`, so every
process started afterwards loaded Debian's 2.41 loader against Arch's 2.43
libc and died with SIGBUS before `main`.

Running processes survived. The kernel, the bootloader, `/home`, pacman's
database and every NVIDIA library were never involved.

## WARNING — the v1 script was dangerous

The first `RECOVER.sh` ended with:

```sh
rm -rf /usr/lib/aarch64-linux-gnu      # DON'T
```

That directory is also where the **NVIDIA/Tegra userspace** lives —
`libcuda.so`, `nvidia/`, `tegra-egl/`, `gbm/`, `gstreamer-1.0/`, `libilm*`.
Deleting it would have taken the GPU stack with the Debian leftovers.
`RECOVER.sh` v2 removes only files dpkg itself lists, and only direct
children of that directory.

## Repair

```sh
sudo mkdir -p /newroot
sudo mount -o loop /opt/omarchy/omarchy.img /newroot     # or losetup + mount
sudo bash /newroot/root/RECOVER.sh /newroot
```

What it does:

1. reads the expected version from `/var/lib/pacman/local/glibc-*`
   (2.43+r22+g8362e8ce10b2-2),
2. takes that exact `glibc` package from the pacman cache, or downloads it
   from `mirror.archlinuxarm.org`,
3. installs `usr/lib/ld-linux-aarch64.so.1` as a **regular file** and
   `usr/lib/libc.so.6`,
4. deletes the Debian `ld.so.conf` fragment and the Debian libraries dpkg
   listed — never the NVIDIA subdirectories,
5. runs `ldconfig` inside the image so the cache maps `libc.so.6` to
   `/usr/lib/libc.so.6`,
6. proves it: loader `--version`, `chroot /newroot /bin/bash -c 'echo WORKING'`,
   cache checks for `libc.so.6` **and** `libnvidia-allocator`.

## Then

```sh
sudo umount /newroot
sudo reboot
```

## Don't do it again

`apt`/`dpkg` write into the same `/usr` as pacman. On Arch that is not
"installing a Debian tool", it is overwriting the base system. Debian things
belong in `distrobox` (already installed) or a container — not on the host.
