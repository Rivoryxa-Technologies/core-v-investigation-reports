# CV32E40P towards TRL5: what we checked, what we found

*Rivoryxa Technologies · 3 October 2026 · RTL master 6033d2b · follow-up to the CVE4 meeting of 18 September 2026*

Everything below runs on open-source tools (Verilator, Yosys, SymbiYosys, OpenSTA, Spike). Anyone in the group can rerun it without a licence. Each item links to a short report with the numbers, the commands to repeat it, and a Limits section stating what it does not show.

## At a glance

| CVE4 open point | Our answer | Report |
|---|---|---|
| Which FPU pipeline depth goes to TRL5, and what does it cost? | Without register retiming, the extra stages only cost cycles. With retiming, F1 gives about 1.8x the performance per area of F0, and F2 about 2.0x. Zfinx is about 18% smaller at every latency. | [01 FPU pipeline depth](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/01-fpu-pipeline-depth.md) ([PDF](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/01-fpu-pipeline-depth.pdf)) |
| #1060: do PR #1065 and PR #1070 hold on the pipelined FPU configurations? (question from CEA) | Yes, in everything we ran. Both fixes clear the bug on F0, F1 and F2, including under random bus stalls, interrupts and debug requests. FPU latency does not affect the bug or the fixes. #1060 is not a reason to drop F1, F2, Z1 or Z2. | [02 #1060 on pipelined FPUs](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/02-issue-1060-pipelined-fpu.md) ([PDF](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/02-issue-1060-pipelined-fpu.pdf)) |
| PULP and XCV move to TRL4: do the coverage-hole waivers still hold at COREV_PULP=0? | 4 of the 15 holes disappear. 10 stay proven unreachable (three with a stated condition). #1004 is reachable and needs a test, which we supply. | [03 Coverage holes at COREV_PULP=0](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/03-coverage-holes-trl5-scope.md) ([PDF](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/03-coverage-holes-trl5-scope.pdf)) |
| Testbench readiness for the FPU configurations | The Verilator core testbench builds every configuration at FPU latency 0, and it never sends a debug request to the core. Two small patches fix both. | [04 Testbench gaps](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/04-testbench-gaps.md) ([PDF](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/04-testbench-gaps.pdf)) |
| ImperasDV relaunch is blocked: what can be checked today? | An open-source cross-check against Spike runs today on I0, F0-F2 and Z0-Z2. It finds #1060 and no other design divergence. It is a stopgap, not a replacement: its known blind spots are listed. | [05 Open-source cross-check](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/05-open-source-cross-check.md) ([PDF](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/05-open-source-cross-check.pdf)) |

## 1. FPU pipeline depth: performance against area

**The question.** Which FPU pipeline configuration (latency 0, 1 or 2) should go to TRL5, and what does each cost in area and performance?

**What we found.**
- **Cycles.** F1 costs 0 to 6% more cycles on five small FP kernels; F2 costs 1.5 to 28.5%. On the testbench's own `matmul_32b_float` program, the costs are 30% and 64%.
- **Clock.** Without retiming, the clock does not improve, because the stage registers sit at the FPU output. With retiming, the core's worst path goes from 32.3 ns (F0) to 17.1 ns (F1) and 13.1 ns (F2), against 11.8 ns for the core without an FPU.
- **Area.** Retimed, F1 adds 4.6% and F2 adds 9.5% to the whole core. Zfinx is about 18% smaller than F at every latency.
- **Performance per area** (F0 without retiming = 1.00):

| | F0 | F1 | F2 | Z0 | Z1 | Z2 |
|---|---|---|---|---|---|---|
| without retiming | 1.00 | 0.90 | 0.78 | 1.12 | 1.25 | 0.99 |
| with retiming | 1.02 | 1.81 | 2.00 | 1.13 | 2.15 | 2.56 |

**What it means.** The choice depends on the implementation flow as much as on the RTL. If the flow retimes into the FPU, F1 is the safe middle choice and F2 adds a little more. If it does not, F0 is best. A latency-aware compiler schedule would remove most of the cycle cost at no area.

**Limits.** These are synthesis estimates: one typical corner, no place and route, and the retimed netlists are not equivalence-checked.

Full report: [01-fpu-pipeline-depth.md](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/01-fpu-pipeline-depth.md) · Kernels and synthesis script: [tests/cv32e40p-fpu-perf](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/tree/main/tests/cv32e40p-fpu-perf)

## 2. #1060 on the pipelined FPU configurations

