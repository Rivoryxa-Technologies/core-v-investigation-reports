# cv32e40p #1004: interrupt with a pending debug request in FIRST_FETCH

Issue: [openhwgroup/cv32e40p#1004](https://github.com/openhwgroup/cv32e40p/issues/1004).
Site: `cv32e40p_controller.sv:399` (RTL 6033d2b), state `FIRST_FETCH`:

```systemverilog
if (irq_req_ctrl_i && ~(debug_req_pending || debug_mode_q))
```

The coverage hole has two uncovered conditions, and they have different answers:

| Condition | Answer | Evidence |
|---|---|---|
| `irq_req_ctrl_i && debug_mode_q` | Unreachable | `a_1004_irq_in_debug_mode` proven (SymbiYosys, abc pdr), at COREV_PULP=1 and again at COREV_PULP=0 |
| `irq_req_ctrl_i && debug_req_pending` | **Reachable** | Bounded model check gives a counterexample at depth 30 (COREV_PULP=0), and the directed test below hits it in simulation |

## Files

| File | What it is |
|---|---|
| [`checker_1004.sv`](checker_1004.sv) | The two assertions and four covers. Bind or inject into `cv32e40p_controller`. |
| [`env_constraints.sv`](env_constraints.sv) | The environment assumptions used for the proofs: OBI handshake rules and bounded outstanding transactions, no scan, fetch enabled. Bind into `cv32e40p_core`. It mirrors the assumes in the upstream `scripts/formal/src/{insn,data,cv32e40p}_assert.sv`. |
| [`probe_hole1004.sv`](probe_hole1004.sv) | A simulation counter on the same expression. Bound into the controller, it prints `HOLE1004_HITS=<n>` at the end of a run. |
| [`first_fetch_dt.c`](first_fetch_dt.c), [`dbg.S`](dbg.S) | The directed test. It arms the timer interrupt, executes `wfi`, and asks the testbench for a short debug request. The start of the request is swept over 32 delays around the wake-up, so one iteration lands on the FIRST_FETCH cycle. |

## Simulation result

Core-v-verif `core` Verilator testbench, COREV_PULP=0, RTL 6033d2b:

| Program | `HOLE1004_HITS` | Program result |
|---|---|---|
| an ordinary program (prints and exits) | 0 | EXIT SUCCESS |
| `first_fetch_dt` (32 sweep iterations; 32 interrupts and 32 debug entries taken) | **1** | EXIT SUCCESS |

The same probe was also run in the cv32e40p-dv-review Verilator testbench: **0 hits** over the 94 ACT4 programs
and **1 hit** with this directed test.

The 0 over ACT4 is guaranteed by construction. In that testbench, `debug_req_i` is tied to 0, so ACT4 never
sends a debug request to the core (diagnostic counters on the debug request read 0). The hit with the directed
test needs the debug-request wiring patch in
[`../../cv32e40p-trl5/patches/tb_debug_req_wiring.patch`](../../cv32e40p-trl5/patches/tb_debug_req_wiring.patch).
See [report 04](../../cv32e40p-trl5/04-testbench-gaps.md).

## Running it on the core-v-verif `core` testbench

1. Copy `first_fetch_dt.c` and `dbg.S` into `cv32e40p/tests/programs/custom/first_fetch_dt/`.
2. Add `probe_hole1004.sv` to the Verilator source list in `cv32e40p/sim/core/Makefile`.
3. Build with `COREV_PULP=0`, then run `make veri-test TEST=first_fetch_dt`.

Two adjustments to the testbench are needed:

- **The wrapper's port names.** The wrapper must use the current parameter names (`COREV_PULP`,
  `COREV_CLUSTER`, `ZFINX`), and the testbench `irq_i` must be connected to the wrapper's interrupt bus.
- **The debugger code address.** The `.debugger` section is linked at `dm_halt_addr` 0x1A110800, and the
  testbench keeps only 22 bits of the instruction address. Move the `@1A110800` / `@1A111000` records in the
  `.hex` file to `@00110800` / `@00111000` before running.

  The `#1010` row 4 test in [`../cv32e40p-1010-row4`](../cv32e40p-1010-row4) avoids this adjustment by copying
  its handler to RAM at run time.

## Running the formal checks

Our results came from a flow that converts the RTL with sv2v and inserts the checker into the module, because
sv2v has no `bind`. To rerun with SymbiYosys and the yosys-slang front end, bind the modules instead:

```systemverilog
// not run in exactly this form: the bind targets follow cv32e40p_controller / cv32e40p_core port names at 6033d2b
bind cv32e40p_controller triage_chk_1004a u_chk_a (.clk(clk), .rst_n(rst_n), .ctrl_fsm_cs(ctrl_fsm_cs),
  .irq_req_ctrl_i(irq_req_ctrl_i), .debug_mode_q(debug_mode_q));
bind cv32e40p_controller triage_chk_1004b u_chk_b (.clk(clk), .rst_n(rst_n), .ctrl_fsm_cs(ctrl_fsm_cs),
  .irq_req_ctrl_i(irq_req_ctrl_i), .debug_req_pending(debug_req_pending));
bind cv32e40p_core triage_env_constraints u_env (.clk(clk_i), .rst_n(rst_ni), .scan_cg_en_i(scan_cg_en_i),
  .fetch_enable_i(fetch_enable_i), .instr_req_o(instr_req_o), .instr_gnt_i(instr_gnt_i),
  .instr_rvalid_i(instr_rvalid_i), .data_req_o(data_req_o), .data_gnt_i(data_gnt_i), .data_rvalid_i(data_rvalid_i));
```

Run `triage_chk_1004a` in `prove` mode (engine `abc pdr`) and `triage_chk_1004b` in `bmc` mode (depth 30,
engine `smtbmc yices`). Prepare the design with `prep; flatten; memory_map; async2sync; techmap; setundef -anyseq`;
the `techmap` must come before `setundef`, or `$shiftx` in `cv32e40p_cs_registers` leaves X bits that abc rejects.

The clock gate is modelled as transparent. That is sound for an unreachability proof, but not for timing.

Tools used: Yosys 0.69, SBY 0.69, sv2v, Verilator 5.050.
