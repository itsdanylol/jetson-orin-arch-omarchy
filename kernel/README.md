# The kernel rig

Build `6.8.12-1021-tegra` yourself, test it where it cannot hurt anything,
install it beside the stock kernel, keep a rollback one command away.

Run the scripts in numeric order from this directory.

## 00-fetch.sh

Put the L4T kernel source in `src/`. NVIDIA ships it as a tarball per Jetson
Linux release. There is no distro package and no AUR recipe that matches, and
this script does not invent a URL.

```sh
SRC=/path/to/linux-tegra-R39.2.1.tar.gz ./00-fetch.sh
SRC_URL=https://host/file.tar.gz ./00-fetch.sh
```

About 1 GB compressed, roughly 4 GB unpacked, another 8 GB to build. It reads
`Makefile` and warns if the source line is not 6.8, because a different line
will not load the tegra modules this board needs.

## 10-config.sh

Seeds `src/.config` from `/proc/config.gz` of the kernel that is running right
now. That is the whole safety argument: everything that works today stays
enabled. Changes go in `config.dany`, one `CONFIG_X=y` per line, so the intent is
reviewable in git instead of buried in a 9000-line diff.

Outputs `dany_defconfig` and `out/config.diff` against the running kernel.

## 20-build.sh

```sh
JOBS=4 ./20-build.sh
```

`LOCALVERSION=-dany` keeps this kernel's module directory separate from the
stock one, so both can live on the machine at once and a rollback is pointing at
the other directory. Expect 40 to 90 minutes on this board. Do not raise the job
count: 8 GB is shared with the GPU, and linking a kernel at `-j8` will OOM.

## 30-stage.sh

`modules_install` into `out/root`, then an initramfs built there with
`mkinitcpio -r`. The running system is not touched at any point in this script.

## 40-qemu-test.sh

```sh
./40-qemu-test.sh out/Image-dany out/initramfs-linux-dany.img 90
```

Boots the candidate on `qemu-system-aarch64 -M virt -cpu cortex-a72`. There is
no tegra hardware on `virt`, so init will fail to find a real root. Expected. The
PASS condition is narrower: the kernel banner printed **and** control reached
userspace. That proves the image is executable, the decompressor works, the arch
code runs, and modules load.

On PASS it writes `out/qemu-result.txt` containing `PASS`, the sha256 of the
image, and the sha256 of the initramfs. `50-install.sh` will not accept a verdict
that belongs to different bytes.

## 50-install.sh

Installs `Image-dany`, `initramfs-linux-dany.img` and the `-dany` module
directory. Creates no entry, edits no bootloader, touches no stock file. It
refuses unless:

1. all three files exist,
2. `qemu-result.txt` says PASS and its image hash matches what is being installed,
3. you have read `out/config.diff` and run `touch out/config-reviewed`.

Then it prints the GRUB entry to add and the `grub-reboot` command for a
one-shot boot. A one-shot boot means a broken kernel falls back to the stock
entry by itself.

## 90-rollback.sh

Removes the `-dany` files and the `-dany` module directory. The stock kernel and
its boot entry are exactly as they were.

## Why the bootloader is manual

The boot chain lives on `/dev/nvme0n1p1`, outside the loop-mounted root. Rule 5
of `INTENT.md` says that is not something a script edits. The rig prints the
entry; a human pastes it.
