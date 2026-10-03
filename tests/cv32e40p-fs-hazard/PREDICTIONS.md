# Predictions for the mstatus.FS hazard tests

Written from reading the RTL at 6033d2b, before the matrix was run.

## Relevant RTL

`cv32e40p_core.sv:1060`

    fregs_we = (regfile_alu_we_fw && regfile_alu_waddr_fw[5]) ||
               (regfile_we_wb     && regfile_waddr_wb[5]);

`cv32e40p_cs_registers.sv:1034` raises `mstatus_fs_n = FS_DIRTY` on
`fregs_we_i || fflags_we_i || fcsr_update`, and `mstatus_fs_q` is registered at
`:1217`. A `csrr mstatus` executing in EX in the same cycle as the FP write
therefore reads the pre-update `mstatus_fs_q` (`:468`, `:472`).

`cv32e40p_id_stage.sv:920`

    csr_apu_stall = csr_access & (apu_en_ex_o & (apu_lat_ex_o[1] == 1'b1) | apu_busy_i);

`cv32e40p_decoder.sv:892/900/902/904` sets `apu_lat_o = LAT + 1` for ADDMUL and
OTHERS, and a fixed `2'h3` for DIVSQRT. So `apu_lat_ex_o[1]` is 0 only when the
configured latency is 0, and 1 for latency 1 and 2.

## Expected outcome per case

| case | why FS must go Dirty | base F0 | base F1 / F2 | pr1065 | pr1070 | local |
|---|---|---|---|---|---|---|
| flw d0 | LSU write to FP regfile in WB | FAIL | FAIL | PASS | PASS | PASS |
| flw d1, d2, d8 | same, more slack | PASS | PASS | PASS | PASS | PASS |
| fadd_s, fmul_s (all d) | `fregs_we` from the APU writeback | PASS | PASS | PASS | PASS | PASS |
| fdiv_s, fsqrt_s (all d) | `fregs_we` | PASS | PASS | PASS | PASS | PASS |
| fcvt_s_w, fmv_w_x, fsgnj_s (all d) | `fregs_we` | PASS | PASS | PASS | PASS | PASS |
| fcvt_w_s (all d) | `fflags_we` only (NX from 1.5 -> 1) | PASS | PASS | PASS | PASS | PASS |
| feq_s_snan (all d) | `fflags_we` only (NV from sNaN) | PASS | PASS | PASS | PASS | PASS |
| csrw_fcsr, csrw_fflags (all d) | `fcsr_update`, in-order CSR write | PASS | PASS | PASS | PASS | PASS |

## Reasoning

1. **FP load is the only base failure.** An `flw` writes the FP register file
   from WB, one stage behind the CSR read in EX, so `csrr mstatus` at d = 0 is
   in EX exactly when `regfile_we_wb & regfile_waddr_wb[5]` asserts. Nothing in
   the base `csr_apu_stall` term covers the LSU path, and the load is not an
   APU operation, so `apu_busy_i` is low. This is issue #1060 and matches the
   existing ACT4 `priv/SmF/SmF-00` failure on F0, F1 and F2.

2. **FPU_*_LAT = 0 APU operations should not be stale.** With latency 0 the APU
   result is written back through `regfile_alu_we_fw` while the operation is
   still in EX, one full cycle before the following `csrr` reaches EX, so
   `mstatus_fs_q` is already updated. No stall is needed and none is generated
   (`apu_lat_ex_o == 2'b01`, bit 1 clear).

3. **FPU_*_LAT = 1 or 2 APU operations should be stalled.** `apu_lat_ex_o[1]`
   is set, so `csr_apu_stall` holds the CSR access in ID for as long as the APU
   operation occupies EX, and `apu_busy_i` extends that. The open question is
   whether the stall is released exactly on the writeback cycle rather than one
   cycle after it; if it is, F1 and F2 would show stale reads at d = 0 for the
   ADDMUL and OTHERS classes. The prediction above is PASS, with this as the
   identified risk.

4. **Integer-destination FP operations rely on `fflags_we_i`.** `fcvt.w.s` and
   `feq.s` never write the FP register file, so `fregs_we` stays low and the
   only path to Dirty is the flag write, which is driven by `apu_valid` in
   `cv32e40p_ex_stage.sv:417`, i.e. at the same time as the result. The same
   stall reasoning applies.

5. **Both fixes should clear the `flw` case.** pr1065 and the local patch add
   `data_req_ex_o & ~data_we_ex_o & regfile_waddr_ex_o[5]` to `csr_apu_stall`,
   which holds the CSR access while the FP load is in EX. pr1070 instead
   forwards `FS_DIRTY` into `csr_rdata_int` whenever `fregs_we_i || fflags_we_i`
   is asserted, which covers every same-cycle case including any APU writeback,
   so pr1070 is expected to be the broadest of the three.

6. **d = 8 is the control.** Eight `nop`s exceed every writeback path in this
   core, so a d = 8 failure means the test itself is wrong, not the DUT.
