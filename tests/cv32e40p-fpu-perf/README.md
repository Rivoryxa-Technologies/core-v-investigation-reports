# FPU pipeline depth: cycle counts

Directed C kernels that measure how many cycles the CV32E40P loses when the FPU
has pipeline registers (`FPU_ADDMUL_LAT` = `FPU_OTHERS_LAT` = 0, 1, 2; configurations
F0/F1/F2 and Zfinx Z0/Z1/Z2). Together with the sky130hd OpenSTA periods and areas
this gives execution time and performance per area per configuration.

## What a program does

`src/kernels.c` is built once per kernel (`-DKERNEL=K_<name>`, `-O2`,
`-ffp-contract=off`, multiply-adds written as `__builtin_fmaf`). `src/crt0.S` sets
`mstatus.FS` to Initial (Off at reset on F builds), clears `mcountinhibit`, and calls
`main`, which initialises the inputs, reads `mcycle` and `minstret` around one call of
the kernel and prints

    FPUPERF kernel=<name> cycles=<n> instret=<n> checksum=0x<h> expected=0x<h>

The program passes (`RVCP-SUMMARY: TEST PASSED`, status word 123456789) only if the
checksum equals the host reference: the same source built for the host with
`-DHOST -ffp-contract=off` (IEEE single precision, round-to-nearest-even, fused
multiply-add). Any trap is a failure.

| kernel | content |
|---|---|
| `matmul` | 16x16 matrix product, inner product in one register |
| `dot` | 1024-element dot product, unrolled by 4 into one accumulator (dependent fmadd chain) |
| `axpy` | 1024-element y = a*x + y, unrolled by 4 (independent fmadd) |
| `fir` | 16-tap FIR, 256 outputs |
| `norm` | normalise 128 three-vectors (one fsqrt and one fdiv each) |
| `control` | integer only: bitwise CRC-32 of 1 KiB and an insertion sort of 64 words |

`build/f` (rv32imfc_zicsr) runs on F0-F2, `build/zfinx` (rv32imc_zfinx_zicsr) on
Z0-Z2, `build/i` (rv32imc_zicsr, `control` only) on I0.

## Run

The toolchain is `riscv-none-elf-gcc` on `PATH` (xPack GCC 15.2 was used; the cycle
counts depend on the compiler's schedule, so another version may differ slightly); set
`RISCV_TOOLS` / `RISCV_PREFIX` otherwise. A host C compiler (`cc`) builds the reference
checksums.

    ./build.sh
    cd ../cv32e40p-tb-run
    for c in F0 F1 F2; do ./build_tb.sh $c; ./run_elfs.sh work/$c/obj/Vtb_top ../cv32e40p-fpu-perf/build/f/*.elf; done
    for c in Z0 Z1 Z2; do ./build_tb.sh $c; ./run_elfs.sh work/$c/obj/Vtb_top ../cv32e40p-fpu-perf/build/zfinx/*.elf; done
    ./build_tb.sh I0; ./run_elfs.sh work/I0/obj/Vtb_top ../cv32e40p-fpu-perf/build/i/*.elf

Each line shows `PASS` and `FPUPERF kernel=<name> cycles=<n> ...`. Example (F1):
`dot PASS FPUPERF kernel=dot cycles=4627 instret=3852 checksum=0xc1aa27ba expected=0xc1aa27ba`.

Area and delay per configuration: [`synth/synth.sh`](synth/synth.sh), for example
`LIB=.../sky130_fd_sc_hd__tt_025C_1v80.lib ./synth/synth.sh F1 retime` prints
`Chip area ... 313762.17` and `worst register-to-register path 17.1214 ns`.

The upstream program `matmul_32b_float` row was produced by rebuilding that program from
the testbench repository with its own flags (`-O3`), adding only `PULP` to its defines on
the F configurations so that its `fp_enable()` runs (mstatus.FS is Off at reset). That
rebuild used our internal suite runner and is not scripted here.

## Recorded result (2026-10-03, base RTL 6033d2b)

All 37 programs PASS with the host checksum; `instret` is identical across latencies;
`control` is 89,166 cycles on all seven configurations.

| kernel | F0 | F1 | F2 | Z0 | Z1 | Z2 |
|---|---|---|---|---|---|---|
| matmul | 34960 | +0 | +512 (+1.5%) | 34961 | +0 | +256 (+0.7%) |
| dot | 4371 | +256 (+5.9%) | +770 (+17.6%) | 4371 | +256 | +769 |
| axpy | 5394 | +0 | +1536 (+28.5%) | 5394 | +0 | +1536 |
| fir | 35086 | +0 | +512 (+1.5%) | 35087 | +0 | +256 (+0.7%) |
| norm | 6925 | +256 (+3.7%) | +1152 (+16.6%) | 6925 | +256 | +1152 |
| upstream matmul_32b_float (-O3) | 10075 | +3072 (+30.5%) | +6401 (+63.5%) | 10652 | +768 (+7.2%) | +4352 (+40.9%) |

Mechanism (`cv32e40p_apu_disp.sv`, decoder `apu_lat = LAT + 1`): F1 costs one cycle
per FP result consumed by the very next instruction and still overlaps independent FP
ops; F2 puts every FP op in the multicycle class, so FP ops never overlap (+2 per
back-to-back FP op), a next-instruction consumer waits 2 cycles, and a result
returning while an ALU-writing integer instruction is in EX costs 1 more. Division and
square root are the same in every configuration (`C_LAT_DIVSQRT`). The compiler's
schedule decides the cost: the -O3 F build of the upstream program keeps 12
next-instruction consumers per output (12 x 256 = 3072 exactly), the Zfinx build, short
of registers, only 3 (768).

Predictions: [`PREDICTIONS.md`](PREDICTIONS.md), written before any run and copied
unchanged from our internal records (paths inside it refer to our internal workspace).
Time and area tables: [report 01](../../cv32e40p-trl5/01-fpu-pipeline-depth.md).

## Limits

- Six small kernels and one upstream program, one compiler (GCC 15.2, `-O2`; upstream
  program `-O3`), default `-mtune`. The cost depends on the instruction schedule, which
  a compiler tuned for the configured latency could improve.
- Single-cycle testbench memory, no wait states, no interrupts.
- Simulation evidence for these programs only.
