#!/usr/bin/env bash
# 10-config.sh — derive dany_defconfig from the kernel currently running.
#
# Starting from /proc/config.gz guarantees the board still boots: every tegra,
# NVIDIA and Jetson driver that works today stays enabled. The delta file is
# the only place changes go, so intent is reviewable in git.
#
#   config.dany          one CONFIG_X=y / CONFIG_X=n / # CONFIG_X is not set per line
set -euo pipefail
cd "$(dirname "$0")"
[ -f src/Makefile ] || { echo "run 00-fetch.sh first"; exit 1; }

echo "seeding .config from the running kernel"
zcat /proc/config.gz > src/.config

if [ -f config.dany ]; then
    echo "applying $(grep -cvE '^\s*(#|$)' config.dany) delta line(s) from config.dany"
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue;; esac
        sym=${line%%[= ]*}; sym=${sym#\# }
        ./src/scripts/config --file src/.config $line
        grep -q "CONFIG_${sym#CONFIG_}\b" src/.config || echo "WARN  $line did not take effect"
    done < config.dany
else
    echo "no config.dany — defconfig will be identical to the running kernel"
fi

make -C src olddefconfig >/dev/null
make -C src savedefconfig >/dev/null
cp src/defconfig src/arch/arm64/configs/dany_defconfig
cp src/defconfig dany_defconfig
diff <(zcat /proc/config.gz | grep -E '^(CONFIG_|# CONFIG_)' | sort) \
     <(grep -E '^(CONFIG_|# CONFIG_)' src/.config | sort) > out/config.diff || true
echo "wrote dany_defconfig ($(wc -l < src/defconfig) lines); full diff vs running kernel: out/config.diff ($(grep -c '^[<>]' out/config.diff) lines)"
echo "50-install.sh requires you to run:  touch out/config-reviewed"
echo
echo "review what changed against the running kernel:"
echo "  diff <(zcat /proc/config.gz) src/.config | head"
