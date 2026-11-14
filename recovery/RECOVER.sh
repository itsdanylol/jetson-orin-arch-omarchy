#!/bin/bash
# RECOVER.sh (v2) — restore Arch's dynamic loader after a Debian package
# unpacked its own glibc onto this Arch root.
#
# WHY v1 IS DANGEROUS: v1 ended with `rm -rf /usr/lib/aarch64-linux-gnu`.
# That directory holds the NVIDIA/Tegra userspace (libcuda.so, nvidia/,
# tegra-egl/, gbm/, gstreamer-1.0/, libilm*), which has nothing to do with
# Debian. Deleting it destroys the GPU stack. This version removes only files
# that dpkg itself lists, and only direct children of that directory.
#
# RUN FROM UBUNTU, with the image mounted at /newroot:
#   sudo mount /opt/omarchy/omarchy.img /newroot      (or losetup + mount)
#   sudo bash /newroot/root/RECOVER.sh /newroot
set -u
NEWROOT="${1:-/newroot}"
BROKEN=".broken-by-dpkg"
say()  { printf '\n== %s ==\n' "$*"; }
ok()   { printf '   OK    %s\n' "$*"; }
die()  { printf '   FAIL  %s\n' "$*"; exit 1; }

[ "$(id -u)" = 0 ] || die "run with sudo"
[ -d "$NEWROOT/usr/lib" ] && [ -d "$NEWROOT/var/lib/pacman/local" ] || die "$NEWROOT is not an Arch root"

say "expected glibc (from pacman's database)"
DB=$(ls -d "$NEWROOT"/var/lib/pacman/local/glibc-[0-9]* 2>/dev/null | head -1)
[ -n "$DB" ] || die "no glibc entry in pacman's database"
VER=$(basename "$DB" | sed 's/^glibc-//')
ok "glibc $VER"

say "locating that exact package"
PKG=$(ls "$NEWROOT"/var/cache/pacman/pkg/glibc-"$VER"-aarch64.pkg.tar.* 2>/dev/null | head -1)
TMP=""
if [ -z "$PKG" ]; then
    TMP=$(mktemp -d)
    URL="http://mirror.archlinuxarm.org/aarch64/core/glibc-${VER}-aarch64.pkg.tar.xz"
    curl -fsSL -o "$TMP/glibc.pkg.tar.xz" "$URL" || die "download failed: $URL"
    PKG="$TMP/glibc.pkg.tar.xz"
fi
ok "$(basename "$PKG")"

say "extracting loader + libc"
W=$(mktemp -d)
tar -xf "$PKG" -C "$W" usr/lib/ld-linux-aarch64.so.1 usr/lib/libc.so.6 2>/dev/null \
    || tar -xf "$PKG" -C "$W" 2>/dev/null || die "cannot read the package"
[ -f "$W/usr/lib/ld-linux-aarch64.so.1" ] || die "package has no loader"

say "installing"
# v1 left the Debian loader as a symlink here; a loader must be a real file.
[ -e "$NEWROOT/usr/lib/ld-linux-aarch64.so.1$BROKEN" ] || \
    cp -a "$NEWROOT/usr/lib/ld-linux-aarch64.so.1" "$NEWROOT/usr/lib/ld-linux-aarch64.so.1$BROKEN" 2>/dev/null || true
rm -f "$NEWROOT/usr/lib/ld-linux-aarch64.so.1"
install -m 755 "$W/usr/lib/ld-linux-aarch64.so.1" "$NEWROOT/usr/lib/ld-linux-aarch64.so.1" || die "copy failed"
ok "loader restored"
install -m 755 "$W/usr/lib/libc.so.6" "$NEWROOT/usr/lib/libc.so.6" || die "libc copy failed"
ok "libc restored"

say "removing Debian's files — NVIDIA's stay"
rm -f "$NEWROOT"/etc/ld.so.conf.d/aarch64-linux-gnu.conf \
      "$NEWROOT"/etc/ld.so.conf.d/aarch64-linux-gnu.conf.dpkg-new
n=0
for list in "$NEWROOT"/var/lib/dpkg/info/libc6:*.list "$NEWROOT"/var/lib/dpkg/info/libgcc-s1:*.list; do
    [ -f "$list" ] || continue
    while IFS= read -r p; do
        case "$p" in
            /usr/lib/aarch64-linux-gnu/*/*) continue ;;   # gconv/, nvidia/, tegra/, ...
            /usr/lib/aarch64-linux-gnu) continue ;;
            /usr/lib/aarch64-linux-gnu/*)
                f="$NEWROOT$p"
                if [ -f "$f" ] || [ -L "$f" ]; then rm -f "$f"; n=$((n+1)); fi ;;
        esac
    done < "$list"
done
ok "$n Debian libraries removed"

say "rebuilding the loader cache inside the image"
chroot "$NEWROOT" /usr/bin/ldconfig || die "ldconfig failed"
ok "ld.so.cache rebuilt"

say "PROOF"
"$NEWROOT/usr/lib/ld-linux-aarch64.so.1" --version 2>&1 | head -1 | grep -qi 'GNU libc' && ok "loader executes" || die "loader does not execute"
OUT=$(chroot "$NEWROOT" /bin/bash -c 'echo WORKING' 2>&1)
[ "$OUT" = "WORKING" ] && ok "bash runs through it" || die "bash does not run: $OUT"
chroot "$NEWROOT" /usr/bin/ldconfig -p 2>/dev/null | grep -q 'libc.so.6 .*=> /usr/lib/libc.so.6' && ok "cache maps libc to /usr/lib/libc.so.6"
chroot "$NEWROOT" /usr/bin/ldconfig -p 2>/dev/null | grep -q 'libnvidia-allocator' && ok "NVIDIA libraries still resolve"

rm -rf "$W"; [ -n "$TMP" ] && rm -rf "$TMP"
sync
say "REPAIRED — unmount and reboot"
