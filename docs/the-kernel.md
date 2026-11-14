# The kernel

`6.8.12-1021-tegra`, out-of-tree, built by NVIDIA for the T234. This one file
(`/boot/Image`) is the difference between a working desktop and a board with no
display, which is why it has a guard, a snapshot, a build rig and three checks.

## Why nothing fits

The kernel is not Arch's. That single fact cascades:

- **No `linux-aarch64`.** Upstream Arch ARM's kernel will install, boot, and
  have no tegra display, no tegra EGL, no `nvgpu`. It is a valid kernel package
  and it is the wrong kernel.
- **No kernel headers from a package.** Anything that compiles a module needs
  `/usr/src/linux-headers-6.8.12-1021-tegra-*`, which only exists if you build
  it. So every out-of-tree module is a source build or nothing.
- **`uname -r` is a trap.** `6.8.12-1021-tegra` is not a version any AUR recipe
  knows. AUR helpers that check `uname -r` against a package version will
  conclude the system is on a mainline kernel and offer to "fix" it.
- **`Ignores` belong in `[options]`.** A `IgnorePkg` line placed inside a repo
  section is silently ignored, and pacman says so on every run: `directive
  'IgnorePkg' in section 'omarchy' not recognized`.
- **The GPU userspace is outside pacman.** Nothing owns `libcuda.so.1`, so
  pacman's dependency resolver believes `vulkan-driver` is unfulfilled and
  offers `nvidia-utils`, the desktop driver package, which will overwrite
  NVIDIA's files in `/usr/bin/nvidia-*`,
  `/usr/lib/xorg/modules/drivers/nvidia_drv.so` and
  `/usr/share/glvnd/egl_vendor.d/10_nvidia.json`.

## The guard

`guards/kernel-guard/jetson-kernel-guard` plus `install.sh`. Installed at
`/usr/local/bin/`, driven by two pacman hooks.

Layer one, holding the line before anything runs: `IgnorePkg = linux-aarch64`
in `/etc/pacman.conf`, so pacman never offers the mainline kernel in the first
place.

Layer two, `--snapshot`: called by `94-jetson-kernel-snapshot.hook` on any
`Install` or `Upgrade` of a kernel package. Copies `/boot/Image`,
`/boot/initramfs-linux.img` and `/etc/mkinitcpio.d/linux-aarch64.preset` into
`/var/backups/jetson-kernel/<timestamp>/`, keeping the five most recent and
never touching the `golden/` reference copy.

Layer three, `--verify`: called by `95-jetson-kernel-guard.hook` afterwards, and
by `checks/verify.sh` daily.

1. Read the version out of `/boot/Image` with `strings`. If it is not
   `6.8.12-1021-tegra`, restore `golden/Image` over it.
2. Re-pin `ALL_kver` in the mkinitcpio preset if something rewrote it.
3. Rebuild initramfs if either changed.
4. `lsinitcpio` the initramfs and confirm it carries this kernel's modules. An
   initramfs built for the wrong kernel is the failure mode that survives a good
   kernel.
5. Re-export `Image` and `initramfs-linux.img` to `/opt/omarchy/boot/`, because
   GRUB reads the host-side copies, not the ones inside the loop-mounted root.

The detail that bit this repo: the hooks first declared `Operation = Downgrade`,
which libalpm does not accept, and since hooks are parsed for every transaction,
two bad files took out package management entirely. See [fix 001](../fixes/001-pacman-hook-downgrade.md).

## Building your own

`kernel/` is the rig, staged so a bad kernel never reaches the boot chain. It is
written to be read in order.

```text
00-fetch.sh       put the L4T source in src/ (you supply the tarball, it does
                  not invent a URL)
10-config.sh      seed .config from /proc/config.gz of the running kernel, apply
                  config.dany as the only delta, emit dany_defconfig
20-build.sh       Image + modules with LOCALVERSION=-dany, cap the job count
30-stage.sh       modules_install into out/root, build an initramfs there
40-qemu-test.sh   boot the candidate under qemu-system-aarch64, prove it reaches
                  userspace, write out/qemu-result.txt with the sha256 it tested
50-install.sh     install only new -dany files; refuses without a matching
                  qemu PASS, a config diff you have read, and a hash match
90-rollback.sh    delete the -dany files. Stock kernel never touched
```

The reason for `LOCALVERSION=-dany` is that a module directory is keyed by
`uname -r`. Two kernels with different `LOCALVERSION` values can live on the
same machine at the same time, so a failed experiment is a boot-menu choice and
a rollback is `rm` on new files. Nothing is overwritten.

The reason for the QEMU step is that this board gets one shot at a boot. The
candidate image is booted on `-M virt -cpu cortex-a72`, which has no tegra
hardware, so init will fail to find a real root. That is expected. What is being
proven is narrower and still worth proving: the image is executable, the
decompressor works, the arch code runs, modules load, and control reaches
userspace instead of panicking.

`50-install.sh` refuses three ways, and the hash check is the one that matters:

```sh
[ "$(sed -n 1p out/qemu-result.txt)" = "PASS" ] || refuse
[ "$(sed -n 2p out/qemu-result.txt)" = "$(sha256sum out/Image-dany | cut -d' ' -f1)" ] || refuse
[ out/config-reviewed -nt out/config.diff ] || refuse
```

A PASS that belongs to a different image than the one being installed is not a
PASS. Binding the verdict to the bytes is the difference between a gate and a
gesture.

The rig deliberately does not edit the bootloader. It prints the GRUB entry to
add and the `grub-reboot` one-shot command, because the boot chain lives on
`/dev/nvme0n1p1` and rule 5 says that is not something a script gets to edit.
A one-shot boot means a bad kernel falls back to the stock entry by itself,
which is the only reason this is a safe procedure at all.

## What the board still cannot do

No `nvidia-smi`. It ships with the desktop driver package, and installing that
package to obtain it would overwrite the vendor files the display depends on. On
Jetson the supported route is `tegrastats` and the sysfs nodes, not the desktop
tool.

No `nvcc`. CUDA is not installed on this image. The toolkit is a per-project
decision and it should not be baked into a desktop image that mostly runs a
compositor.
