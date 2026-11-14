# 013 — aarch64 has no `libc::ENOATTR`, so `xattr` 0.2.3 breaks the build

**Date:** 2026-11-14
**Layer:** project vendor patch (`~/Work/phoenix/vendor/xattr`)
**Status:** held

## Symptom

Building the GPUI app (`cargo build -p phoenix-app`) died on a dependency:

```
error[E0425]: cannot find value `ENOATTR` in crate `::libc`
   --> xattr-0.2.3/src/sys/mod.rs:12:56
    |
 12 |   pub const ENOATTR: ::libc::c_int = ::libc::ENOATTR;
```

Not our code. `xattr 0.2.3` is pulled in by `gpui → gpui_http_client →
zed-async-tar`.

## Cause

Linux has no `ENOATTR` errno — the equivalent is `ENODATA`. macOS and the BSDs
do define `ENOATTR`, and `xattr`'s `platforms!` macro assigned the same
`libc::ENOATTR` constant to the `android`/`linux`/`macos` group. Newer `libc`
(0.2.191 here) does not provide `ENOATTR` for `aarch64-linux-gnu`, so the crate
stops compiling.

On x86_64 with an older `libc` it happened to compile; this is a
platform-and-toolchain trap, not an architecture-specific design choice —
`cargo tree -i xattr` shows the whole chain in one line.

## Fix

Vendor the crate and define the constant per platform, then patch it in as a
path dependency:

```toml
# ~/Work/phoenix/Cargo.toml
[patch.crates-io]
xattr = { path = "vendor/xattr" }
```

```rust
// vendor/xattr/src/sys/mod.rs, replacing the single libc::ENOATTR line
#[cfg(any($(target_os = $platform),*))]
#[cfg(not(any(target_os = "android", target_os = "linux")))]
pub const ENOATTR: ::libc::c_int = ::libc::ENOATTR;

#[cfg(any($(target_os = $platform),*))]
#[cfg(any(target_os = "android", target_os = "linux"))]
pub const ENOATTR: ::libc::c_int = ::libc::ENODATA;
```

The two `cfg`s are mutually exclusive, so there is one definition per target and
no duplicate-const error across the macro's platform groups.

`ENODATA` (61) is the correct value: it is what `getxattr` sets when the
attribute is absent, which is exactly the case `util.rs` matches on
(`Some(ENOATTR) => Ok(None)`).

## Survives

- [x] `cargo update` — `[patch.crates-io]` redirects the version requirement
- [x] a `libc` bump — the patch no longer depends on what libc does or does not
      define
- [ ] upstream `xattr` 0.2.x fixing it — then the patch can be dropped

Remove it when `cargo tree -i xattr` shows a version that no longer assumes a
Linux `ENOATTR`.

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh        # case 013a
grep -n "ENODATA" ~/Work/phoenix/vendor/xattr/src/sys/mod.rs
cargo build -p phoenix-app                     # in ~/Work/phoenix
```

## Revert

```sh
rm -rf ~/Work/phoenix/vendor/xattr
# and drop the [patch.crates-io] block from ~/Work/phoenix/Cargo.toml
```

The build fails again on aarch64 until upstream is fixed.
