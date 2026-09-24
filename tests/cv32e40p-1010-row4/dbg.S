// #1010 condition row 4 directed test, portable version: no .debugger section.
// The debug handler lives in .text and main() copies it to RAM 0x00110800 before the debug request.
// The core fetches dm_halt_addr 0x1A110800; testbenches that keep only the low 22 address bits read RAM 0x110800.
// The handler must be position independent: data addresses are absolute (lui/addi), never la/auipc.
// STEP_BIT: 4 sets dcsr.step (test), 0 leaves it clear (control).
#ifndef STEP_BIT
#define STEP_BIT 4
#endif
.section .text
.option push
.option norvc
.balign 4
.global dbg_handler_start
.global dbg_handler_end
dbg_handler_start:
        csrw dscratch, a0
        csrw 0x7b3, t0              // dscratch1
        li   t0, STEP_BIT
        csrs 0x7b0, t0              // dcsr.step on (test) while in debug mode
        li   a0, 0
        .word ((10 << 20) | (4 << 15) | (0x4 << 12) | (0x6 << 8) | (0 << 7) | 0x2b)   // cv.setupi loop0, end +4 words, 10 iterations
        addi a0, a0, 1
        addi a0, a0, 1
        addi a0, a0, 1
        nop
        li   t0, 4
        csrc 0x7b0, t0              // dcsr.step off before leaving debug mode
        lui  t0, %hi(glb_loop_acc)
        sw   a0, %lo(glb_loop_acc)(t0)
        lui  t0, %hi(glb_debug_count)
        lw   a0, %lo(glb_debug_count)(t0)
        addi a0, a0, 1
        sw   a0, %lo(glb_debug_count)(t0)
        csrr t0, 0x7b3
        csrr a0, dscratch
        dret
dbg_handler_end:
.option pop
