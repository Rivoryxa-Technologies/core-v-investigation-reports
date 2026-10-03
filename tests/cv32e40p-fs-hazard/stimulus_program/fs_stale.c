/* Exposure program for the stale mstatus.FS defect (issue 1060, RTL state base on F0): a floating-point
   instruction that writes an FP register or the FP flags, immediately followed by a read of mstatus,
   must show FS = Dirty (and SD set). Before each pair the program returns FS to Initial. Built for the
   stimulus support layer (interrupts and debug requests arrive at random times; an interrupt that falls
   between the two instructions hides the defect for that pair only). The value that the program
   accumulates comes from a host build that applies the architectural rule, never from the design. */
#include <stdint.h>
#ifndef EXPECTED
#define EXPECTED 0
#endif

#define FS_MASK 0x6000u
#define FS_INITIAL 0x2000u
#define FS_DIRTY_BITS 0x80006000u        /* SD, FS = 3 */

static float data[4] = {1.5f, -2.25f, 3.0f, 0.5f};

uint32_t compute(void) {
    uint32_t h = 0;
    for (int i = 0; i < 400; i++) {
        uint32_t m;
#ifdef HOST
        m = FS_DIRTY_BITS;
#else
        float *p = &data[i & 3];
        uint32_t k = (uint32_t)i % 3u;
        asm volatile("csrc mstatus, %0" :: "r"(FS_MASK));
        asm volatile("csrs mstatus, %0" :: "r"(FS_INITIAL));
        if (k == 0) {                    /* load into an FP register, then read mstatus */
            asm volatile("flw ft0, 0(%1)\n\tcsrr %0, mstatus" : "=r"(m) : "r"(p) : "ft0");
        } else if (k == 1) {             /* FP add (writes the register and the flags), then read mstatus */
            asm volatile("flw ft1, 0(%1)\n\tcsrc mstatus, %2\n\tcsrs mstatus, %3\n\tfadd.s ft0, ft1, ft1\n\tcsrr %0, mstatus"
                         : "=&r"(m) : "r"(p), "r"(FS_MASK), "r"(FS_INITIAL) : "ft0", "ft1");
        } else {                         /* flw followed by a dependent integer op in between, then read */
            asm volatile("flw ft0, 0(%1)\n\taddi %0, %1, 1\n\tcsrr %0, mstatus" : "=&r"(m) : "r"(p) : "ft0");
        }
#endif
        h = h * 31u + (m & FS_DIRTY_BITS) + (uint32_t)i;
    }
    return h;
}
#ifdef HOST
#include <stdio.h>
int main(void) { printf("0x%08xu\n", compute()); return 0; }
#else
int test_main(void) { return compute() == EXPECTED ? 0 : 1; }
#endif
