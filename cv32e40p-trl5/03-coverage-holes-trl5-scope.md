# Coverage-hole waivers at COREV_PULP=0 (the TRL5 scope)

*Rivoryxa Technologies · CV32E40P · 3 October 2026 · RTL master 6033d2b*

## Answer

We rechecked the 15 open coverage-hole issues with **COREV_PULP=0**, the configuration that stays in scope for
TRL5 once the PULP and XCV extensions move to TRL4.

| Outcome at COREV_PULP=0 | Count | Issues |
|---|---|---|
| **The hole disappears.** The code is inside `if (COREV_PULP)` or tied to 0. | 4 | #1005, #1006, #1009, #1010 (all hardware-loop logic) |
| **Still present, still proven unreachable.** The waiver carries over. | 10 | #1007, #1011, #1012, #1015, #1016, #1017, #1018, #1019, #1022, #1023 |
| **Present and reachable.** It needs a test, not a waiver. | 1 | #1004 (a directed test is supplied) |

Three of the ten carry a condition. Read the exceptions below before reusing their waiver text.

## The question

At the CVE4 meeting (September 2026), the group agreed to move the PULP extensions (configurations P_F0, P_Z0)
and the XCV instructions to TRL4. The TRL5 configurations therefore build the core with `COREV_PULP=0`.

The open coverage-hole issues were filed against a COREV_PULP=1 build. The question is whether each hole and
its waiver still holds in the TRL5 build.

## What we did

For each of the 15 issues, we started from the existing disposition, rebuilt the design with `COREV_PULP=0`
and reran the same checks:

- **Structural check.** Where the code sits inside a `COREV_PULP` generate or `if`, we matched the source lines
  that remove it. This is a reading of the RTL, not a proof.
- **Formal proof.** For each remaining hole, we reran the unreachability assertion as an unbounded proof
  (SymbiYosys, `abc pdr` unless noted), together with a cover. The cover shows that the surrounding state is
  reachable, so the proof is not true merely because nothing can happen.
- **Reachability check.** Where the hole was already known to be reachable, we reran the bounded model check
  and the directed simulation test.

A prediction for each hole was written before any run. All 15 held.

## Results

