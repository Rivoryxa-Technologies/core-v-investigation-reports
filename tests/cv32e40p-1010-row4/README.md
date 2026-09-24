# cv32e40p #1010, condition row 4: directed test

Line 850 of `cv32e40p_controller.sv` has four condition rows. Rows 2 and 3 (single-step on, debug mode off) are
proven unreachable (see `reports/rtl-triage-cv32e40p-1010.pdf`). Row 4 (single-step on while in debug mode) is
reachable. This test hits it.

How it works: the test asks the testbench for one debug request. In debug mode, the debug code sets `dcsr.step`,
runs a hardware loop of 10 iterations (`cv.setupi`), clears `dcsr.step`, and returns with `dret`.

- `dbg.S`: debug code (`.debugger` section). `STEP_BIT` is 4 in the test and 0 in the control.
- `main.c`: triggers the debug request and checks the result.

Result (core-v-verif `core` Verilator testbench, COREV_PULP=1, FPU=0, RTL 6033d2b; the controller is identical on `dev`):

| run | row 4 cycles | rows 2/3 cycles |
|---|---|---|
| test (`STEP_BIT=4`) | 28 | 0 |
| control (`STEP_BIT=0`) | 0 | 0 |

Rows counted at the controller on rising clock edges, from the simulation waveform.
