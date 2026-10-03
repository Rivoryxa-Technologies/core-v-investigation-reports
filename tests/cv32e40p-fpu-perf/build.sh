#!/usr/bin/env bash
# Build the fpu_perf kernels into build/<march dir>/<kernel>.elf and the matching
# .hex files that tb_top.sv loads with $readmemh.
#   build/f/      rv32imfc_zicsr        (configurations F0, F1, F2)
#   build/zfinx/  rv32imc_zfinx_zicsr   (configurations Z0, Z1, Z2)
#   build/i/      rv32imc_zicsr         (configuration I0, integer control kernel only)
# The expected checksums come from the same source built for the host
# (-DHOST, -ffp-contract=off) and are compiled into each ELF as -DEXPECTED.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Toolchain: riscv-none-elf-* (xPack GCC 15.2 was used) on PATH, or set RISCV_TOOLS to its bin
# directory and RISCV_PREFIX if your toolchain uses another prefix (e.g. riscv64-unknown-elf-).
PREFIX="${RISCV_PREFIX:-riscv-none-elf-}"
TOOLS="${RISCV_TOOLS:-$(dirname "$(command -v "${PREFIX}gcc" || echo /missing/x)")}"
CC="$TOOLS/${PREFIX}gcc"
OBJCOPY="$TOOLS/${PREFIX}objcopy"
OBJDUMP="$TOOLS/${PREFIX}objdump"
HOSTCC="${HOSTCC:-cc}"
SRC="$HERE/src"
OUT="$HERE/build"

for t in "$CC" "$OBJCOPY" "$OBJDUMP"; do
  [ -x "$t" ] || { echo "missing toolchain binary: $t" >&2; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT/f" "$OUT/zfinx" "$OUT/i"

"$HOSTCC" -O2 -ffp-contract=off -DHOST -o "$OUT/host_ref" "$SRC/kernels.c" -lm
"$OUT/host_ref" > "$OUT/host_ref.txt"

CFLAGS=(-O2 -mabi=ilp32 -ffp-contract=off -fno-math-errno -ffreestanding
        -fno-tree-loop-distribute-patterns -nostdlib -nostartfiles
        -Wl,--no-warn-rwx-segments -T "$HERE/link.ld")

n=0
build() {  # dir march kernel-name kernel-macro
  local exp
  exp="$(awk -v k="$3" '$1 == k { print $2 }' "$OUT/host_ref.txt")"
  [ -n "$exp" ] || { echo "no host checksum for $3" >&2; exit 1; }
  "$CC" -march="$2" "${CFLAGS[@]}" -DKERNEL="$4" -DEXPECTED="$exp" \
        -o "$OUT/$1/$3.elf" "$SRC/crt0.S" "$SRC/kernels.c" -lgcc
  "$OBJCOPY" -O verilog "$OUT/$1/$3.elf" "$OUT/$1/$3.hex"
  "$OBJDUMP" -d "$OUT/$1/$3.elf" > "$OUT/$1/$3.dis"
  n=$((n+1))
}

for k in matmul dot axpy fir norm control; do
  m="K_$(echo "$k" | tr a-z A-Z)"
  build f     rv32imfc_zicsr      "$k" "$m"
  build zfinx rv32imc_zfinx_zicsr "$k" "$m"
done
build i rv32imc_zicsr control K_CONTROL

# No soft-float routine may end up in any image: every float operation must be an FPU instruction.
if grep -l '<__[a-z]*sf[0-9]*>:' "$OUT"/*/*.dis; then
  echo "soft-float routine linked into the images above" >&2; exit 1
fi
echo "built $n programs in $OUT"
