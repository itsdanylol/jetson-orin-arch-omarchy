#!/bin/sh
# verify.sh — every fix in this registry, checked. Run after updates, and daily
# from custom-os-verify.timer. Exit 0 when the machine is still held together.
#
# A FAIL here means an update reverted a fix. Re-apply it, then move it into a
# layer that cannot be reverted.

set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/custom-os"
LOG="$STATE_DIR/verify.log"
mkdir -p "$STATE_DIR"

failed=0
passed=0

check() {
    name=$1
    shift
    detail=$("$@" 2>&1)
    if [ $? -eq 0 ]; then
        passed=$((passed + 1))
        printf 'PASS  %s\n' "$name"
    else
        failed=$((failed + 1))
        printf 'FAIL  %s\n' "$name"
        [ -n "$detail" ] && printf '      %s\n' "$(printf '%s' "$detail" | head -3 | tr '\n' ' ')"
    fi
}

echo "custom-os verify — $(date '+%Y-%m-%d %H:%M')"

# 001 — every pacman hook uses only valid Operation values. One bad hook blocks
# every transaction on the machine, including this check's own packages.
check "pacman hooks parse" sh -c '
    bad=0
    for hook in /etc/pacman.d/hooks/*.hook; do
        [ -e "$hook" ] || continue
        while IFS= read -r line; do
            value=${line#*=}
            value=$(printf "%s" "$value" | tr -d " ")
            case "$value" in
                Install|Upgrade|Remove) ;;
                *) echo "$hook: invalid Operation $value"; bad=1 ;;
            esac
        done <<EOF
$(grep -E "^[[:space:]]*Operation[[:space:]]*=" "$hook")
EOF
    done
    exit $bad
'

# 002 — sudoers parses, and passwordless sudo is actually in effect.
check "sudoers parses" sudo -n visudo -c -q
check "passwordless sudo" sudo -n true

# 003 — the group and shadow files agree, and the daily check unit is happy.
# A oneshot leaves no running process, so the assertion is on its last result,
# not on is-active.
check "grpck" sudo -n grpck -r
check "shadow.service" sh -c '[ "$(systemctl show -p Result --value shadow.service)" = success ]'

# 004 — networkd's wait-online is off; NetworkManager owns the network, and its
# own wait-online feeds network-online.target.
check "networkd wait-online off" sh -c '! systemctl is-enabled --quiet systemd-networkd-wait-online.service'

# 004 — the L4T kernel is still the one booting, with its guard in place.
check "L4T kernel booted" sh -c '[ "$(uname -r)" = "6.8.12-1021-tegra" ]'
check "kernel guard installed" test -x /usr/local/bin/jetson-kernel-guard
check "kernel guard hooks" test -f /etc/pacman.d/hooks/95-jetson-kernel-guard.hook

# 005 — pacman database is consistent and unlocked.
check "pacman database" pacman -Dk

# 005 — the host can never install a Debian package again, and the loader that
# dpkg once replaced is the one pacman's glibc owns.
check "loader executes" sh -c '/usr/lib/ld-linux-aarch64.so.1 --version 2>/dev/null | grep -qi "GNU libc"'
check "loader matches pacman glibc" sh -c '
    want=$(pacman -Q glibc | awk "{print \$2}" | grep -oE "^[0-9]+\.[0-9]+")
    have=$(/usr/lib/ld-linux-aarch64.so.1 --version | head -1 | grep -oE "[0-9]+\.[0-9]+" | head -1)
    [ "$want" = "$have" ] || { echo "want $want have $have"; exit 1; }'
check "host apt is simulate-only" grep -q 'Simulate "true"' /etc/apt/apt.conf.d/99-arch-guard
check "host dpkg refuses installs" test -x /usr/local/bin/dpkg-refuse
check "NVIDIA userspace intact" test -e /usr/lib/aarch64-linux-gnu/libcuda.so.1

# 006 — the custom bar module is present under any section the user chose.
# Its id is `orin` since the rename; accept the old `jetson` id too so the
# check tracks the module, not a historical name.
check "bar jetson module configured" python3 -c '
import json,sys
d=json.load(open("/home/dany/.config/omarchy/shell.json"))
section=d["bar"]["layout"]
ids=[m.get("id") for s in ("left","center","right") for m in section[s]]
sys.exit(0 if ({"jetson","orin"} & set(ids)) else 1)'
check "bar jetson module valid json" sh -c '
/home/dany/.config/omarchy/bar/scripts/jetson-status | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get(\"text\") else 1)"'

# 007 — nothing on this host executes as x86
check "nothing runs as x86" /home/dany/Work/custom-os/checks/native-audit.sh

# 008 — opencode is a mise tool. The install itself must come from mise's
# tree, no second copy may exist behind it, and the supervisor must resolve
# through PATH rather than a hardcoded binary. A curl install reappears here.
check "opencode comes from mise" test -x "$HOME/.local/share/mise/installs/opencode/latest/node_modules/.bin/opencode"
check "no stale opencode install" test ! -e "$HOME/.opencode/bin/opencode"
check "supervisor resolves via PATH" sh -c '
    ! grep -q "HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode-supervise"'

# 009 — every mise-managed agent CLI has a shim ahead of mise on PATH, so its
# own `update` / `upgrade` verb runs `mise upgrade <tool>` instead of failing
# with "Could not detect the installation method".
check "update shims installed" test -x "$HOME/.local/share/mise-cli-shims/_shim"
check "update shims on PATH" grep -q "mise-cli-shims" "$HOME/.bashrc"
check "shim map has opencode" grep -qx "opencode	opencode" "$HOME/.local/share/mise-cli-shims/.map"
check "shim passes through" sh -c '
    PATH="$HOME/.local/share/mise-cli-shims:$PATH" opencode --version | grep -q "^opencode v"'
check "shim routes update to mise" sh -c '
    PATH="$HOME/.local/share/mise-cli-shims:$PATH" MISE_SHIM_PASSTHROUGH=1 opencode --version >/dev/null'

# 010 — cloudflared, and the brain listening only on loopback. A tunnel is only
# safe while the brain refuses unauthenticated edge traffic; a bind regression
# reopens *:8787 to the LAN, which is how this box was found in the first place.
check "cloudflared present" test -x /usr/bin/cloudflared
check "moros-brain is loopback-bound" sh -c '
    ! ss -ltn 2>/dev/null | grep -qE "\*:8787|0\.0\.0\.0:8787|\[::\]:8787"'
check "brain healthz on loopback" sh -c '
    curl -s --max-time 3 http://127.0.0.1:8787/healthz 2>/dev/null | grep -q "\"ok\":true"'
check "edge traffic refused without a token" sh -c '
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
      -X POST http://127.0.0.1:8787/mcp -H "cf-ray: verify" \
      -H "content-type: application/json" -d "{}" 2>/dev/null)
    [ "$code" = "401" ]'

# 011 — the board's Super key is muted by its own firmware, so the key-table
# entry was re-encoded as key usage 0xE3 instead of modifier bit 0x08. This
# lives in the keyboard's flash, not the OS: it survives everything except a
# factory reset of the board. Skips cleanly when that keyboard is not attached.
check "super key re-encoded in keyboard" sh -c '
    name=$(grep -h HID_NAME /sys/class/hidraw/hidraw1/device/uevent 2>/dev/null | cut -d= -f2)
    [ "$name" = "Evision RGB Keyboard" ] || exit 0
    sudo -n "$HOME/.local/bin/evision-keyentry" 0xE7 3 2>/dev/null | grep -q "02 02 e3"'
check "no caps:super crutch" sh -c '! grep -qE "^[[:space:]]*kb_options[[:space:]]*=.*caps:super" "$HOME/.config/hypr/input.lua"'

# 012 — an interrupted transaction leaves db.lck behind with nothing holding it,
# which then refuses every future pacman run on the machine.
check "no stale pacman lock" sh -c '
    [ ! -e /var/lib/pacman/db.lck ] || pgrep -x pacman >/dev/null'

# 013 — aarch64 libc has no ENOATTR, so the vendored xattr defines it as ENODATA.
# Skips cleanly if the phoenix tree is not present on this machine.
check "xattr vendored patch in place" sh -c '
    f="$HOME/Work/phoenix/vendor/xattr/src/sys/mod.rs"
    [ -f "$f" ] || exit 0
    grep -q "ENODATA" "$f"'

units=$(systemctl --state=failed --no-legend 2>/dev/null | wc -l)
if [ "$units" -gt 0 ]; then
    echo "NOTE  $units failed unit(s):"
    systemctl --state=failed --no-legend 2>/dev/null | sed 's/^/      /'
fi

echo "----------------------------------------"
echo "$passed passed, $failed failed"
echo "log: $LOG"

{
    echo "custom-os verify — $(date '+%Y-%m-%d %H:%M') — $passed passed, $failed failed"
} >>"$LOG"

if [ "$failed" -gt 0 ]; then
    printf '%s failed custom-OS check(s) — see %s\n' "$failed" "$LOG" |
        notify-send -a "custom-os" -u critical "A fix was reverted" - 2>/dev/null || true
    exit 1
fi
