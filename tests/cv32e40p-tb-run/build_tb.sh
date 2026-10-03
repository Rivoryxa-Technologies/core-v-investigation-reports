#!/usr/bin/env bash
# Build the CV32E40P Verilator core testbench (openhwgroup/cv32e40p-dv-review) for one
# configuration, with the FPU-parameter plumbing patch, and optionally an RTL patch.
#
#   ./build_tb.sh <config> [rtl.patch]      config: I0 F0 F1 F2 Z0 Z1 Z2
#
# Result: work/<config>[_<patch name>]/obj/Vtb_top. Run a program with
#   work/<cell>/obj/Vtb_top +elf_file=<program>.elf
# A program passes when the log contains "RVCP-SUMMARY: TEST PASSED".
#
# Pinned refs (the ones every result in cv32e40p-trl5/ was produced with):
#   RTL        openhwgroup/cv32e40p          6033d2b (master)
#   testbench  openhwgroup/cv32e40p-dv-review 89ad543
# Tools: Verilator 5.050 (5.x should work), git, a C++ compiler.
# Set CV32E40P_REPO / DV_REVIEW_REPO to local clones to avoid cloning from GitHub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${1:?usage: build_tb.sh <I0|F0|F1|F2|Z0|Z1|Z2> [rtl.patch]}"
RTL_PATCH="${2:-}"
TB_PATCH="${TB_PATCH:-$HERE/../../cv32e40p-trl5/patches/tb_fpu_config_plumbing.patch}"
CV32E40P_REPO="${CV32E40P_REPO:-https://github.com/openhwgroup/cv32e40p.git}"
DV_REVIEW_REPO="${DV_REVIEW_REPO:-https://github.com/openhwgroup/cv32e40p-dv-review.git}"
RTL_REF=6033d2b
TB_REF=89ad543

case "$CFG" in
  I0) P="-GFPU_EN=0 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=0"; FL=cv32e40p_manifest.flist ;;
  F0) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  F1) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=1 -GFPU_OTHERS_LAT=1 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  F2) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=2 -GFPU_OTHERS_LAT=2 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  Z0) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  Z1) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=1 -GFPU_OTHERS_LAT=1 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  Z2) P="-GFPU_EN=1 -GFPU_ADDMUL_LAT=2 -GFPU_OTHERS_LAT=2 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  *) echo "unknown config $CFG" >&2; exit 1 ;;
esac
[ -f "$TB_PATCH" ] || { echo "missing testbench patch: $TB_PATCH" >&2; exit 1; }

CELL="$CFG"
[ -n "$RTL_PATCH" ] && CELL="${CFG}_$(basename "$RTL_PATCH" .patch)"
W="$HERE/work/$CELL"
rm -rf "$W"; mkdir -p "$W"

git clone -q "$CV32E40P_REPO" "$W/rtl" && git -C "$W/rtl" checkout -q "$RTL_REF"
git clone -q "$DV_REVIEW_REPO" "$W/tb" && git -C "$W/tb" checkout -q "$TB_REF"
git -C "$W/tb" apply "$TB_PATCH"
[ -n "$RTL_PATCH" ] && git -C "$W/rtl" apply --include='rtl/*' "$(cd "$(dirname "$RTL_PATCH")" && pwd)/$(basename "$RTL_PATCH")"

T="$W/tb/tb/core"
DESIGN_RTL_DIR="$W/rtl/rtl" verilator --main --binary --cc --sv --exe --build -j 0 \
  --top-module tb_top \
  "$T/tb_top.sv" "$T/cv32e40p_dut_wrap.sv" "$T/tb_riscv/riscv_rvalid_stall.sv" \
  "$T/tb_riscv/riscv_gnt_stall.sv" "$T/mm_ram.sv" "$T/dp_ram.sv" \
  -f "$W/rtl/$FL" --Mdir "$W/obj" -CFLAGS "-std=gnu++14 -O2" \
  -Wno-COMBDLY -Wno-MULTIDRIVEN -Wno-BLKANDNBLK -Wno-lint --Wno-UNOPTFLAT -Wno-MODDUP \
  -Wno-WIDTHCONCAT -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  $P > "$W/build.log" 2>&1 || { tail -30 "$W/build.log"; exit 1; }
echo "built $W/obj/Vtb_top"
