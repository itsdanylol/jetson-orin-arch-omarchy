#!/usr/bin/env bash
# apply-recovery-hardening.sh — run ONCE after the machine boots again.
#
# Makes a host-side Debian unpack structurally impossible instead of
# "guarded by a script with a bug in it". Three layers, all durable:
#
#   1. apt on the host can only simulate — it never downloads, never unpacks.
#   2. dpkg on the host refuses to run at all without an explicit token.
#   3. apt-guard is corrected (the bug was a leading "./" left on paths, so
#      every comparison against pacman's database missed).
#
# Real Debian packages still work normally inside `distrobox enter dany-deb`.

set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "== 1. apt may only simulate on this host"
cat >/etc/apt/apt.conf.d/99-arch-guard <<'EOF'
// This host's /usr belongs to pacman. apt exists only to inspect packages.
// Simulate=1 means no download, no unpack, no dpkg call. Ever.
APT::Get::Simulate "true";
APT::Get::Assume-Yes "true";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF

echo "== 2. dpkg refuses to run without an explicit token"
cat >/usr/local/bin/dpkg-refuse <<'EOF'
#!/bin/sh
# Called by dpkg's pre-invoke hook. Host dpkg exists for inspection only.
if [ "${DPKG_HOST_INSTALL:-0}" != "1" ]; then
    cat >&2 <<'MSG'
dpkg: host installs are disabled on this machine.

  This /usr belongs to pacman. A Debian libc6 unpack here once replaced
  Arch's dynamic loader and left the system unable to start any process.

  Inspect a package:      dpkg-deb -c foo.deb
  Really install it:      prefix the command with  DPKG_HOST_INSTALL=1
  Install it properly:    distrobox enter dany-deb   (real apt, isolated)
MSG
    exit 1
fi
exit 0
EOF
chmod 755 /usr/local/bin/dpkg-refuse
cat >/etc/dpkg/dpkg.cfg.d/99-arch-guard <<'EOF'
# Hard stop for host-side Debian installs. See /usr/local/bin/dpkg-refuse.
pre-invoke "/usr/local/bin/dpkg-refuse"
EOF

echo "== 3. corrected apt-guard (path normalisation was wrong)"
cat >/usr/local/bin/apt-guard <<'EOF'
#!/usr/bin/env bash
# apt-guard — refuse a Debian package that would overwrite a pacman-owned file.
# The earlier version compared paths that still had a leading "./" against a
# database with no leading slash, so every comparison missed and it approved
# everything. Paths are normalised in one place now.
set -uo pipefail

DB=/var/lib/apt-guard/pacman-files.txt
STAMP=/var/lib/apt-guard/pacman-files.stamp
ARGV0=${APT_GUARD_NAME:-$(basename "$0")}

die() { printf 'apt-guard: %s\n' "$*" >&2; exit 1; }

normalise() { sed -e 's|^\./||' -e 's|^/||' -e 's|/$||'; }

rebuild_db() {
    local newer
    newer=$(find /var/lib/pacman/local -maxdepth 1 -type d -newer "$STAMP" 2>/dev/null | head -1)
    if [ ! -s "$DB" ] || [ -n "$newer" ]; then
        printf 'apt-guard: indexing pacman ownership...\n' >&2
        pacman -Qlq 2>/dev/null | normalise | sort -u >"$DB.tmp"
        mv "$DB.tmp" "$DB"
        touch "$STAMP"
    fi
}

deb_files() {
    dpkg-deb -c "$1" 2>/dev/null |
        awk '$1 ~ /^-/ || $1 ~ /^l/ { for (i = 6; i <= NF; i++) if (i == NF) print $i }' |
        normalise | sort -u
}

check_debs() {
    local rc=0 f conflicts
    for f in "$@"; do
        dpkg-deb -I "$f" >/dev/null 2>&1 || continue
        conflicts=$(deb_files "$f" | comm -12 - "$DB" | head -20)
        if [ -n "$conflicts" ]; then
            printf 'apt-guard: %s would overwrite pacman-owned files:\n' "$(basename "$f")" >&2
            printf '  /%s\n' $conflicts >&2
            rc=1
        fi
    done
    return $rc
}

if [ "$ARGV0" = dpkg ]; then
    debs=()
    for a in "$@"; do case "$a" in *.deb) debs+=("$a");; esac; done
    if [ ${#debs[@]} -gt 0 ]; then
        rebuild_db
        check_debs "${debs[@]}" || [ "${APT_GUARD_FORCE:-0}" = 1 ] ||
            die "refusing: use distrobox enter dany-deb"
    fi
    exec /usr/bin/dpkg "$@"
fi

cmd=""; seen=0; pkgs=()
for a in "$@"; do
    case "$a" in
        -*) continue;;
        *) if [ "$seen" = 0 ]; then seen=1; cmd="$a"; else pkgs+=("$a"); fi;;
    esac
done

case "$cmd" in
    install|reinstall)
        rebuild_db
        tmpd=$(mktemp -d)
        ( cd "$tmpd" && /usr/bin/apt-get download "${pkgs[@]}" >/dev/null 2>&1 ) || true
        mapfile -t debs < <(find "$tmpd" -maxdepth 1 -name '*.deb')
        if [ ${#debs[@]} -gt 0 ]; then
            check_debs "${debs[@]}" || [ "${APT_GUARD_FORCE:-0}" = 1 ] ||
                { rm -rf "$tmpd"; die "refusing: those packages collide with pacman"; }
        fi
        rm -rf "$tmpd"
        ;;
esac

exec /usr/bin/"$ARGV0" "$@"
EOF
chmod 755 /usr/local/bin/apt-guard
for t in apt apt-get dpkg; do
    printf '#!/bin/sh\nAPT_GUARD_NAME=%s exec /usr/local/bin/apt-guard "$@"\n' "$t" \
        >"/usr/local/bin/$t"
    chmod 755 "/usr/local/bin/$t"
done

echo "== 4. sanity"
/usr/bin/pacman -Q glibc
test -x /usr/lib/ld-linux-aarch64.so.1 && /usr/lib/ld-linux-aarch64.so.1 --version | head -1
printf '\nhost apt is now simulate-only; dpkg refuses installs; container unaffected.\n'
