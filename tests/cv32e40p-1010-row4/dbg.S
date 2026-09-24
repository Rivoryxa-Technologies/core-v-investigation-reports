// #1010 condition row 4 directed test: in debug mode, set dcsr.step and run a PULP hardware loop,
// so the controller sits in DECODE_HWLOOP with debug_single_step_i=1 and debug_mode_q=1.
// STEP_BIT is 4 (dcsr.step) in the test and 0 in the control.
// cv.setupi L, uimmS, uimmL : bits[31:20]=count, [19:15]=end offset in words, funct3=100, [11:8]=0110, [7]=L, opcode 0x2b
.section .debugger, "ax"
.global _debugger_start
.global glb_debug_count
.global glb_loop_acc
_debugger_start:
        csrw dscratch, a0
        csrw 0x7b3, t0              // dscratch1
        li   t0, STEP_BIT
        csrs 0x7b0, t0              // dcsr.step (bit 2) on, in debug mode
        li   a0, 0
.option push
.option norvc
.balign 4
        .word ((10 << 20) | (4 << 15) | (0x4 << 12) | (0x6 << 8) | (0 << 7) | 0x2b)   // cv.setupi loop0, end +4 words, 10 iterations
        addi a0, a0, 1
        addi a0, a0, 1
        addi a0, a0, 1
        nop
.option pop
        li   t0, 4
        csrc 0x7b0, t0              // dcsr.step off before leaving debug mode
        la   t0, glb_loop_acc
        sw   a0, 0(t0)
        la   a0, glb_debug_count
        lw   t0, 0(a0)
        addi t0, t0, 1
        sw   t0, 0(a0)
        csrr t0, 0x7b3
        csrr a0, dscratch
        dret
