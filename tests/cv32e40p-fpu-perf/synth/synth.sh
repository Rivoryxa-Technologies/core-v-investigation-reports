#!/usr/bin/env bash
# Whole-core area and worst register-to-register delay of cv32e40p_top for one configuration,
# mapped to sky130_fd_sc_hd (typical corner), plain or retimed. Reproduces the numbers in
# cv32e40p-trl5/01-fpu-pipeline-depth.md.
#
#   ./synth.sh <config> [plain|retime]       config: I0 F0 F1 F2 Z0 Z1 Z2
#
# Needs: yosys with the yosys-slang plugin (OSS CAD Suite; Yosys 0.69 was used), OpenSTA
# (3.1.0 was used; optional: without `sta` on PATH only area and the abc estimate are
# printed), git, and the liberty file:
#   https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/blob/b5dceb3c08fd30c9a1c5c0587bc6a57e0392080a/flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
#   (sha256 ec0e1067a35c8bf20b11e58d1e8ac53326067e4dac84a125cc1b917a3518d0d9), path in $LIB.
# Set CV32E40P_REPO to a local clone to avoid cloning from GitHub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${1:?usage: synth.sh <I0|F0|F1|F2|Z0|Z1|Z2> [plain|retime]}"
MODE="${2:-plain}"
LIB="${LIB:?set LIB to sky130_fd_sc_hd__tt_025C_1v80.lib}"
CV32E40P_REPO="${CV32E40P_REPO:-https://github.com/openhwgroup/cv32e40p.git}"

case "$CFG" in
  I0) G="-GFPU=0 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=0"; FL=cv32e40p_manifest.flist ;;
  F0) G="-GFPU=1 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  F1) G="-GFPU=1 -GFPU_ADDMUL_LAT=1 -GFPU_OTHERS_LAT=1 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  F2) G="-GFPU=1 -GFPU_ADDMUL_LAT=2 -GFPU_OTHERS_LAT=2 -GZFINX=0"; FL=cv32e40p_fpu_manifest.flist ;;
  Z0) G="-GFPU=1 -GFPU_ADDMUL_LAT=0 -GFPU_OTHERS_LAT=0 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  Z1) G="-GFPU=1 -GFPU_ADDMUL_LAT=1 -GFPU_OTHERS_LAT=1 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  Z2) G="-GFPU=1 -GFPU_ADDMUL_LAT=2 -GFPU_OTHERS_LAT=2 -GZFINX=1"; FL=cv32e40p_fpu_manifest.flist ;;
  *) echo "unknown config $CFG" >&2; exit 1 ;;
esac
case "$MODE" in
  plain)  RETIME="" ;;
  # abc moves only plain flip-flops: asynchronous resets are modelled as synchronous first.
  retime) RETIME=$'async2sync\ndffunmap\nabc -dff -D 1\nopt_clean' ;;
  *) echo "mode is plain or retime" >&2; exit 1 ;;
esac

W="$HERE/work/${CFG}_$MODE"; rm -rf "$W"; mkdir -p "$W"
git clone -q "$CV32E40P_REPO" "$W/cv32e40p" && git -C "$W/cv32e40p" checkout -q 6033d2b
R="$W/cv32e40p/rtl"

# Source list: the core's own manifest without the tracer, the testbench wrapper and the
# simulation clock gate, which is replaced by a transparent model (synthesis has no
# clock-gating cell mapping here).
FILES=$(grep '^${DESIGN_RTL_DIR}' "$W/cv32e40p/$FL" | grep -Ev 'tracer|tb_wrapper|sim_clock_gate' \
        | sed "s#\${DESIGN_RTL_DIR}#$R#" | tr '\n' ' ')
INC="-I$R/include -I$R/../bhv -I$R/../bhv/include -I$R/../sva -I$R/vendor/pulp_platform_common_cells/include"

printf 'set_driving_cell sky130_fd_sc_hd__inv_1\nset_load 10.0\n' > "$W/constr.txt"
yosys -q -l "$W/yosys.log" -p "
plugin -i slang
read_slang $G $INC $FILES $HERE/clock_gate_transparent.sv --top cv32e40p_top
hierarchy -top cv32e40p_top
proc
flatten
synth -top cv32e40p_top -flatten
$RETIME
dfflibmap -liberty $LIB
abc -liberty $LIB -constr $W/constr.txt -D 100000
tee -o $W/area.txt stat -liberty $LIB
write_verilog -noattr $W/mapped.v
"
echo "$CFG $MODE: $(grep -i 'chip area' "$W/area.txt" | head -1)"

if command -v sta >/dev/null; then
  cat > "$W/sta.tcl" <<EOF
read_liberty $LIB
read_verilog $W/mapped.v
link_design cv32e40p_top
create_clock -name core_clk -period 100.0 [get_ports clk_i]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_1 [all_inputs]
set_load 0.01 [all_outputs]
report_checks -path_delay max -digits 4 -group_count 1
report_worst_slack -max -digits 4
EOF
  sta -no_init -exit "$W/sta.tcl" > "$W/sta.log" 2>&1
  # No input/output delays are set, so the worst path is register to register; its data
  # arrival time is the number reported (the clock period itself is not a target).
  A=$(awk '/data arrival time/ {print $1; exit}' "$W/sta.log")
  echo "$CFG $MODE: worst register-to-register path $A ns (OpenSTA)"
else
  echo "OpenSTA (sta) not on PATH: timing skipped"
fi
