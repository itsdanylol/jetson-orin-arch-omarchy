#!/usr/bin/env bash
# 00-fetch.sh — put the L4T kernel source in src/.
#
# NVIDIA ships this as a tarball per Jetson Linux release; there is no distro
# package for it and no AUR recipe that matches this kernel. This script does
# not invent a URL: give it the tarball you downloaded (JetPack 7.2.1 /
# L4T R39.2.1 → "Jetson Linux sources"), or a URL you trust.
#
#   SRC=/path/to/linux-tegra-R39.2.1.tar.gz   ./00-fetch.sh
#   SRC_URL=https://host/file.tar.gz          ./00-fetch.sh
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d src ] || [ -z "$(ls -A src 2>/dev/null)" ]; then
    mkdir -p src
    if [ -n "${SRC:-}" ]; then
        echo "extracting $SRC"
        tar -xf "$SRC" -C src --strip-components=1 2>/dev/null || tar -xf "$SRC" -C src
    elif [ -n "${SRC_URL:-}" ]; then
        echo "downloading $SRC_URL"
        curl -fL --progress-bar -o out/kernel-src.tar "${SRC_URL}"
        tar -xf out/kernel-src.tar -C src --strip-components=1 2>/dev/null || tar -xf out/kernel-src.tar -C src
    else
        cat <<'MSG'
No source given.

  JetPack 7.2.1 / L4T R39.2.1 kernel source:
    1. download the "Jetson Linux" sources tarball for R39.2.1
    2. unpack it somewhere, or pass it straight in:
         SRC=/path/to/linux-tegra-R39.2.1.tar.gz ./00-fetch.sh

The tarball is ~1 GB; expect the tree to be ~4 GB unpacked and the build to
want another ~8 GB.
MSG
        exit 1
    fi
fi

# sanity: is this actually a kernel tree, and the right one?
m=src/Makefile
[ -f "$m" ] || { echo "FAIL  src/Makefile missing — not a kernel tree"; exit 1; }
v=$(awk -F'= ' '/^VERSION =/{print $2}' "$m")
p=$(awk -F'= ' '/^PATCHLEVEL =/{print $2}' "$m")
echo "source tree: $v.$p"
case "$v.$p" in
    6.8) echo "OK    matches the 6.8 line this board runs" ;;
    *)   echo "WARN  this box runs 6.8.12-1021-tegra; a different line will not load the tegra modules" ;;
esac
