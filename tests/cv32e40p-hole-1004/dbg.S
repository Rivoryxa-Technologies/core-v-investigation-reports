// Debugger stub and timer irq handler for first_fetch_dt (cv32e40p #1004 directed test)
.section .debugger, "ax"
.global _debugger_start
.global glb_debug_count
_debugger_start:
        csrw dscratch, a0
        csrw 0x7b3, t0              // dscratch1
        la   a0, glb_debug_count
        lw   t0, 0(a0)
        addi t0, t0, 1
        sw   t0, 0(a0)
        csrr t0, 0x7b3
        csrr a0, dscratch
        dret

.section .text
.global m_timer_irq_handler
.global glb_irq_count
m_timer_irq_handler:
        addi sp, sp, -8
        sw   a0, 0(sp)
        sw   t0, 4(sp)
        la   a0, glb_irq_count
        lw   t0, 0(a0)
        addi t0, t0, 1
        sw   t0, 0(a0)
        lw   a0, 0(sp)
        lw   t0, 4(sp)
        addi sp, sp, 8
        mret

// Own vector table (vectored mtvec): entry 7 -> timer handler, everything else -> trap reporter.
.section .text
.option push
.option norvc               // every entry must be a 4-byte jump (vectored mtvec = base + 4*id)
.balign 256
.global ff_vectors
ff_vectors:
        j ff_trap               // 0: exceptions
        j ff_trap               // 1
        j ff_trap               // 2
        j ff_trap               // 3
        j ff_trap               // 4
        j ff_trap               // 5
        j ff_trap               // 6
        j m_timer_irq_handler   // 7: machine timer
        .rept 24
        j ff_trap
        .endr
.option pop
.global ff_trap
ff_trap:
        csrr a0, mcause
        csrr a1, mepc
        csrr a2, mtval
        la   sp, __stack_top_ff
        call trap_report        // never returns
        j ff_trap
.section .bss
.balign 16
        .space 512
__stack_top_ff:
