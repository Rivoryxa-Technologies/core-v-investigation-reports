# mstatus.FS hazard directed tests

Directed bare-metal tests for the CV32E40P `mstatus.FS` update hazard reported
as openhwgroup/cv32e40p#1060. The ACT4 suite covers this only through a single
FP-load case (`priv/SmF/SmF-00`). These tests widen the coverage to every class
of floating-point instruction that must set `FS` to Dirty, and to three CSR
read distances, so that a failing table entry names the exact instruction and
distance rather than a whole suite.

## What a test does

Every test is a single self-contained program:

1. Install a trap handler; any trap reports failure.
2. Write `mstatus` to 0, then set `FS` to Initial (`2'b01`) so FP instructions
   decode.
3. Set up the operands, then force `FS` back to Initial and `SD` to 0.
4. Execute the instruction under test.
5. Execute `d` `nop`s.
6. `csrr x10, mstatus`.
7. Pass only if the value read has `FS == 2'b11` (Dirty) and `SD == 1`.

The observed `mstatus` value is always printed as
`RVCP: mstatus = 0x........` before the verdict, so a failure log shows the
stale value directly.

`.option norvc` is used throughout and the measurement window starts on a
64-byte boundary, so the distance between the instruction under test and the
`csrr` is exactly `d` 4-byte instructions.

## Cases

| case | instruction | path to Dirty |
|---|---|---|
| `flw` | `flw f0, 0(x14)` | FP register file write from the load-store unit |
| `fadd_s` | `fadd.s f0, f1, f2` | APU writeback, ADDMUL class (`FPU_ADDMUL_LAT`) |
| `fmul_s` | `fmul.s f0, f1, f2` | APU writeback, ADDMUL class |
| `fdiv_s` | `fdiv.s f0, f1, f2` | APU writeback, DIVSQRT class |
| `fsqrt_s` | `fsqrt.s f0, f1` | APU writeback, DIVSQRT class |
| `fcvt_s_w` | `fcvt.s.w f0, x15` | APU writeback, CONV class (`FPU_OTHERS_LAT`) |
| `fcvt_w_s` | `fcvt.w.s x11, f3, rtz` | fflags only: 1.5 to integer is inexact, so NX is raised. The destination is an integer register, so there is no FP register write |
| `feq_s_snan` | `feq.s x11, f4, f5` | fflags only: `f4` holds a signalling NaN, so NV is raised. Integer destination |
| `fmv_w_x` | `fmv.w.x f0, x15` | APU writeback, CONV class |
| `fsgnj_s` | `fsgnj.s f0, f1, f2` | APU writeback, NONCOMP class, no flags raised |
| `csrw_fcsr` | `csrw fcsr, x15` | explicit FP CSR write |
| `csrw_fflags` | `csrw fflags, x15` | explicit FP CSR write |

Each case is built at `d` in {0, 1, 2, 8}, giving 48 ELFs. `d = 8` is the
control: eight `nop`s exceed every writeback path in this core, so a `d = 8`
failure indicates a defect in the test, not in the design.

Cases added on 2026-10-03 (`CASES_2` in `gen.py`; the 48 above are generated
byte-for-byte as before). Each also reads `mstatus` a second time eight `nop`s
after the first read and fails if the first read differs from it in FS or SD;
"dirty" cases also require Dirty. 40 ELFs, 88 in total.

| case | instruction(s) | check |
|---|---|---|
| `fmadd_s`, `fnmsub_s` | `fmadd.s` / `fnmsub.s f0, f1, f2, f3` | dirty (ADDMUL class) |
| `fmin_s` | `fmin.s f0, f1, f2` | dirty (NONCOMP class) |
| `fclass_s`, `fmv_x_w` | `fclass.s x11, f1` / `fmv.x.w x11, f1` | settled only: no FP state changes, so the architecture does not require Dirty. The RTL sets Dirty for every FPU operation (`fpu_fflags_we_o = apu_valid`); Spike does not for these two |
| `fcvt_wu_s` | `fcvt.wu.s x11, f3, rtz` (1.5, NX) | dirty |
| `csrw_frm` | `csrw frm, x15` | dirty |
| `fdiv_flw`, `fsqrt_flw` | `fdiv.s` / `fsqrt.s`, then `flw f3`, then `d` nops, then the read | dirty. The divide is still running when the `flw` retires (the read is held by `apu_busy_i`); the divide also sets Dirty, so this does not isolate the load path |
| `flw_misal` | `flw f0, 2(x14)` (two bus transactions) | dirty |

## Build

    ./build.sh

`gen.py` writes the assembly into `src/` (the generated files are also committed
here), then `build.sh` assembles and links each file with `link.ld` and produces
`build/<case>_d<d>.elf` and the `.hex` image. The toolchain is
`riscv-none-elf-gcc` on `PATH` (xPack GCC 15.2 was used); set `RISCV_TOOLS` to its
`bin` directory, and `RISCV_PREFIX` if your toolchain uses another prefix.

