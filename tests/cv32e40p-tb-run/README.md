# Running a bare-metal program on CV32E40P (Verilator)

Two small scripts used by the tests in `../cv32e40p-fpu-perf` and `../cv32e40p-fs-hazard`.

- [`build_tb.sh`](build_tb.sh) `<config> [rtl.patch]` clones the RTL (openhwgroup/cv32e40p
  at 6033d2b) and the Verilator core testbench (openhwgroup/cv32e40p-dv-review at 89ad543),
  applies [`tb_fpu_config_plumbing.patch`](../../cv32e40p-trl5/patches/tb_fpu_config_plumbing.patch)
  so that the FPU latency and Zfinx parameters reach the core, optionally applies the
  `rtl/` hunks of an RTL patch (for example an upstream pull request's `.diff`), and builds
  `work/<cell>/obj/Vtb_top`.
- [`run_elfs.sh`](run_elfs.sh) `<Vtb_top> <elf>...` runs each program and prints PASS, FAIL,
  ERROR or TIMEOUT, plus the measurement line the program printed.

| config | FPU | FPU_ADDMUL_LAT | FPU_OTHERS_LAT | ZFINX |
|---|---|---|---|---|
| I0 | 0 | 0 | 0 | 0 |
| F0 / F1 / F2 | 1 | 0 / 1 / 2 | 0 / 1 / 2 | 0 |
| Z0 / Z1 / Z2 | 1 | 0 / 1 / 2 | 0 / 1 / 2 | 1 |

Tools: Verilator 5.050 was used, git, a C++ compiler. Set `CV32E40P_REPO` and
`DV_REVIEW_REPO` to local clones to avoid cloning from GitHub each time.

Without the plumbing patch the testbench builds, but every build runs with latency 0 and
Zfinx off whatever parameters are passed (see
[report 04](../../cv32e40p-trl5/04-testbench-gaps.md)).
