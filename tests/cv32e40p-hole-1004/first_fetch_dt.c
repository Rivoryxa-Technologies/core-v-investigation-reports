// Directed test for cv32e40p issue #1004 (controller line 399):
// FIRST_FETCH with irq_req_ctrl_i=1 AND debug_req_pending=1 in the same cycle.
// Recipe (from the formal witness): enable timer irq, wfi -> SLEEP, wake on irq,
// and let debug_req_i rise exactly in the FIRST_FETCH cycle that follows the wake.
// The tb debug_req start delay is swept so one iteration lands on that cycle.
#include <stdint.h>
#define PRINT_REG (*(volatile char *)0x10000000)
static void ff_puts(const char *s) { while (*s) PRINT_REG = *s++; }
static void ff_puthex(uint32_t v) { for (int i = 28; i >= 0; i -= 4) { uint32_t d = (v >> i) & 0xf; PRINT_REG = (char)(d < 10 ? '0' + d : 'a' + d - 10); } }
static void ff_kv(const char *k, uint32_t v) { ff_puts(k); ff_puthex(v); PRINT_REG = ' '; }
#define TIMER_REG (*(volatile uint32_t *)0x15000000)
#define TIMER_VAL (*(volatile uint32_t *)0x15000004)
#define DBG_CTRL  (*(volatile uint32_t *)0x15000008)
volatile uint32_t glb_irq_count = 0;    // incremented by m_timer_irq_handler (dbg.S)
volatile uint32_t glb_debug_count = 0;  // incremented by the debugger stub (dbg.S)
extern char ff_vectors[];
void trap_report(uint32_t mcause, uint32_t mepc, uint32_t mtval) {
    ff_puts("first_fetch_dt TRAP "); ff_kv("mcause=", mcause); ff_kv("mepc=", mepc); ff_kv("mtval=", mtval); PRINT_REG = '\n';
    *(volatile uint32_t *)0x20000000 = 1;   // TEST_FAILED -> tb exits
    for (;;) ;
}
int main(void) {
    __asm__ volatile("csrw mtvec, %0" : : "r"((uint32_t)ff_vectors | 1u));   // vectored, own table
    { uint32_t mt; __asm__ volatile("csrr %0, mtvec" : "=r"(mt)); ff_kv("mtvec=", mt); ff_kv("vectors=", (uint32_t)ff_vectors);
      ff_kv("word@dm_halt=", *(volatile uint32_t *)0x1A110800); ff_kv("word@dm_halt+4=", *(volatile uint32_t *)0x1A110804); PRINT_REG = '\n'; }
    __asm__ volatile("csrs mie, %0" : : "r"(1u << 7));       // machine timer irq (tb timer drives irq bit 7)
    __asm__ volatile("csrs mstatus, %0" : : "r"(1u << 3));   // MIE
    for (uint32_t k = 0; k < 32; k++) {
        uint32_t irq0 = glb_irq_count, dbg0 = glb_debug_count;
        ff_kv("k=", k);
        TIMER_REG = 1u << 7;
        // debug_req: value=1 (bit31), pulse (bit30), width 2 cycles (bits 28:16), start delay = 48+k cycles (bits 14:0)
        // timer irq fires 64 cycles after the TIMER_VAL store below (a few cycles after the DBG_CTRL store),
        // so the sweep k=0..31 moves debug_req from ~12 cycles before the wake to ~19 cycles after it.
        DBG_CTRL = (1u << 31) | (1u << 30) | (2u << 16) | (48u + k);
        TIMER_VAL = 64;
        __asm__ volatile("wfi");                               // sleeps until the timer irq wakes the core
        for (volatile int d = 0; d < 400; d++)                 // let both events land (bounded)
            if (glb_irq_count != irq0 && glb_debug_count != dbg0) break;
        ff_kv("irq=", glb_irq_count - irq0); ff_kv("dbg=", glb_debug_count - dbg0); PRINT_REG = '\n';
    }
    ff_puts("first_fetch_dt done "); ff_kv("irq=", glb_irq_count); ff_kv("dbg=", glb_debug_count); PRINT_REG = '\n';
    return 0;
}
