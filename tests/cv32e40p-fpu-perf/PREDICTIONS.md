# Predictions for the FPU pipeline-depth performance kernels

Written 2026-10-03 from the RTL at 6033d2b and the disassembly of the built kernels
(`build/f/*.dis`, `build/zfinx/*.dis`), before any simulation of this suite.

## Relevant RTL

- `cv32e40p_decoder.sv:892,900,902,904`: `apu_lat = LAT + 1` for ADDMUL and for
  NONCOMP/CONV (`FPU_OTHERS_LAT`), fixed `2'h3` for DIVSQRT. So F0 issues every
  non-div FP op as `apu_lat = 1` (single cycle), F1 as `2`, F2 as `3` (the same
  "multicycle" class as fdiv/fsqrt).
- `cv32e40p_fp_wrapper.sv:77-91`: fpnew `PipeRegs` = `FPU_ADDMUL_LAT` for ADDMUL,
  `FPU_OTHERS_LAT` for NONCOMP and CONV, `C_LAT_DIVSQRT = 1` for DIVSQRT in every
  configuration. Division and square root cost the same in F0, F1 and F2.
- `cv32e40p_apu_disp.sv`: up to two ops in flight (`inflight`, `waiting`), but
  `stall_type = enable & active & (lat==1 | (lat==2 & last_lat==3) | lat==3)`.
  Lat-2 ops (F1) may issue while another lat-2 op is in flight: F1 pipelines
  independent FP ops. A lat-3 op (every FP op in F2, and fdiv/fsqrt everywhere)
  waits in EX until nothing is in flight, and `active` is registered, so it
  issues two cycles after the previous FP op at the earliest: **F2 does not
  overlap FP ops with each other.** Integer instructions do continue while an FP
  op is in flight (no general stall on `apu_busy`; only CSR accesses stall,
  `cv32e40p_id_stage.sv:920`).
- Read-after-write: `read_dep` holds the consumer in ID until the producer
  returns. Lat-2 results are written on the WB (LSU) port and forwarded like a
  load; lat-3 results on the EX (ALU) port.
- `cv32e40p_ex_stage.sv:205-212`: when a lat-3 result returns while an integer
  instruction that writes the ALU port is in EX, `wb_contention` stalls EX one
  cycle.

## Per-event cost model (cycles, relative to F0)

| event | F1 | F2 |
|---|---|---|
| consumer of an FP result at distance 1 (next instruction) | +1 | +2 |
| consumer at distance 2 | 0 | +1 |
| independent FP op right after an FP op | 0 | +2 (distance 2: +1) |
| FP result returns while an ALU-writing integer op is in EX | 0 | +1 |

## Predicted overhead per kernel (F build; Zfinx code has the same shape)

| kernel | FP ops | where the cost comes from | F1 - F0 | F2 - F0 |
|---|---|---|---|---|
| matmul 16x16 (`fmadd` per k, 4096) | 4096 fmadd + 256 fmv | chain distance 6 with a taken branch in between: hidden. `fsw` at distance 2 after each inner loop | 0 | +256 (one per output) |
| dot, 4 x unrolled, one accumulator | 1024 fmadd | per iteration one `fmadd` at distance 1 on the chain; F2 also one ALU contention | +256 | +768 (range +512..+800) |
| axpy, 4 x unrolled, independent | 1024 fmadd | four back-to-back independent `fmadd`: F1 pipelines them, F2 serialises (+2 each after the first); stores at distance 5 | 0 | +1536 |
| FIR 16 taps x 256 | 4096 fmadd + 256 fmv | as matmul | 0 | +256 |
| norm (128 vectors) | 128 x (fmul, 2 fmadd, fsqrt, fdiv, 3 fmul) | dist-1 chain fmul->fmadd->fmadd->fsqrt; three back-to-back fmul after fdiv; fdiv/fsqrt same in all | +256 (2 per vector) | +1152 (9 per vector) |
| control (integer only) | 0 | none | 0 exactly | 0 exactly |

Absolute F0 counts are not predicted precisely; rough: matmul ~37k, dot ~5k,
axpy ~5.5k, FIR ~37k, norm ~5-6k cycles (div/sqrt dominates). Relative overhead
expected: F1 0..5% on every kernel; F2 ~1% (matmul, FIR), ~15% (dot), ~28%
(axpy), ~20% (norm).

Exact-equality predictions:

1. `instret` is identical across F0/F1/F2 and across Z0/Z1/Z2 for every kernel
   (same binary); `control` cycles are identical on I0, F0-F2, Z0-Z2 (the
   integer code is byte-identical in all three builds).
2. Every checksum equals the host reference (IEEE-754 single precision,
   round-to-nearest-even, fused multiply-add); 6/6 PASS on F0, F1, F2, Z0, Z1,
   Z2 and 1/1 on I0.
3. Z deltas equal the F deltas within a few cycles per kernel (same dispatcher,
   same instruction schedule; Zfinx uses `li` instead of `fmv.w.x` for the zero
   accumulator, so matmul/FIR Z may be up to 256 cycles cheaper in F2).

## Execution time and area (to be checked against the OpenSTA periods)

Plain synthesis periods are F0 32.29, F1 33.38, F2 33.32 ns: with cycles never
lower than F0, **F0 is the fastest plain configuration on every kernel**.
Retimed periods are F0 33.89, F1 17.12, F2 13.12 ns: F2 beats F1 in time iff
`cycles(F2)/cycles(F1) < 17.12/13.12 = 1.305`. Predicted: F2 retimed fastest on
matmul, FIR, dot, norm; axpy near the break-even (~1.28), so a tie to within a
few percent. Retimed F1 and F2 both about 2x faster than F0 on all kernels.

## upstream matmul_32b_float on F with mstatus.FS enabled

The F failure is the FS-Off cause recorded in `upstream_suite/DIAGNOSIS.md`
(`fp_enable()` only under `PULP`). Built with `-DPULP` added (only effect for an
F build: `fp_enable()` runs; the printed text is the same) it is predicted to
PASS on F0, F1, F2, with the printed kernel cycle count within 5% of Z0's 10652,
and F1 - F0 and F2 - F0 within 10% of the Z deltas (+783, +4367).

## Zfinx synthesis (added before the Z0-Z2 sky130hd runs)

Same flow as F (`synthesis/scripts/size.py --lib sky130hd --sta [--retime]`). Zfinx drops the
32 x 32-bit FP register file and its read/write muxing from the core, so:

- area Z_n < F_n at every latency, by 15,000 to 50,000 um2 (about 1,024 flip-flops of ~20 um2 plus muxes);
- area rises Z0 < Z1 < Z2 (checked by the script, `predictions.json["synthesis_mapped"]`);
- plain OpenSTA delay of Z_n within 5% of F_n (the unregistered FPU datapath still dominates);
- retimed OpenSTA delay Z2 < Z1 < Z0 (checked by the script), each within 15% of the F value.

## I0 retimed (added before that run, after the cycle results were known)

Retimed F2 (13.12 ns) is already below plain I0 (13.89 ns), so retiming also shortens paths
outside the FPU. To see whether F2 retimed sits at the integer core's own floor, I0 is run
with the same retimed flow. Predicted: I0 retimed between 11 and 14 ns, so F2 retimed is
within 20% of the floor and a third FPU stage would buy little clock.