## Run

Build the testbench once per configuration and state with
[`../cv32e40p-tb-run/build_tb.sh`](../cv32e40p-tb-run/build_tb.sh), then run the
ELFs with [`../cv32e40p-tb-run/run_elfs.sh`](../cv32e40p-tb-run/run_elfs.sh):

    cd ../cv32e40p-tb-run
    ./build_tb.sh F1                                   # base RTL, FPU latency 1
    ./run_elfs.sh work/F1/obj/Vtb_top ../cv32e40p-fs-hazard/build/*.elf

    curl -sL -o pr1065.patch https://github.com/openhwgroup/cv32e40p/pull/1065.diff
    curl -sL -o pr1070.patch https://github.com/openhwgroup/cv32e40p/pull/1070.diff
    ./build_tb.sh F1 pr1065.patch                      # only rtl/ hunks are applied
    ./run_elfs.sh work/F1_pr1065/obj/Vtb_top ../cv32e40p-fs-hazard/build/*.elf

Expected: on the base RTL only `flw_d0` fails, printing `RVCP: mstatus = 0x00003800`;
with either PR all 88 pass and print `0x80007800`.

## Reporting mechanism

The tests reuse the virtual peripherals of the core testbench, the same ones
the ACT4 model macros use:

- `0x10000000` is the character printer. The pass and fail banners and the
  observed `mstatus` value are written one byte at a time to this address.
- `0x20000000` is the test status register. Writing `123456789` ends the
  simulation as a pass, writing `1` ends it as a failure.
- `0x20000004` is the exit register.

The banner text is the string the matrix runner greps for,
`RVCP-SUMMARY: TEST PASSED`, so these ELFs can be scored by the existing
runner without changes to it.

## Recorded result

2026-10-03 (RTL 6033d2b), 88 tests per cell: base 87/88 on F0, F1 and F2 (only `flw_d0`),
pr1065, pr1070 and local 88/88; predictions in `PREDICTIONS_2026-10-03.md`.
The 2026-09 result for the original 48 follows and is unchanged.

Run over F0, F1 and F2 (`FPU_ADDMUL_LAT` = `FPU_OTHERS_LAT` = 0, 1, 2) and the
states base, pr1065, pr1070 and local, 48 tests per cell, 12 cells.

- base, all three configurations: 47 pass, 1 fail. The only failure is
  `flw_d0`, which reads `mstatus = 0x00003800`, that is `FS = 2'b01` (Initial)
  and `SD = 0`, instead of the required `0x80007800`.
- pr1065, pr1070 and local, all three configurations: 48 pass.

No floating-point *operation* showed a stale `FS` read at any distance, in any
configuration, in any state. Adding pipeline stages to the FPU does not create
a new stale-read window, because the decoder reports `apu_lat = LAT + 1`, so
`apu_lat_ex_o[1]` is set for every non-zero latency and `csr_apu_stall` already
holds the CSR access. At latency 0 no stall is needed, because the APU result
is written back through the EX-stage forwarding path one cycle before the
following CSR access reaches EX.


## Limits

- This is simulation evidence for the executed instruction and distance
  combinations only. It is not a proof, and it does not establish that no other
  instruction or distance is affected.
- Only the single-precision subset reachable from `rv32imfc` is covered. Zfinx,
  half precision and the PULP FP extensions are not exercised.
- The memory system is the simple testbench RAM with no wait states beyond the
  default testbench behaviour. A configuration with different load latency
  could shift which distance is sensitive.
- The tests check `FS` and `SD` only. They do not check `fflags` values, the
  arithmetic result, or the Clean-to-Dirty transition from a Clean starting
  state.
- The trap handler treats every trap as a failure, so a test that traps for an
  unrelated reason is reported as a failure and must be read from the log,
  which prints `mcause`.
- A negative control was run separately: the same program with the instruction
  under test replaced by a `nop` reads `mstatus = 0x00003800` and fails. This
  confirms that the setup sequence really leaves `FS` at Initial, so a pass is
  caused by the instruction under test and not by residual state.

## Files in this directory

- `gen.py`, `src/*.S`, `build.sh`, `link.ld`: the 88 tests.
- `PREDICTIONS.md` (2026-09) and `PREDICTIONS_2026-10-03.md`: the predictions, written
  before the runs and copied unchanged from our internal records. Paths inside them
  refer to our internal workspace, not to this repository.
- `stimulus_program/fs_stale.c`: the program used for the runs under random interrupts,
  debug requests and bus stalls (report 02). Those runs need our replay-against-Spike
  harness, which is not public; the program is included so the exposure it creates can
  be read.