**The question** (Matteo Pezzin, CEA, [on #1060](https://github.com/openhwfoundation/cv32e40p/issues/1060#issuecomment-5601441869)). Are PR #1065 and PR #1070 only partial fixes, because #1060 is a race that the FPU pipeline stages could expose? CEA is considering keeping only F0 and Z0.

**What we found.**

| check | unfixed (F0, F1, F2) | with #1065, #1070 or our comparison patch (F0, F1, F2) |
|---|---|---|
| Runs under random interrupts, debug requests and bus stalls, 20 seeds | 20/20 stale | 20/20 correct |
| Same, with bus stalls up to 8 cycles | | 20/20 correct |
| Random FP programs replayed on Spike | stale | all correct |
| 88 directed tests (`flw`, `fmadd`, `fdiv`/`fsqrt` in flight, `frm`, misaligned `flw`, conversions, moves) | 87/88, only `flw` then `csrr mstatus` fails | 88/88 |
| ACT4 | 180/181 | 181/181 |
| No-FPU core (I0), ACT4 | 94/94 | 94/94 with either PR |

**Why the FPU latency does not matter.** FS becomes Dirty when the `flw` enters write-back. The read is stale only if `csrr mstatus` completes in that same cycle. #1065 delays the CSR access and #1070 forwards Dirty in that cycle. Neither depends on FPU latency or on memory timing. Zfinx cannot have the bug, because FS is hardwired to zero.

**One open point.** The RTL marks FS Dirty after `fclass.s` and `fmv.x.w`, which change no FP state. Judging from its source, Spike does not. This is not yet confirmed by a run.

**Limits.** This is simulation evidence, not a formal proof of either PR.

Full report: [02-issue-1060-pipelined-fpu.md](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/02-issue-1060-pipelined-fpu.md) · Directed tests: [tests/cv32e40p-fs-hazard](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/tree/main/tests/cv32e40p-fs-hazard)

## 3. Coverage-hole waivers in the TRL5 scope (COREV_PULP=0)

**The question.** The open coverage-hole issues were filed against a COREV_PULP=1 build. With PULP and XCV moved to TRL4, does each hole and its waiver still hold?

**What we found.**
- **Disappear (4):** #1005, #1006, #1009 and #1010 (all hardware-loop logic). The code is removed when COREV_PULP=0.
- **Still unreachable, by unbounded proof (10):** #1007, #1011, #1012, #1015, #1016, #1017, #1018, #1019, #1022 and #1023. Three carry a condition:
  - #1012 row 4 holds under a trigger-stability assumption.
  - #1022 has no line-exact waiver.
  - #1023 is proven at FPU latency 0 only.
- **Reachable (1):** #1004. An interrupt with a debug request pending in FIRST_FETCH can happen. A bounded model check finds it at depth 30, and we supply a directed test that hits it in simulation.
- **#1010 (COREV_PULP=1):** rows 2 and 3 are proven unreachable ([PR #1073](https://github.com/openhwfoundation/cv32e40p/pull/1073)). Row 4 is reachable and covered by a directed test (28 hits, 0 in the control). We also opened a bind fix, [PR #1072](https://github.com/openhwfoundation/cv32e40p/pull/1072).

Full report: [03-coverage-holes-trl5-scope.md](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/03-coverage-holes-trl5-scope.md) · Per-issue reports: [reports/](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/tree/main/reports) · #1004 test: [tests/cv32e40p-hole-1004](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/tree/main/tests/cv32e40p-hole-1004)

## 4. Two testbench gaps, with patches

**What we found** in the Verilator core testbench of cv32e40p-dv-review (89ad543):
- **FPU parameters are hardcoded.** `FPU_ADDMUL_LAT`, `FPU_OTHERS_LAT` and `ZFINX` are fixed to 0 in `cv32e40p_dut_wrap.sv`, so every "pipelined" build actually runs at latency 0.
- **No debug requests reach the core.** `debug_req_i` is tied to 0, so a directed debug test ran to completion while none of its 32 debug requests reached the core.

**What we supply.** Two small patches, each applying cleanly on 89ad543. We can send them upstream if they are wanted.

Full report: [04-testbench-gaps.md](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/04-testbench-gaps.md) · Patches: [cv32e40p-trl5/patches](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/tree/main/cv32e40p-trl5/patches)

## 5. An open-source cross-check while ImperasDV is relaunched

**What it is.** Every retired instruction of the design (from RVFI) is compared with Spike. This includes runs with random interrupts, debug requests and bus stalls, the core's own directed programs, and riscv-dv random programs.

**What we found.**
- **Stimulus runs:** 1,020 of 1,020 MATCH on I0, F0-F2, Z0-Z2 and an I0 stress set (2.08 million interrupts and 905,000 debug entries in total).
- **Random programs:** 3,272 runs (3.07 million instructions). The only divergences are #1060, on the unfixed F configurations.
- **Zfinx:** 114 of 114 programs match Spike.
- **Spec version, not a defect:** CSR 0x310 (`mstatush`) is not implemented. The core follows Machine ISA 1.11, and `mstatush` belongs to 1.12.

**Known blind spots.**
- The debug-entry cause is taken from the design rather than checked independently. ImperasDV computes it itself.
- Runs over 8 million cycles are not replayed.
- Trigger debug entries are not supported.

Full report: [05-open-source-cross-check.md](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports/blob/main/cv32e40p-trl5/05-open-source-cross-check.md)

## What is still open

- A formal proof of either #1060 fix.
- Place-and-route numbers for the FPU configurations.
- Equivalence checking of the retimed netlists.
- Confirming the `fclass.s` / `fmv.x.w` FS behaviour against Spike and the spec.
- Two results that changed on a later rerun of the unmodified design (one random Zfinx program, one replay of `illegal_instr_test`), being diagnosed (report 05).
- Measuring the cross-check's bug-finding power with a blind fault-injection study (report 05).
- Review of [PR #1072](https://github.com/openhwfoundation/cv32e40p/pull/1072) and [PR #1073](https://github.com/openhwfoundation/cv32e40p/pull/1073).

## Contact

If you have a bug, a coverage hole, or a verification question on any CORE-V core, contact us. Send the issue and the configuration it applies to. We will come back with a disposition and its evidence, or a clear statement of what stopped us.

- **Avinash Kollu**, Rivoryxa Technologies
- Email: [avinashkollu123@gmail.com](mailto:avinashkollu123@gmail.com)
- Website: [www.rivoryxatechnologies.com](https://www.rivoryxatechnologies.com/)
- All reports: [github.com/Rivoryxa-Technologies/core-v-investigation-reports](https://github.com/Rivoryxa-Technologies/core-v-investigation-reports)
