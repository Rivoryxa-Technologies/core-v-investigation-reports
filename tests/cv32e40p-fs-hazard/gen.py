#!/usr/bin/env python3
"""Generate one bare-metal assembly test per (FP instruction, CSR read distance).

Each test sets mstatus.FS to Initial, executes one floating-point instruction,
waits d instructions, reads mstatus, and passes only if the read observes
FS == Dirty (2'b11) and SD == 1. Result is reported to the Verilator core
testbench with the same virtual peripherals the ACT4 suite uses.
"""
import pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent

# name -> (setup, instruction under test)
# Setup runs before mstatus.FS is forced back to Initial, so setup side effects
# on FS do not matter. Operands are chosen so the instruction must set FS.
CASES = [
    # FP load: FP register file write from the LSU (writeback stage).
    ("flw",       "la    x14, fp_a",                               "flw     f0, 0(x14)"),
    # ADDMUL pipeline class: latency follows FPU_ADDMUL_LAT.
    ("fadd_s",    "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",  "fadd.s  f0, f1, f2"),
    ("fmul_s",    "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",  "fmul.s  f0, f1, f2"),
    # DIVSQRT class: always reported as latency 3 by the decoder.
    ("fdiv_s",    "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",  "fdiv.s  f0, f1, f2"),
    ("fsqrt_s",   "la x14, fp_a\nflw f1, 0(x14)",                  "fsqrt.s f0, f1"),
    # CONV class: latency follows FPU_OTHERS_LAT. Writes an FP register.
    ("fcvt_s_w",  "li    x15, 7",                                  "fcvt.s.w f0, x15"),
    # CONV class with an integer destination: 1.5 -> 1 is inexact, so NX is
    # raised and the only path to FS == Dirty is the fflags write.
    ("fcvt_w_s",  "la x14, fp_a\nflw f3, 8(x14)",                  "fcvt.w.s x11, f3, rtz"),
    # NONCOMP class with an integer destination: a signalling NaN operand
    # raises NV, so again only the fflags write can set FS.
    ("feq_s_snan","la x14, fp_a\nflw f4, 12(x14)\nflw f5, 0(x14)", "feq.s   x11, f4, f5"),
    # Integer to FP register move, CONV class.
    ("fmv_w_x",   "li    x15, 0x3f800000",                         "fmv.w.x f0, x15"),
    # NONCOMP class, FP destination, never raises a flag.
    ("fsgnj_s",   "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",  "fsgnj.s f0, f1, f2"),
    # Explicit FP CSR writes: FS must go Dirty through the fcsr update path.
    ("csrw_fcsr", "li    x15, 0x21",                               "csrw    fcsr, x15"),
    ("csrw_fflags","li   x15, 0x01",                               "csrw    fflags, x15"),
]

# Added 2026-10-03 (issue 1060 follow-up, PREDICTIONS_2026-10-03.md). The cases above are
# unchanged. Each of these also reads mstatus a second time, eight nops after the first read,
# and passes only if the first read equals the second (a stale first read fails even where
# the architecture does not require Dirty). "dirty" cases additionally require Dirty.
# name -> (setup, instruction(s) under test, check)
CASES_2 = [
    # ADDMUL class, fused multiply-add: three source operands.
    ("fmadd_s",   "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)\nflw f3, 8(x14)",
                  "fmadd.s f0, f1, f2, f3", "dirty"),
    ("fnmsub_s",  "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)\nflw f3, 8(x14)",
                  "fnmsub.s f0, f1, f2, f3", "dirty"),
    # NONCOMP class, FP destination.
    ("fmin_s",    "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",  "fmin.s  f0, f1, f2", "dirty"),
    # NONCOMP class, integer destination, no flag raised: the architecture does not require
    # FS to change, so only consistency of the two reads is checked.
    ("fclass_s",  "la x14, fp_a\nflw f1, 0(x14)",                  "fclass.s x11, f1", "settled"),
    ("fmv_x_w",   "la x14, fp_a\nflw f1, 0(x14)",                  "fmv.x.w x11, f1", "settled"),
    # CONV class, integer destination: 1.5 -> 1 is inexact, NX is raised.
    ("fcvt_wu_s", "la x14, fp_a\nflw f3, 8(x14)",                  "fcvt.wu.s x11, f3, rtz", "dirty"),
    # Explicit write of the rounding mode.
    ("csrw_frm",  "li    x15, 0x1",                                 "csrw    frm, x15", "dirty"),
    # Long-latency operation still in flight when an FP load and the mstatus read follow.
    ("fdiv_flw",  "la x14, fp_a\nflw f1, 0(x14)\nflw f2, 4(x14)",
                  "fdiv.s  f0, f1, f2\n    flw     f3, 0(x14)", "dirty"),
    ("fsqrt_flw", "la x14, fp_a\nflw f1, 4(x14)",
                  "fsqrt.s f0, f1\n    flw     f3, 0(x14)", "dirty"),
    # FP load from a misaligned address (two bus transactions; the load stays in EX longer).
    ("flw_misal", "la x14, fp_a",                                   "flw     f0, 2(x14)", "dirty"),
]

CHECK_DIRTY = """    srli    x6, x10, 13
    andi    x6, x6, 3
    li      x7, 3
    bne     x6, x7, report_fail     // FS must read Dirty
    srli    x6, x10, 31
    li      x7, 1
    bne     x6, x7, report_fail     // SD must read 1
    j       report_pass"""

# Second read eight nops later; the first read must equal it in FS and SD.
LATE_READ = "\n    " + "\n    ".join(["nop"] * 8) + "\n    csrr    x19, mstatus"
CHECK_SETTLED = """    li      x7, 0x80006000
    and     x6, x10, x7
    and     x7, x19, x7
    bne     x6, x7, report_fail     // first read must equal the settled read"""

