# The libc day

2026-11-09. Every new process on the machine started dying with `SIGBUS` before
it reached `main`, the desktop kept running, and the cause was a package that
looked like it had installed cleanly. This is the full postmortem, because the
same shape of failure will happen on any system where two package managers share
one `/usr`.

## What happened

At 15:41 a host-side `apt-get install` ran on the Arch root. `apt` and `dpkg`
exist on this machine only because the L4T userspace is Debian-laid-out, and
they write into the same `/usr` as pacman.

The transaction pulled in Debian's `libc6 2.41`. Its file list ends with:

```text
/usr/lib/ld-linux-aarch64.so.1
```

On Arch, that path **is** glibc's dynamic loader. Arch's glibc was
`2.43+r22+g8362e8ce10b2-2`. `dpkg` did what `dpkg` does when it owns a path: it
replaced the file. The replacement was a symlink into
`/usr/lib/aarch64-linux-gnu/`, pointing at Debian's 2.41 loader.

From that second on, every `execve()` started a program by handing control to a
2.41 loader that would resolve symbols against Arch's 2.43 `libc.so.6`. The
mismatch faults during loader startup, before `main`, which is why the error was
`SIGBUS` and not a symbol lookup message.

## Why it looked like nothing was wrong

Running processes never load anything again. The compositor, the terminal
emulator, the shell that had been open since before the install: all of them
kept running because their loaders were already in memory and their libraries
already mapped. The desktop was smooth. Windows moved.

Anything new died. A new terminal window, `ls`, `sudo`, `pacman`, a shell
spawned by a systemd unit. And because the thing that reports errors is itself a
program that has to start, the machine could not even tell you what was wrong.

Cold file reads were fine. The NVMe was healthy, the filesystem was clean, the
kernel was untouched, `/home` was intact, pacman's database was intact. Nothing
was lost. Everything was just unable to start.

## What made it worse than it had to be

Two things, both human.

**The safety net had never been tested.** `apt-guard` was supposed to compare a
package's file list against pacman's file database and refuse collisions. It
compared `./usr/bin/foo` from the Debian manifest against `usr/bin/foo` from
pacman and never stripped the leading `./`, so every comparison missed and every
package was approved. It had been "installed and working" for days without ever
being pointed at a real collision. That is now rule 9:

> A guard is untested code until it has blocked something. Test it against a
> real case before the destructive operation runs behind it.

**The first repair script was more dangerous than the incident.** `RECOVER.sh`
v1 ended with:

```sh
rm -rf /usr/lib/aarch64-linux-gnu      # never do this
```

That directory is not Debian's. It is the shared vendor directory holding the
whole NVIDIA userspace: `libcuda.so*`, `nvidia/`, `tegra/`, `tegra-egl/`,
`gbm/`, `gstreamer-1.0/`, `libvulkan.so.1`, `libilm*`, `libnvcu*`. Deleting it
removes the GPU stack from a board whose only display path is the GPU stack.
Recovery would have turned one broken afternoon into a reinstall. That is now
rules 3 and 10:

> Never delete a shared directory. Delete named files.

> Before `rm`, `dd`, `--overwrite`, or any loop over a manifest: say out loud
> what the path contains and what the glob matches.

## The repair that worked

`recovery/RECOVER.sh` v2, run from Ubuntu with the image mounted at `/newroot`.
It never touches the running system, and it treats pacman's database as the
source of truth.

1. Read the expected version from `/var/lib/pacman/local/glibc-*`. Not from
   memory, not from a guess: `2.43+r22+g8362e8ce10b2-2`.
2. Get that exact package from the pacman cache, or from
   `mirror.archlinuxarm.org` if the cache is cold.
3. Install `usr/lib/ld-linux-aarch64.so.1` as a **regular file** and
   `usr/lib/libc.so.6` from it. The Debian loader was left behind as a symlink;
   a loader has to be a real file.
4. Remove only the files Debian's own manifests name, and only direct children
   of `/usr/lib/aarch64-linux-gnu`. Anything in a subdirectory (`nvidia/`,
   `tegra-egl/`, `gconv/`) is skipped without discussion.
5. `chroot /newroot ldconfig` so the cache maps `libc.so.6` to
   `/usr/lib/libc.so.6`.
6. Prove it, in this order: the loader prints a `GNU libc` version, then
   `chroot /newroot /bin/bash -c 'echo WORKING'` returns `WORKING`, then
   `ldconfig -p` maps `libc.so.6` correctly **and** still resolves
   `libnvidia-allocator`.

That last check is the important one. A repair that brings back the shell and
takes the GPU is not a repair.

## The aftermath

`dpkg` still lists `libc6 2.41`, `libgcc-s1` and `gcc-14-base` as `iU`
(half-installed) because their files are gone but their database entries are
not. Do not `dpkg --purge` them to tidy up: that runs Debian maintainer scripts
against an Arch root and can do the same thing again. Leave the entries alone or
edit the database by hand.

`apply-recovery-hardening.sh` closes the hole structurally, in three layers:

```text
1. apt may only simulate      /etc/apt/apt.conf.d/99-arch-guard
2. dpkg refuses to run        /usr/local/bin/dpkg-refuse, pre-invoke hook
3. apt-guard's path bug fixed /usr/local/bin/apt-guard
```

Real Debian work now happens in a distrobox container, which has its own root
and cannot reach the host's `/usr`. That container is the only place `apt
install` is allowed to run on this machine.

`checks/verify.sh` asserts the outcome every day: the loader executes, the
loader's version matches pacman's glibc, the apt guard config is present, the
dpkg refusal wrapper is installed, and `/usr/lib/aarch64-linux-gnu/libcuda.so.1`
still exists.

## The transferable lesson

Two package managers, one `/usr`, no coordination. On a machine with a vendor
stack that is not optional, the coordination has to be structural: the second
manager gets disabled, not trusted. And any guard added to hold that line is
untested until it has refused something real.
