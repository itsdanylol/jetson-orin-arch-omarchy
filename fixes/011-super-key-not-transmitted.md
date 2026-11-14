# 011 — Super key: re-encoded in the keyboard's key table

**Date:** 2026-11-14
**Layer:** keyboard firmware (EVision flash, key table at config `0xC0`)
**Status:** held

## Symptom

No `SUPER` binding worked anywhere on the desktop. `Super + W` did nothing, the
Omarchy launcher (`Super + Space`) did nothing, all 47 registered SUPER binds
were dead. Typing, other modifiers and every non-SUPER bind were fine.

The board's RGB ripple lit up on the key press, which made it look like software.
It was not.

## Cause

USB `320F:5000`, an **EVision**-controller keyboard. Its firmware has the Win
key locked: the key is present in the key table, mapped as a *modifier* Left GUI,
and the firmware suppresses modifier bit `0x08` from every report it sends.

Evidence chain, each step ruling out a layer:

- **Hyprland** — `hyprctl binds` lists 47 SUPER binds including
  `SUPER + W → Close window`; `hyprctl submap` = `default`; `hyprctl
  configerrors` empty; `omarchy menu keybindings --print` agrees.
- **xkb** — `/etc/xkb/symbols/omarchy` (`omarchy:shift_caps_compose`) touches
  `<CAPS>` only. `xkbcli compile-keymap` renders `<CAPS>` → `Super_L`, so the
  option path is sound.
- **kernel input** — a reader on `event1` / `event2` / `event6` printed `key 30`
  (the letter `a`) and `key 57` (space) while three Super presses produced zero
  `KEY_LEFTMETA`. The key never reaches the input layer.
- **HID descriptor** — `hidraw0`'s report descriptor declares
  `Usage Minimum 0xE0` … `Usage Maximum 0xE7`, which includes `0xE3` (Left GUI).
  The interface advertises the key.
- **raw reports** — reading `/dev/hidraw0` directly, 22 reports, byte 0 (the
  modifier bitmap) was `00` in every single one while the keycodes appeared in
  byte 2. The firmware does not put the bit on the wire.
- **key table** — read over the vendor protocol: entry 13 is
  `02 01 08`, i.e. *modifier, Left GUI*. Configured correctly, emitted never.

So: a win-lock flag in flash, in a region the vendor tools do not document.

## Fix

The lock guards modifier **bit** `0x08` in byte 0 of the report. The same key
re-encoded as a **key usage** travels in the keycode array instead, and the HID
layer maps usage `0xE3` to `KEY_LEFTMETA` just the same:

```
offset 0xE7:  02 01 08   (modifier, Left GUI)   →   02 02 e3   (key, usage 0xE3)
```

Same physical key, same position, different field. The lock never sees it.

Written over the EVision vendor HID protocol (usage page `0xFF1C`, usage `0x92`,
report id 4), the same one OpenRGB and OpenEVision speak:

```
byte 0     report id 4
byte 1-2   checksum, sum of bytes 3..63, little endian
byte 3     command: 0x01 begin, 0x06 write config, 0x02 end
byte 4     payload length
byte 5-6   offset, little endian
byte 7     status
byte 8+    payload
```

Procedure actually run, aborting on any mismatch:

1. read the full 384-byte key table, compare to the backup byte for byte
2. read entry `0xE7`, confirm it is `02 01 08`
3. no-op write — the identical 3 bytes — read back, confirm unchanged
4. write `02 02 e3`, read back, confirm
5. full table read-back: two bytes changed (index 40, 41; the leading `02` was
   already `02`), nothing else touched

Backup of the whole table before any write:
`~/Work/keyboard-backup/keytable-320f-5000-20261114-1935.bin`

Tool for reading it back:
```sh
sudo ~/.local/bin/evision-keyentry 0xE7 3     # → 02 02 e3
```

An interim workaround (`caps:super` in `~/.config/hypr/input.lua`) was used while
the cause was being found, and has been removed — Caps Lock is Caps Lock again
and Shift+Caps compose is back.

## Survives

- [x] `pacman -Syu`
- [x] `omarchy update`
- [x] kernel bump
- [x] replug / reboot / different machine — it is stored in the keyboard
- [ ] a keyboard **factory reset** — that restores the vendor default and the
      key goes silent again

## Verify

```sh
bash ~/Work/custom-os/checks/verify.sh        # cases 011a–011b
sudo ~/.local/bin/evision-keyentry 0xE7 3     # must print: 02 02 e3
```

Plus the human test that started all of this: `Super + W` closes a window.

## Revert

```sh
# put the modifier entry back
sudo python3 - <<'EOF'
# offset 0xE7, data 02 01 08, same begin/write/end sequence as above
EOF
```

Or restore the whole table from
`~/Work/keyboard-backup/keytable-320f-5000-20261114-1935.bin`. Either way Super
stops working again, because the firmware lock is untouched — this fix routes
around the key, it does not unlock it.
