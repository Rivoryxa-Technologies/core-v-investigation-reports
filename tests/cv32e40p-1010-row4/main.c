// #1010 condition row 4 directed test driver: one debug request, then report.
#include <stdio.h>
#include <stdint.h>
#define DBG_CTRL (*(volatile uint32_t *)0x15000008)
volatile uint32_t glb_debug_count = 0;
volatile uint32_t glb_loop_acc = 0;
int main(void) {
    // debug_req: value=1 (bit31), pulse (bit30), width 2 cycles (bits 28:16), start delay 20 cycles
    DBG_CTRL = (1u << 31) | (1u << 30) | (2u << 16) | 20u;
    for (volatile int d = 0; d < 2000 && glb_debug_count == 0; d++) ;
    printf("row4 test: debug entries=%u loop acc=%u (expect 1 and 30)\n", (unsigned)glb_debug_count, (unsigned)glb_loop_acc);
    return (glb_debug_count == 1 && glb_loop_acc == 30) ? 0 : 1;
}
