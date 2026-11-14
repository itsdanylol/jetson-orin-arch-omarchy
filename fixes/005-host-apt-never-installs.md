# 005 — host apt/dpkg can never install a Debian package

**Date:** 2026-11-09
**Layer:** local package (files in /usr/local + /etc/apt + /etc/dpkg)
**Survives:** `pacman -Syu` (nothing here is package-owned, except `apt`/`dpkg`
binaries which these shims do not touch)

## Symptom

Every newly started process died with `SIGBUS`, including `sh -c 'echo alive'`,
statically linked binaries, and anything spawned through the opencode HTTP API
(`/api/shell` reported `"signal":"SIGBUS"`). Already-running processes were
unaffected. Cold file reads worked; `ext4` reported no errors.

## Cause

`apt-get install sl` ran on the Arch host. dpkg unpacked Debian's `libc6`
(2.41). That package's file list ends with:

```
/usr/lib/ld-linux-aarch64.so.1
```

which is **Arch's dynamic loader**, glibc 2.43. Every subsequent `execve()`
loaded the Debian 2.41 loader against Arch's 2.43 `libc.so.6`; the mismatch
faults before `main`, so no new process could start.

The guard meant to prevent this had a path-normalisation bug: `dpkg-deb -c`
prints `./usr/bin/foo`, the pacman index stored `usr/bin/foo` — the leading
`./` was never stripped, so the comparison matched nothing and every package
was approved.

## Fix

Three layers, applied by `apply-recovery-hardening.sh`:

1. `/etc/apt/apt.conf.d/99-arch-guard` — `APT::Get::Simulate "true"`. Host apt
   downloads nothing and unpacks nothing; it only reports what it would do.
2. `/etc/dpkg/dpkg.cfg.d/99-arch-guard` — `pre-invoke` runs
   `/usr/local/bin/dpkg-refuse`, which aborts the whole dpkg run unless
   `DPKG_HOST_INSTALL=1` is set.
3. `/usr/local/bin/apt-guard` — corrected: every path goes through one
   `normalise()` (`s|^\./||; s|^/||; s|/$||`) before comparison.

Debian packages still install normally inside the container:

```sh
distrobox enter dany-deb
```

## Recovery that was used

`~/RECOVER.sh` from a live Ubuntu boot: mount `/dev/nvme0n1p1`, loop-mount
`/opt/omarchy/omarchy.img`, extract `usr/lib/ld-linux-aarch64.so.1` and
`usr/lib/libc.so.6` from the cached glibc package into the image, remove
`/usr/lib/aarch64-linux-gnu`, then prove it by running
`bash -c 'echo WORKING'` through the restored loader.

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh
```

Cases `005a`–`005d`: loader executes, loader matches pacman's glibc, apt is
simulate-only, dpkg refuses without the token.

## Revert

```sh
sudo rm /etc/apt/apt.conf.d/99-arch-guard \
        /etc/dpkg/dpkg.cfg.d/99-arch-guard \
        /usr/local/bin/dpkg-refuse
```
