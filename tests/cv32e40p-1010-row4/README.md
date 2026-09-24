# cv32e40p #1010, condition row 4: directed test

Line 850 of `cv32e40p_controller.sv` has four condition rows. Rows 2 and 3 (single-step on, debug mode off) are
proven unreachable (see `reports/rtl-triage-cv32e40p-1010.pdf`). Row 4 (single-step on while in debug mode) is
reachable. This test hits it.

How it works: `main.c` copies the debug handler to RAM `0x00110800`, then asks the testbench for one debug request.
In debug mode the handler sets `dcsr.step`, runs a hardware loop of 10 iterations (`cv.setupi`), clears
`dcsr.step`, and returns with `dret`. The test passes if the loop result is 30 and debug mode was entered once.

Why the copy: the core fetches the debug handler from `dm_halt_addr` 0x1A110800. The core-v-verif `core`
testbench keeps only the low 22 bits of the instruction address, so that fetch reads RAM 0x110800. Copying the
handler there means no `.debugger` section is needed, and the program loads on the stock testbench.

Run (core-v-verif, `cv32e40p/sim/core`, COREV_PULP=1): copy `dbg.S` and `main.c` into
`cv32e40p/tests/programs/custom/row4p_step/` (rename `main.c` to `row4p_step.c`), then `make veri-test TEST=row4p_step`.
Control: the same with `#define STEP_BIT 0` in `dbg.S`.

Result (RTL 6033d2b; the controller is identical on `dev`), stock testbench, no hex rewriting:

| run | result | row 4 cycles | rows 2/3 cycles |
|---|---|---|---|
| test (`STEP_BIT 4`) | EXIT SUCCESS, loop 30 | 28 | 0 |
| control (`STEP_BIT 0`) | EXIT SUCCESS, loop 30 | 0 | 0 |

Rows counted at the controller on rising clock edges, from the simulation waveform.