DISTANCES = [0, 1, 2, 8]   # d = 8 is the control: it must pass in every cell

PRINT_ADDR = "0x10000000"
STATUS_ADDR = "0x20000000"

TEMPLATE = r"""// Generated by gen.py -- do not edit by hand.
// Case: {name}, CSR read at distance d = {d}.
// mstatus.FS is set to Initial, the instruction under test is executed, then
// mstatus is read {d} instruction(s) later. PASS requires FS == 2'b11 (Dirty)
// and SD == 1.

    .option norvc
    .section .text.init, "ax"
    .globl _start

_start:
    // Trap handler: any trap is a test error, not a pass.
    la      x5, trap_entry
    csrw    mtvec, x5
    csrw    mstatus, x0             // FS = Off, MIE = 0
    li      x5, (1 << 13)           // FS = Initial so FP instructions decode
    csrs    mstatus, x5
    {nop8}

    // Operand setup. These instructions may dirty FS; FS is reset below.
{setup}
    {nop8}

    // Force FS back to Initial (01) and SD to 0.
    li      x5, (3 << 13)
    csrc    mstatus, x5
    li      x5, (1 << 13)
    csrs    mstatus, x5
    {nop8}

    // ---- measurement window -------------------------------------------
    .balign 64
    {insn}
{gap}
    csrr    x10, mstatus{late}
    // -------------------------------------------------------------------

    mv      x18, x10                // keep the observed mstatus for printing
{check}

trap_entry:
    csrr    x18, mcause
    la      x11, str_trap
    jal     x1, print_str
    mv      x10, x18
    jal     x1, print_hex
    la      x11, str_nl
    jal     x1, print_str
    j       report_fail

report_pass:
    la      x11, str_mstatus
    jal     x1, print_str
    mv      x10, x18
    jal     x1, print_hex
    la      x11, str_nl
    jal     x1, print_str{late_print_pass}
    la      x11, str_pass
    jal     x1, print_str
    li      x1, 123456789
    li      x2, {status}
    sw      x1, 0(x2)
    sw      x0, 4(x2)
self_loop_pass:
    j       self_loop_pass

report_fail:
    la      x11, str_mstatus
    jal     x1, print_str
    mv      x10, x18
    jal     x1, print_hex
    la      x11, str_nl
    jal     x1, print_str{late_print_fail}
    la      x11, str_fail
    jal     x1, print_str
    li      x1, 1
    li      x2, {status}
    sw      x1, 0(x2)
    sw      x1, 4(x2)
self_loop_fail:
    j       self_loop_fail

// x11 = NUL terminated string pointer
print_str:
    li      x28, {printer}
1:  lbu     x29, 0(x11)
    beq     x29, x0, 2f
    sw      x29, 0(x28)
    addi    x11, x11, 1
    j       1b
2:  jalr    x0, 0(x1)

// x10 = 32 bit value, printed as 8 hex digits
print_hex:
    li      x28, {printer}
    li      x30, 28
1:  srl     x29, x10, x30
    andi    x29, x29, 15
    li      x31, 10
    blt     x29, x31, 2f
    addi    x29, x29, 87            // 'a' - 10
    j       3f
2:  addi    x29, x29, 48            // '0'
3:  sw      x29, 0(x28)
    addi    x30, x30, -4
    bge     x30, x0, 1b
    jalr    x0, 0(x1)

    .section .rodata
    .balign 4
fp_a:
    .word   0x3f800000              // 1.0f
    .word   0x40000000              // 2.0f
    .word   0x3fc00000              // 1.5f  (inexact when converted to int)
    .word   0x7f800001              // signalling NaN
str_mstatus:
    .asciz  "RVCP: mstatus = 0x"{late_str}
str_nl:
    .asciz  "\n"
str_trap:
    .asciz  "RVCP: UNEXPECTED TRAP, mcause = 0x"
str_pass:
    .asciz  "\nRVCP-SUMMARY: TEST PASSED - Test File \"{name}_d{d}.S\"\n\n"
str_fail:
    .asciz  "\nRVCP-SUMMARY: TEST FAILED - Test File \"{name}_d{d}.S\"\n\n"
"""


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "src"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*.S"):
        f.unlink()
    nop8 = "\n    ".join(["nop"] * 8)
    n = 0
    late_print = """
    la      x11, str_late
    jal     x1, print_str
    mv      x10, x19
    jal     x1, print_hex
    la      x11, str_nl
    jal     x1, print_str"""
    late_str = '\nstr_late:\n    .asciz  "RVCP: mstatus (8 nops later) = 0x"'
    cases = [(c[0], c[1], c[2], None) for c in CASES] + CASES_2
    for name, setup, insn, check in cases:
        setup_txt = "\n".join("    " + l.strip() for l in setup.splitlines())
        if check is None:    # original cases: text unchanged
            extra = dict(late="", check=CHECK_DIRTY, late_print_pass="", late_print_fail="", late_str="")
        else:
            chk = CHECK_SETTLED + ("\n" + CHECK_DIRTY if check == "dirty" else "\n    j       report_pass")
            extra = dict(late=LATE_READ, check=chk, late_print_pass=late_print,
                         late_print_fail=late_print, late_str=late_str)
        for d in DISTANCES:
            gap = "\n".join(["    nop"] * d)
            (out / ("%s_d%d.S" % (name, d))).write_text(TEMPLATE.format(
                name=name, d=d, setup=setup_txt, gap=gap, insn=insn, nop8=nop8,
                printer=PRINT_ADDR, status=STATUS_ADDR, **extra))
            n += 1
    print("generated %d tests in %s" % (n, out))


if __name__ == "__main__":
    main()
