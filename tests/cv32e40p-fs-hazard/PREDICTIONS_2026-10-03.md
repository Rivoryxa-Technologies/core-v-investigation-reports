# Predictions, 2026-10-03: issue 1060 fixes on pipelined FPU configurations

Written before any run of this date. Question (CEA, Matteo Pezzin, on openhwgroup/cv32e40p#1060):
are pr1065 (merged in dev) and pr1070 (open, master) only partial fixes, because 1060 is a race,
in particular with FPU pipeline stages (F1: FPU_ADDMUL_LAT = FPU_OTHERS_LAT = 1, F2: = 2)?

RTL 6033d2b; patches `chips/cv32e40p/patches/rtl_pr1065.patch`, `rtl_pr1070.patch`, `rtl_local_1060.patch`.

## Mechanism, read from the RTL before the runs

- `fregs_we` (`cv32e40p_core.sv:1060`) is `regfile_we_wb && regfile_waddr_fw_wb_o[5]` on the load
  path. `regfile_we_wb` is `regfile_we_lsu` (`cv32e40p_ex_stage.sv:234`), a register set when the load
  leaves EX (`ex_valid_o`, i.e. after the grant) and held until the response (`wb_ready_i`). So the
  FS update (`cv32e40p_cs_registers.sv:1034`) is triggered in the first cycle the `flw` is in WB,
  whether or not `data_rvalid_i` has arrived, and `mstatus_fs_q` is Dirty one clock later.
- `csrr mstatus` reads `mstatus_fs_q` in EX. On `base` it is stale only if it completes EX in the
  first WB cycle of the `flw`, which needs (a) the `csrr` in ID while the `flw` is in EX and (b) the
  response in that first WB cycle (EX waits for `wb_ready_i`, `cv32e40p_ex_stage.sv:474`). A late
  `rvalid` therefore hides the defect on `base`; it does not create a new window.
- pr1065 holds the CSR access in ID while an FP load is in EX (`data_req_ex_o & ~data_we_ex_o &
  regfile_waddr_ex_o[5]`). The `csrr` then reaches EX no earlier than one clock after the `flw`
  entered WB, when `mstatus_fs_q` is already Dirty. A late grant keeps the `flw` in EX and the stall
  with it; a late `rvalid` does not matter because the FS trigger does not wait for it. The
  WB-stage term of the local patch is therefore redundant for loads. Prediction: no window under
  any bus timing.
- pr1070 forwards Dirty into the read value while `fregs_we_i || fflags_we_i` is high. In the only
  stale cycle on `base` (the `flw` in its first WB cycle) `fregs_we_i` is high, so the read is
  corrected; one clock later `mstatus_fs_q` itself is Dirty. Prediction: no window under any bus
  timing.
- FPU latency (F1, F2) does not enter the load path at all. For FPU operations the existing term
  `apu_en_ex_o & apu_lat_ex_o[1] | apu_busy_i` stalls the CSR access for latency >= 1; at latency 0
  the result is written from EX one clock before the `csrr` reaches EX (as recorded on 2026-09).
- Side observation expected in the new directed cases: `fpu_fflags_we_o = apu_valid`
  (`cv32e40p_ex_stage.sv:417`), so every FPU operation, including `fclass.s` and `fmv.x.w`, which
  change no FP state, sets FS Dirty. Spike (`insns/fclass_s.h`, `fmv_x_w.h`) leaves FS unchanged.
  This is not issue 1060 (no stale read); the new cases check only that the first read equals the
  settled one.

## Step 2, cosim `fs_stale` under stimulus (20 seeds, standard rates: irq 2000, dbg 500, dbg_len 3, stall_max 3, epoch 512)

| state | F1 | F2 |
|---|---|---|
| base | DIVERGED 20/20 (first divergence the `csrr` value, FS Initial against Dirty) | DIVERGED 20/20 |
| pr1065 | MATCH 20/20 | MATCH 20/20 |
| pr1070 | MATCH 20/20 | MATCH 20/20 |
| local | MATCH 20/20 | MATCH 20/20 |

Same rates with stall_max 8 (preset `standard_stall8`), states pr1065 and pr1070 on F0, F1, F2:
MATCH 20/20 in all six cells. Reason: the stall (pr1065) and the forward (pr1070) do not depend on
when `rvalid` arrives.

## Step 3, randgen (seeds as the F0 PR runs: fp_mstatus 40, fp_mstatus_grid 64, fp_mstatus_offset 32)

| config, state | fp_mstatus | fp_mstatus_grid | fp_mstatus_offset |
|---|---|---|---|
| F1, F2 pr1065 / pr1070 / local | 40/40 MATCH | 64/64 MATCH | 32/32 MATCH |
| F1, F2 base (offset only; the other two are recorded) | | | 22 MATCH, 10 DIVERGED, the same seeds as F0 base (the `flw` path does not involve the FPU; medium confidence, because the FP operations of the start-up code could shift fetch timing) |

## Step 4, directed `fs_hazard` (88 ELFs: the 48 unchanged plus 40 new, all at d = 0, 1, 2, 8)

New cases: `fmadd_s`, `fnmsub_s`, `fmin_s`, `fclass_s`, `fmv_x_w`, `fcvt_wu_s`, `csrw_frm`,
`fdiv_flw` (fdiv.s in flight, then flw, then csrr), `fsqrt_flw`, `flw_misal` (flw from address 2 mod 4).

| case | base F0 | base F1, F2 | pr1065 | pr1070 | local |
|---|---|---|---|---|---|
| the 48 existing | as recorded: only `flw_d0` fails | same | PASS | PASS | PASS |
| fmadd_s, fnmsub_s (ADDMUL, FP destination) | PASS | PASS | PASS | PASS | PASS |
| fmin_s (NONCOMP, FP destination) | PASS | PASS | PASS | PASS | PASS |
| fclass_s, fmv_x_w (integer destination, no flag) | PASS, both reads Dirty (see side observation) | PASS | PASS | PASS | PASS |
| fcvt_wu_s (NX raised) | PASS | PASS | PASS | PASS | PASS |
| csrw_frm | PASS | PASS | PASS | PASS | PASS |
| fdiv_flw, fsqrt_flw | PASS: the `csrr` is held by `apu_busy_i` until the divide completes, and the divide itself sets Dirty. This case cannot isolate the `flw` path, because the long operation dirties FS too | PASS | PASS | PASS | PASS |
| flw_misal | PASS at every d (low confidence): `regfile_we_ex_o` is not cleared for the first part of a misaligned access, so the first part should already raise `fregs_we` before the second part reaches WB | PASS | PASS | PASS | PASS |

Per cell: base 87/88 (not passing: `flw_d0.elf`) on F0, F1, F2; pr1065, pr1070, local 88/88.
Entered in `chips/cv32e40p/predictions.json["fs_hazard"]`.

## Step 5, ACT4 on I0

I0 pr1065 94/94 and I0 pr1070 94/94 (equal to I0 base). pr1065's term needs `regfile_waddr_ex_o[5]`,
which no instruction sets without the FP register file; pr1070's forward is gated by `FPU == 1`.
Entered in `predictions.json["act4"]`.

## What would change the answer

A DIVERGED or FAIL on any fixed state stops the work: trace kept, first divergent instruction
diagnosed (pc, instruction, design and Spike mstatus).

## Outcome (2026-10-03, after the runs)

Every prediction above held. No fixed state diverged or failed anywhere.

- Step 2: F1, F2 base 20/20 DIVERGED each (first divergence the `csrr` value); pr1065, pr1070, local
  20/20 MATCH on F1 and F2. stall_max 8: pr1065 and pr1070 20/20 MATCH on F0, F1, F2. Records:
  `runs/cv32e40p/cosim-stimulus/{F1,F2}_<state>_fs_stale/`, `{F0,F1,F2}_{pr1065,pr1070}_fs_stale_stall8/`.
  Exposure, from three F0 pr1065 stall_max-8 seeds rerun with traces kept
  (`F0_pr1065_fs_stale_stall8_traces/flw_csrr_pairs.txt`): 394 `flw` + `csrr mstatus` pairs retired back
  to back, 294 of them in stall epochs with data-response delay enabled (per-transaction delay not logged),
  all read Dirty.
- Step 3: F1, F2 pr1065/pr1070/local: fp_mstatus 40/40, grid 64/64, offset 32/32 MATCH. F1, F2 base
  offset: 22 MATCH / 10 DIVERGED, the same ten seeds as F0 base. The probe-execution check below
  qualifies what these counts mean.
- Step 4: base 87/88 (only `flw_d0`) on F0, F1, F2; pr1065, pr1070, local 88/88. `fclass_s` and
  `fmv_x_w` read Dirty at d = 0 and 8 nops later in every cell (the side observation). `flw_misal`
  passes on base at every d, as predicted with low confidence. The 48 original tests give the same
  verdict in every cell as the 2026-09 records.
- Step 5: I0 pr1065 94/94, I0 pr1070 94/94.

Probe execution (not predicted; found while diagnosing the offset open item). The randgen probe classes
put one or a few probes behind random generator code, and a random forward branch can jump over a probe.
Each program was run once more on each cell and the executed probes counted from the trace
(`runs/cv32e40p/issue1060_2026-10-03/probe_execution/`):

| class | probes in the programs | executed | flw/c.flw at d = 0 executed | stale on base | stale on any fixed state |
|---|---|---|---|---|---|
| fp_mstatus (40) | 480 | 339 | 158 (157 on fixed states) | 158 of 158 | 0 |
| fp_mstatus_grid (64) | 64 | 45 | 1 | 1 of 1 | 0 |
| fp_mstatus_offset (32) | 32 | 22 | 10 | 10 of 10 | 0 |

Same counts on F0, F1 and F2. So the 6 distance-0 offset programs that MATCH on base (seeds 4, 8, 12,
14, 24, 26) never execute their probe (skipped by a taken `bgeu`/`bge`/`bne`/`blt`/`c.beq` from before
the probe to after it). The "10 of 16, alignment dependent" open item is a probe that did not run, not
a timing effect: every executed distance-0 `flw` probe is stale on base (offsets 0, 2, 4, 6, 10, 12, 14;
both offset-8 programs skip their probe, so offset 8 is untested). In the
grid, 19 of 64 probes did not run, including both `fcvt.s.w` d = 0 and both `fadd` d = 3 cells (the
directed suite covers `fcvt_s_w_d0`; d = 3 is not in the directed suite).
