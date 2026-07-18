#!/usr/bin/env bash
set -euo pipefail

status=0

root_public='pub const Terminal = terminal_mod.Terminal;'
if [[ $(grep -Ec '^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]' src/howl_vt.zig) -ne 1 ]] ||
    ! grep -Fxq "$root_public" src/howl_vt.zig; then
    printf 'src/howl_vt.zig: curated embedding root changed\n'
    status=1
fi

while IFS= read -r file; do
    if ! head -n 1 "$file" | grep -q '^//!'; then
        printf '%s:1: missing file owner contract\n' "$file"
        status=1
    fi

    awk '
        /^[[:space:]]*pub (const|fn|var|threadlocal)[[:space:]]/ {
            if (previous !~ /^[[:space:]]*\/\/\//) {
                printf "%s:%d: undocumented public declaration\n", FILENAME, NR
                failed = 1
            }
        }
        { previous = $0 }
        END { exit failed }
    ' "$file" || status=1
done < <(find src -type f -name '*.zig' -print | sort)

exit "$status"
