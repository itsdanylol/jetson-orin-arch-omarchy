#!/usr/bin/env bash
# native-audit.sh — does anything on this machine run as x86?
#
# The rule from OS-INTENT: native aarch64, or it does not belong on the host.
# This makes that rule testable instead of aspirational.
#
# Exit 0 = clean (everything that executes here is aarch64)
# Exit 1 = something x86 is in a path that executes
#
# Deliberately allowed:
#   box64 / box64-*   the emulator itself, kept for contained use, not wired
#                     into binfmt, so nothing runs under it by accident
#   qemu-*-static     the binfmt helpers containers need for multi-arch

set -uo pipefail

ALLOW='box64|qemu-(x86_64|i386|aarch64|arm)-static'
bad=0

say() { printf '%s\n' "$*"; }

scan_dir() {
    local dir=$1
    [ -d "$dir" ] || return 0
    find "$dir" -maxdepth 3 -type f -perm -u+x 2>/dev/null | while IFS= read -r f; do
        case "$f" in
            */box64|*/box64-*|*/qemu-*-static) continue ;;
        esac
        case "$(file -b "$f" 2>/dev/null)" in
            *x86-64*|*"Intel 80386"*)
                printf 'X86   %s\n' "$f"
                ;;
        esac
    done
}

say "== x86 executables in PATH"
hits=$( { scan_dir /usr/bin; scan_dir /usr/local/bin; scan_dir "$HOME/.local/bin"; scan_dir /opt; } )
if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    bad=1
else
    say "   none"
fi

say "== processes running under emulation"
em=$(ps -eo comm= 2>/dev/null | grep -Ei '^(box64|qemu-|wine|wineserver)' | sort -u || true)
if [ -n "$em" ]; then
    printf '%s\n' "$em"
    bad=1
else
    say "   none"
fi

say "== binfmt handlers that would catch an x86 binary silently"
if [ -d /proc/sys/fs/binfmt_misc ]; then
    for h in /proc/sys/fs/binfmt_misc/*; do
        [ -f "$h" ] || continue
        name=$(basename "$h")
        case "$name" in qemu-x86_64|qemu-i386|box64) say "   registered: $name" ;; esac
    done
fi

say "== package architecture"
# read the %ARCH% field from pacman's own database, not from the version string
arch=$(uname -m)
total=0
foreign=0
for d in /var/lib/pacman/local/*/desc; do
    [ -f "$d" ] || continue
    total=$((total + 1))
    a=$(awk '/^%ARCH%$/{getline; print; exit}' "$d")
    case "$a" in
        "$arch"|any) ;;
        "") foreign=$((foreign + 1)) ;;
        *) printf '   foreign-arch: %s (%s)\n' "$(basename "$(dirname "$d")")" "$a"; foreign=$((foreign + 1)) ;;
    esac
done
say "   $total packages, $arch or any: $((total - foreign)), foreign-arch: $foreign"
[ "$foreign" -gt 0 ] && bad=1

if [ "$bad" -eq 0 ]; then
    say "== result: everything that executes here is native"
else
    say "== result: x86 present — see the lines above"
fi
exit "$bad"
