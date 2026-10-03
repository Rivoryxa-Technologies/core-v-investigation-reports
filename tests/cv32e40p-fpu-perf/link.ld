/* Minimal bare-metal link script for the CV32E40P Verilator core testbench.
   Memory map matches tb/core/mm_ram.sv (RAM_ADDR_WIDTH = 22).
   The entry point is taken from the ELF header by tb_top.sv and driven on
   boot_addr_i, so .text must start at the entry symbol.
   Same as tests/fs_hazard/link.ld plus a 16 KiB stack after .bss for the C kernels. */
OUTPUT_ARCH( "riscv" )
ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 0x00400000
}

SECTIONS
{
  . = 0x00000080;
  .text . : { *(.text.init) *(.text) *(.text.*) } > ram
  . = ALIGN(64);
  .rodata . : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) } > ram
  . = ALIGN(64);
  __global_pointer$ = . + 0x800;
  .data . : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) } > ram
  . = ALIGN(64);
  __bss_start = .;
  .bss . : { *(.bss) *(.bss.*) *(.sbss) *(.sbss.*) *(COMMON) } > ram
  . = ALIGN(64);
  __bss_end = .;
  . = . + 0x4000;
  _stack_top = .;
  _end = .;
}
