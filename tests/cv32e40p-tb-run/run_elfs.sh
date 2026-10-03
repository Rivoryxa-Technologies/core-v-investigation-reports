#!/usr/bin/env bash
# Run every ELF given on the command line on one testbench binary and print one line per
# program: PASS / FAIL / ERROR (no verdict printed) / TIMEOUT, plus any FPUPERF or
# "RVCP: mstatus" line the program printed.
#
#   ./run_elfs.sh work/F1/obj/Vtb_top ../cv32e40p-fs-hazard/build/*.elf
set -uo pipefail
EXE="${1:?usage: run_elfs.sh <Vtb_top> <elf>...}"; shift
TO="${TIMEOUT:-300}"
for elf in "$@"; do
  name="$(basename "$elf" .elf)"
  out="$( (command -v timeout >/dev/null && timeout "$TO" "$EXE" "+elf_file=$elf" || "$EXE" "+elf_file=$elf") 2>&1)"
  rc=$?
  if [ $rc -eq 124 ]; then v=TIMEOUT
  elif [ $rc -eq 0 ] && grep -q "RVCP-SUMMARY: TEST PASSED" <<<"$out"; then v=PASS
  elif grep -q "RVCP-SUMMARY" <<<"$out"; then v=FAIL
  else v=ERROR; fi
  extra="$(grep -aoE "FPUPERF .*|RVCP: mstatus = 0x[0-9a-fA-F]+" <<<"$out" | tr '\n' ' ')"
  printf '%-22s %-7s %s\n' "$name" "$v" "$extra"
done