| Issue | What the hole is | Site (6033d2b) | At COREV_PULP=0 | How it was checked | Earlier report |
|---|---|---|---|---|---|
| [#1004](https://github.com/openhwgroup/cv32e40p/issues/1004) | Interrupt during the first fetch after wake-up | controller.sv:399 | **Reachable** (one of its two conditions) | `irq && debug_mode_q`: proof PASS. `irq && debug_req_pending`: BMC counterexample at depth 30, plus a directed test hit | [PDF](../reports/rtl-triage-cv32e40p-1004.pdf) |
| [#1005](https://github.com/openhwgroup/cv32e40p/issues/1005) | Outer loop ending inside the inner loop | controller.sv:640 | Disappears | `gen_no_hwlp` ties `hwlp_end*_eq_pc` to 0 (controller.sv:1306-1311) | [PDF](../reports/rtl-triage-cv32e40p-1005.pdf) |
| [#1006](https://github.com/openhwgroup/cv32e40p/issues/1006) | Duplicate hardware-loop jump guard | controller.sv:632, 642 | Disappears | Same tie-off as #1005 | [PDF](../reports/rtl-triage-cv32e40p-1006.pdf) |
| [#1007](https://github.com/openhwgroup/cv32e40p/issues/1007) | Single-step with a stalled decode stage | controller.sv:675 | Still unreachable | `p_line675` proof PASS | [PDF](../reports/rtl-triage-cv32e40p-1007.pdf) |
| [#1009](https://github.com/openhwgroup/cv32e40p/issues/1009) | Nested hardware-loop end addresses too close together | controller.sv:831 | Disappears | Line 831 is in state `DECODE_HWLOOP`, whose whole body is inside `if (COREV_PULP)` (lines 717-899) | [PDF](../reports/rtl-triage-cv32e40p-1009.pdf) |
| [#1010](https://github.com/openhwgroup/cv32e40p/issues/1010) | Debug single-step inside a hardware loop | controller.sv:850 | Disappears | Same `DECODE_HWLOOP` body as #1009 | [PDF](../reports/rtl-triage-cv32e40p-1010.pdf) |
| [#1011](https://github.com/openhwgroup/cv32e40p/issues/1011) | Debug entry with no recorded cause | controller.sv:1187, 1210 | Still unreachable | Both assertions proof PASS; covers reached | [PDF](../reports/rtl-triage-cv32e40p-1011.pdf) |
| [#1012](https://github.com/openhwgroup/cv32e40p/issues/1012) | Debug flush with an impossible single cause | controller.sv:1241 | Still unreachable, **with a condition** | Rows 5 and 10: `abc pdr` PASS. Row 4: k-induction (k=12, `smtbmc yices`) PASS under an assumption | [PDF](../reports/rtl-triage-cv32e40p-1012.pdf) |
| [#1015](https://github.com/openhwgroup/cv32e40p/issues/1015) | Operand-select combination in the ID stage | id_stage.sv:872 | Still unreachable | Proof PASS at FPU=0 and at FPU=1 | [PDF](../reports/rtl-triage-cv32e40p-1015.pdf) |
| [#1016](https://github.com/openhwgroup/cv32e40p/issues/1016) | Write-back contention flag in the EX stage | ex_stage.sv:211 | Still unreachable | Proof PASS; antecedent cover reached | [PDF](../reports/rtl-triage-cv32e40p-1016.pdf) |
| [#1017](https://github.com/openhwgroup/cv32e40p/issues/1017) | Result memorisation enable in the EX stage | ex_stage.sv:387 | Still unreachable | Proof PASS; antecedent cover reached | [PDF](../reports/rtl-triage-cv32e40p-1017.pdf) |
| [#1018](https://github.com/openhwgroup/cv32e40p/issues/1018) | Result memorisation clear in the EX stage | ex_stage.sv:396 | Still unreachable | Proof PASS; antecedent cover reached | [PDF](../reports/rtl-triage-cv32e40p-1018.pdf) |
| [#1019](https://github.com/openhwgroup/cv32e40p/issues/1019) | Ready handshake in the divide and square-root unit | fpnew_divsqrt_th_32.sv:288 | Still unreachable | Proof PASS; antecedent cover reached | [PDF](../reports/rtl-triage-cv32e40p-1019.pdf) |
| [#1022](https://github.com/openhwgroup/cv32e40p/issues/1022) | Arbitration between operation groups in the FPU | rr_arb_tree.sv (gen_fair_arb, lzc) | Cause still holds, **with a condition** | Proof PASS (the arbiter never has more than one requester) | [PDF](../reports/rtl-triage-cv32e40p-1022.pdf) |
| [#1023](https://github.com/openhwgroup/cv32e40p/issues/1023) | Two-cycle APU write-back path in the EX stage | ex_stage.sv:237, 241 | Still unreachable, **with a condition** | Proof PASS at FPU latency 0 | [PDF](../reports/rtl-triage-cv32e40p-1023.pdf) |

All ten "still unreachable" results are unbounded proofs, not bounded checks. No run timed out and no tool
reported an error.

### Exceptions: where "the waiver carries over" needs a qualifier

| Issue | What to know |
|---|---|
| #1012, row 4 | Proven by k-induction under an assumption that the trigger-match input is stable, the same assumption as at COREV_PULP=1. The waiver is valid only if that assumption is accepted. A plain `abc pdr` proof did not finish in over 30 minutes, because the cone includes the 32-bit trigger comparator. |
| #1022 | The cause is proven, but there is no line-exact waiver to carry over. The issue names no module instance or line, so mapping the proof onto specific uncovered lines needs the original coverage database. |
| #1023 | Proven for FPU latency 0 only. It is not established for the pipelined FPU configurations (latency 1 or 2). |

### Which FPU configurations these results cover

| Holes | Built with |
|---|---|
| Controller and ID stage (#1004 to #1015) | FPU=0. #1015 was also proven at FPU=1. |
| FPU and EX-stage (#1016 to #1023) | FPU=1, FPU latency 0 |
| Any hole at FPU latency 1 or 2 | **Not run** |

### #1004: the one hole that is reachable

The hole has two conditions. `irq_req_ctrl_i && debug_mode_q` is proven unreachable.
`irq_req_ctrl_i && debug_req_pending` is reachable at COREV_PULP=0: the core wakes from `wfi` on an interrupt
while a debug request is pending, and lands in FIRST_FETCH with both set. The evidence:

| Evidence | Result |
|---|---|
| Bounded model check, COREV_PULP=0 | Counterexample at depth 30 |
| Directed test, core-v-verif `core` Verilator testbench, COREV_PULP=0 | 1 hit; program EXIT SUCCESS (32 interrupts and 32 debug entries taken) |
| Same counter over the 94 ACT4 programs (cv32e40p-dv-review testbench, I0) | 0 hits |
| Same counter with the directed test added | 1 hit |

The 0 over ACT4 says nothing about the RTL. That testbench ties `debug_req_i` to 0, so ACT4 never sends a debug
request. Diagnostic counters on the debug-request path also read 0 there. The directed test reaches the core
only with the wiring patch from [report 04](04-testbench-gaps.md). The test and its files are in
[`tests/cv32e40p-hole-1004`](../tests/cv32e40p-hole-1004).

### #1010: where it stands upstream

| Rows of line 850 | Status |
|---|---|
| Rows 2 and 3 (single-step on, debug mode off) | Proven unreachable. Assertion submitted as [PR #1073](https://github.com/openhwgroup/cv32e40p/pull/1073). |
| Row 4 (single-step on, in debug mode) | Reachable. Closed by the directed test [`tests/cv32e40p-1010-row4`](../tests/cv32e40p-1010-row4): 28 cycles on row 4, 0 in the control run. |
| Formal bind file | [PR #1072](https://github.com/openhwgroup/cv32e40p/pull/1072) fixes the clock and reset names in the controller bind, so the upstream formal setup can check the controller. |

Both pull requests target `dev`, were opened on 24 September 2026, and have no review yet. At COREV_PULP=0 the
whole of line 850 disappears, because it lives in the hardware-loop state.

## What this means for TRL5

- **The four hardware-loop holes leave the TRL5 scope.** No waiver is needed for them at COREV_PULP=0. Their
  waivers matter only for the TRL4 PULP configurations.
- **Ten waivers carry over to the TRL5 build.** Seven need no qualifier. #1012 row 4, #1022 and #1023 need the
  qualifiers above.
- **#1004 needs a test in the regression, not a waiver.** The directed test hits it. Whether the core behaves
  correctly when it gets there is a separate question that this check does not answer. The program completes
  normally and takes every interrupt and debug request.
- **The pipelined FPU configurations are not covered.** If the TRL5 set includes FPU latency 1 or 2, then
  #1023 and the FPU-side holes (#1016 to #1022) need a rerun at those latencies.

## How to repeat

| Item | Where |
|---|---|
| #1004 checker, environment constraints, directed test and probe | [`tests/cv32e40p-hole-1004`](../tests/cv32e40p-hole-1004), whose README gives the bind lines and the SymbiYosys settings |
| #1010 row 4 directed test | [`tests/cv32e40p-1010-row4`](../tests/cv32e40p-1010-row4) |
| Checkers and proofs for the other holes | Described in each issue's PDF in [`reports/`](../reports) (property text, engine, depth, cover) |

Our harness that drives all 15 is not public. To rerun one proof without it:

1. Read the RTL with the yosys-slang front end (or convert it with sv2v), with `COREV_PULP=0` and the FPU
   setting from the table above.
2. Bind the checker and the environment constraints.
3. Run SymbiYosys:
   - for an unreachability proof, `mode prove`, engine `abc pdr`;
   - for #1012 row 4, k-induction with `smtbmc yices` at depth 12;
   - for #1004 reachability, `mode bmc` at depth 30.
4. Prepare the design with `prep; flatten; memory_map; async2sync; techmap; setundef -anyseq`.

Tools: Yosys 0.69, SBY 0.69, sv2v, yosys-slang, Verilator 5.050.

## Limits

- **Structural "disappears" verdicts are a source reading, not a proof.** The four hardware-loop holes rest on
  matching the generate and `if (COREV_PULP)` lines.
- **The clock gate is modelled as transparent.** That is sound for unreachability, not for timing questions.
- **The proofs hold under the environment constraints in `env_constraints.sv`.** These are the OBI handshake
  rules, at most two outstanding transactions, no scan, and fetch enabled. They mirror the upstream formal
  assumes, but a waiver reviewer should confirm they match the integration.
- **The formal trace for the #1004 counterexample at COREV_PULP=0 was not kept.** The summary result was kept,
  and the simulation hit reproduces it.
- **This checks the 15 known holes only.** Coverage of the COREV_PULP=0 build as a whole was not measured here.
- **Nothing here has been reviewed or accepted by OpenHW.** It is an investigation record, not a sign-off.

## Files

- This report: `cv32e40p-trl5/03-coverage-holes-trl5-scope.md`
- [`tests/cv32e40p-hole-1004/`](../tests/cv32e40p-hole-1004): `checker_1004.sv`, `env_constraints.sv`,
  `probe_hole1004.sv`, `first_fetch_dt.c`, `dbg.S`, `README.md`
- [`tests/cv32e40p-1010-row4/`](../tests/cv32e40p-1010-row4): directed test for #1010 row 4
- Per-issue reports: [`reports/`](../reports)
