/* Start-up for the fpu_perf kernels on the CV32E40P Verilator core testbench.
   Sets the stack, clears .bss, sets mstatus.FS to Initial (the core resets it
   to Off, so every F instruction would trap; on Zfinx and I0 builds FS is
   hardwired to zero and the write has no effect), clears mcountinhibit so that
   mcycle and minstret count (reset value 0xd inhibits them), calls main and
   reports its return value through the testbench status register:
   0x20000000 <- 123456789 is a pass, 1 is a fail. Any trap is a fail. */
    .section .text.init
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, _stack_top
    la      t0, trap
    csrw    mtvec, t0
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  li      t0, 0x2000
    csrs    mstatus, t0
    csrwi   mcountinhibit, 0
    call    main
    li      t1, 0x20000000
    li      t0, 123456789
    beqz    a0, 3f
    li      t0, 1
3:  sw      t0, 0(t1)
4:  j       4b

    .align 2
trap:
    csrr    a0, mcause
    csrr    a1, mepc
    call    report_trap
    li      t1, 0x20000000
    li      t0, 1
    sw      t0, 0(t1)
5:  j       5b
