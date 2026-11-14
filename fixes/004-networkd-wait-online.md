# Fix 004 — a red unit on every boot that waits for a cable

**Date:** 2026-11-09
**Layer:** systemd
**Status:** held

## Symptom

```
× systemd-networkd-wait-online.service - Wait for Network to be Online
     Active: failed (Result: exit-code) since Sun 2026-11-08 19:30:29 IST

systemd-networkd-wait-online[411]: Timeout occurred while waiting for network connectivity.
```

Nine minutes of waiting, then a permanent failed unit in every
`systemctl --failed`, on every boot.

## Cause

Two network managers are in play: NetworkManager runs the WiFi (networkd sees
`wlP1p1s0` as `unmanaged`), while `systemd-networkd` still claims the ethernet
link `enP8p1s0` and sits in `configuring`/`no-carrier` when nothing is plugged
in. `systemd-networkd-wait-online` waits for every link networkd manages to reach
`routable` — one unplugged cable means it waits the full timeout and fails.
NetworkManager's own wait-online is enabled and already feeds
`network-online.target`, so networkd's is redundant besides being wrong.

## Fix

Turned off the redundant waiter, leaving networkd itself running (it may still
own links the WiFi path does not).

```sh
sudo systemctl disable --now systemd-networkd-wait-online.service
sudo systemctl reset-failed systemd-networkd-wait-online.service
```

`NetworkManager-wait-online.service` stays enabled, so `network-online.target` is
still satisfied by the manager that actually owns the connection.

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump

Disabling removes the `network-online.target.wants` symlink under
`/etc/systemd/system/`, which systemd never regenerates on upgrade. A `systemd`
package update can re-enable it through its preset file, which is exactly why
`checks/verify.sh` asserts it is still off.

## Verify

```sh
systemctl is-enabled systemd-networkd-wait-online.service   # expect: disabled
systemctl --failed --no-legend                              # expect: empty
```

## Revert

```sh
sudo systemctl enable --now systemd-networkd-wait-online.service
```

Only worth doing if networkd takes over the primary connection from
NetworkManager; otherwise the nine-minute timeout comes back.
