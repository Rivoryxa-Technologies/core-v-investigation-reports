#!/usr/bin/env bash
# Build the mstatus.FS hazard tests into build/*.elf and the matching *.hex
# files that tb_top.sv loads with $readmemh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Toolchain: riscv-none-elf-* (xPack GCC 15.2 was used) on PATH, or set RISCV_TOOLS to its bin
# directory and RISCV_PREFIX if your toolchain uses another prefix (e.g. riscv64-unknown-elf-).
PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"
TOOLS="${RISCV_TOOLS:-$(dirname "$(command -v "${PREFIX}gcc" || echo /missing/x)")}"
CC="$TOOLS/${PREFIX}gcc"
OBJCOPY="$TOOLS/${PREFIX}objcopy"
SRC="$HERE/src"
OUT="$HERE/build"

for t in "$CC" "$OBJCOPY"; do
  [ -x "$t" ] || { echo "missing toolchain binary: $t" >&2; exit 1; }
done

python3 "$HERE/gen.py" "$SRC"

rm -rf "$OUT"
mkdir -p "$OUT"

n=0
for s in "$SRC"/*.S; do
  b="$(basename "$s" .S)"
  "$CC" -march=rv32imfc_zicsr -mabi=ilp32 -nostdlib -nostartfiles -Wl,--no-warn-rwx-segments \
        -T "$HERE/link.ld" -o "$OUT/$b.elf" "$s"
  "$OBJCOPY" -O verilog "$OUT/$b.elf" "$OUT/$b.hex"
  n=$((n+1))
done
echo "built $n tests in $OUT"
