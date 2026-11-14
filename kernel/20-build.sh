#!/usr/bin/env bash
# 20-build.sh — build Image + modules. Nothing is installed.
#
# LOCALVERSION=-dany keeps this kernel's module directory separate from the
# stock one, so both can live on the machine at once and a rollback is just
# pointing at the other directory.
#
#   NPROC=6 ./20-build.sh
set -euo pipefail
cd "$(dirname "$0")"
[ -f src/Makefile ] || { echo "run 00-fetch.sh first"; exit 1; }
mkdir -p out

J=${JOBS:-4}   # 8 GB unified RAM is shared with the GPU; 6 jobs can OOM at link time
echo "building with $J jobs — on this board expect 40-90 minutes"
make -C src -j"$J" LOCALVERSION=-dany Image modules 2>&1 | tee out/build.log | tail -5

cp src/arch/arm64/boot/Image out/Image-dany
echo "image: out/Image-dany ($(du -h out/Image-dany | cut -f1))"
echo "modules: $(find src -name '*.ko' | wc -l)"
