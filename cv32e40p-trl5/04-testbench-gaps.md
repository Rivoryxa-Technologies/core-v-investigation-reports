# Two gaps in the cv32e40p-dv-review Verilator core testbench, with patches

*Rivoryxa Technologies · CV32E40P · 3 October 2026 · RTL master 6033d2b*

## Answer

The Verilator `core` testbench in
[cv32e40p-dv-review](https://github.com/openhwgroup/cv32e40p-dv-review) (commit `89ad543`) has two gaps. Two
small patches close them. Each applies cleanly on its own, and they apply together with the FPU patch first.

| Gap | Effect | Patch |
|---|---|---|
| **The FPU latency and Zfinx parameters are hard-coded to 0.** | The pipelined configurations (F1, F2, Z1, Z2) and the Zfinx configurations can't be selected. Every build gets FPU latency 0 and ZFINX 0, whatever the user asks for. | [`patches/tb_fpu_config_plumbing.patch`](patches/tb_fpu_config_plumbing.patch) |
| **The core's `debug_req_i` is tied to 0.** | A debug request from the testbench's virtual peripheral never reaches the core. A directed debug test ran to completion while none of its 32 debug requests reached the core. | [`patches/tb_debug_req_wiring.patch`](patches/tb_debug_req_wiring.patch) |

## The question

Our work on #1060 and the FPU pipeline depth needed the testbench to build F1, F2, Z1 and Z2. Our work on #1004
needed debug requests to reach the core. Both failed silently: the testbench built and ran, but not with the
configuration or stimulus we intended. This report records the two causes so the test suite can be trusted on
these configurations.

## What we did

1. We read the testbench source at `89ad543` and found where the parameters and the debug request are tied
   off.
2. We wrote one patch per gap and applied each to a clean checkout: each on its own, and both together (FPU patch
   first).
3. We checked that the parameters and the debug request now reach the core, using run-time effects (below)
   rather than reading the code.
4. We reran the ACT4 anchors with the patches applied to confirm nothing else changed.

## Results

### Gap 1: FPU latency and Zfinx parameters

At `89ad543`:

| File:line | Code | Problem |
|---|---|---|
| `tb/core/cv32e40p_dut_wrap.sv:97-99` | `.FPU_ADDMUL_LAT (0)`, `.FPU_OTHERS_LAT (0)`, `.ZFINX (0)` | Constants in the v1.8.3 instance of the core wrapper |
| `tb/core/cv32e40p_dut_wrap.sv:48` | `.PULP_ZFINX (0)` | The same, in the older v1.0.0 instance |
| `tb/core/tb_top.sv:25` | `parameter FPU_EN = 0` | `tb_top` exposes only `FPU_EN`, so there is no way to pass the other parameters down |

The patch adds `FPU_ADDMUL_LAT`, `FPU_OTHERS_LAT` and `ZFINX` as parameters of `tb_top` and `cv32e40p_dut_wrap`,
and passes them through to the core. The defaults stay 0, so existing builds don't change.

**Evidence that the parameters now reach the FPU:**

| Check | Result with the patch |
|---|---|
| ACT4 end-of-test simulation time against F0 | Differs on F1 in 7 of 180 passing tests and on F2 in 180 of 180. On F1 the extra add/multiply stage is mostly absorbed by the write-back stage, which is why most F1 times equal F0. |
| Cycle counts of FP kernels ([report 01](01-fpu-pipeline-depth.md)) | Change with latency exactly as the pipeline predicts, for example a dependent dot product: F0 4371, F1 4627, F2 5141 cycles |
| ACT4 pass counts | Unchanged by the patch: I0 94/94, F0 180/181 (only `priv/SmF/SmF-00` fails, which is #1060) |

### Gap 2: debug request tied to 0

At `89ad543`:

| File:line | Code | Problem |
|---|---|---|
| `tb/core/cv32e40p_dut_wrap.sv:85` and `:127` | `.debug_req_i (1'b0)` | The core's debug request is a constant 0 in both core instances |
| `tb/core/tb_top.sv:276` | `.debug_req_o ()` | The virtual peripheral's debug request output (`mm_ram`) is left unconnected |

The patch adds a `debug_req_i` port to `cv32e40p_dut_wrap`, a `debug_req` net in `tb_top`, and connects
`mm_ram.debug_req_o` to it.

**Evidence, from counters bound into the design** (I0, directed test `first_fetch_dt` for #1004, which
requests 32 debug entries):

| Counter | With the patch |
|---|---|
| Debug requests written by the program to the testbench | 32 |
| Debug request rising edges at the core's `debug_req_i` | 32 (64 cycles high) |
| Debug entries taken by the core | 32 |
| Hits on the #1004 condition | 1 |

Without the patch, the same counters showed the program running to the end while none of its 32 debug requests
reached the core: 0 cycles of `debug_req_i` high, and 0 hits on #1004. Those numbers come from our log of
that diagnosis; the run's record was later overwritten, so only the patched run's record is kept. With the
patch, ACT4 on I0 is still 94/94 and F0 is still 180/181 (only `SmF-00` fails).

## What this means for TRL5

- **The pipelined configurations can't be verified with this testbench as it stands.** Any F1, F2, Z1 or Z2
  result produced with it is really an F0 or Z0 result. This matters for the FPU-depth decision
  ([report 01](01-fpu-pipeline-depth.md)) and for #1060 ([report 02](02-issue-1060-pipelined-fpu.md)).
- **Debug-request tests in this testbench never deliver a request to the core.** They can pass without
  exercising the core's external debug-request path (debug entry by `ebreak` is not affected). Any TRL5 claim that rests on debug tests run in this testbench should be rechecked with the
  wiring patch applied.
- **Both patches are small and keep existing behaviour by default.** We are happy to open them as pull requests
  against cv32e40p-dv-review if that is useful.

## How to repeat

```sh
git clone https://github.com/openhwgroup/cv32e40p-dv-review
cd cv32e40p-dv-review
git checkout 89ad543
git apply /path/to/core-v-investigation-reports/cv32e40p-trl5/patches/tb_fpu_config_plumbing.patch
git apply /path/to/core-v-investigation-reports/cv32e40p-trl5/patches/tb_debug_req_wiring.patch
```

Then build the Verilator `core` testbench with the parameters overridden on the Verilator command line, for
example `-GFPU_EN=1 -GFPU_ADDMUL_LAT=1 -GFPU_OTHERS_LAT=1` for F1, or `-GFPU_EN=1 -GZFINX=1` for Z0.

To see gap 1 for yourself, run any FP-heavy program on F0 and on F2. The end-of-test time:

- is identical without the patch;
- differs with the patch.

To see gap 2 for yourself, run a program that writes the testbench's debug-control register, then count
debug-mode entries in the trace or with `dcsr`. You get none without the patch, and one per request with it.

Tools: Verilator 5.050.

## Limits

- **Gap 2 was observed with one directed program.** We didn't audit every debug test in the suite for whether
  it was relying on the tie-off.
- **There is no recorded run of the unpatched build of gap 1 on F1 or F2.** The evidence that the patch is
  needed is the source (the constants above). The evidence that it works is the changed timing and cycle
  counts.
- **The `irq_i` wiring is not part of these gaps.** It is connected in this testbench. A separate problem with
  `irq_i` tied to 0 exists in the older core-v-verif `core` testbench and is not covered here.

## Files

- This report: `cv32e40p-trl5/04-testbench-gaps.md`
- [`patches/tb_fpu_config_plumbing.patch`](patches/tb_fpu_config_plumbing.patch): FPU latency and Zfinx
  parameters, `tb_top.sv` and `cv32e40p_dut_wrap.sv`
- [`patches/tb_debug_req_wiring.patch`](patches/tb_debug_req_wiring.patch): debug request from `mm_ram` to the
  core, `tb_top.sv` and `cv32e40p_dut_wrap.sv`
