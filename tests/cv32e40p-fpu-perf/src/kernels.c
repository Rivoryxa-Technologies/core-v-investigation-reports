/* FPU pipeline-depth performance kernels for CV32E40P.

   Built once per kernel (-DKERNEL=K_<name>) and per march. Each program
   initialises its inputs, reads mcycle and minstret around one call of the
   kernel, prints

     FPUPERF kernel=<name> cycles=<n> instret=<n> checksum=0x<hex>

   and passes only if the checksum equals the host reference (-DEXPECTED=...,
   computed by the same file built with -DHOST on the build machine).

   Multiply-adds are written as __builtin_fmaf and both builds use
   -ffp-contract=off, so the RISC-V build has the fmadd.s that GCC would form
   by contraction and the host computes the same fused rounding. Inputs are
   k / 65536 - 0.5 for 16-bit k, exact in single precision. */
#include <stdint.h>

#define K_MATMUL  1
#define K_DOT     2
#define K_AXPY    3
#define K_FIR     4
#define K_NORM    5
#define K_CONTROL 6

#define N_MM   16
#define N_VEC  1024
#define N_TAP  16
#define N_OUT  256
#define N_NORM 128
#define N_CRC  1024
#define N_SORT 64

#ifdef HOST
#include <stdio.h>
#include <math.h>
#define FMA(a, b, c) fmaf((a), (b), (c))
#define SQRT(a)      sqrtf(a)
#else
#define FMA(a, b, c) __builtin_fmaf((a), (b), (c))
#define SQRT(a)      __builtin_sqrtf(a)
#endif

#define NOINLINE __attribute__((noinline))

static uint32_t lcg_state;
static uint32_t lcg(void) { lcg_state = lcg_state * 1664525u + 1013904223u; return lcg_state >> 16; }
static float frand(void) { return (float)(int)lcg() * (1.0f / 65536.0f) - 0.5f; }

static uint32_t mix(uint32_t h, uint32_t v) { return (h ^ v) * 16777619u + (h >> 15); }
static uint32_t fbits(float f) { union { float f; uint32_t u; } x = { f }; return x.u; }
static uint32_t hash_f(const float *p, int n) { uint32_t h = 2166136261u; for (int i = 0; i < n; i++) h = mix(h, fbits(p[i])); return h; }

/* ---- kernels ---------------------------------------------------------- */

static float A[N_MM * N_MM], B[N_MM * N_MM], C[N_MM * N_MM];
static float X[N_VEC], Y[N_VEC];
static float H[N_TAP], XS[N_OUT + N_TAP], YS[N_OUT];
static float V[3 * N_NORM];
static uint8_t BYTES[N_CRC];
static int32_t S[N_SORT];
static float dot_result, axpy_a;

/* (a) 16x16 matrix product, inner product kept in one register. */
static NOINLINE void matmul(void)
{
  for (int i = 0; i < N_MM; i++)
    for (int j = 0; j < N_MM; j++) {
      float acc = 0.0f;
      for (int k = 0; k < N_MM; k++)
        acc = FMA(A[i * N_MM + k], B[k * N_MM + j], acc);
      C[i * N_MM + j] = acc;
    }
}

/* (b) dot product, unrolled by four into ONE accumulator: four back-to-back
   dependent fmadd.s per iteration. */
static NOINLINE void dot(void)
{
  float acc = 0.0f;
  for (int i = 0; i < N_VEC; i += 4) {
    acc = FMA(X[i + 0], Y[i + 0], acc);
    acc = FMA(X[i + 1], Y[i + 1], acc);
    acc = FMA(X[i + 2], Y[i + 2], acc);
    acc = FMA(X[i + 3], Y[i + 3], acc);
  }
  dot_result = acc;
}

/* (c) y = a*x + y, unrolled by four: four independent fmadd.s per iteration. */
static NOINLINE void axpy(void)
{
  float a = axpy_a;
  for (int i = 0; i < N_VEC; i += 4) {
    float y0 = FMA(a, X[i + 0], Y[i + 0]);
    float y1 = FMA(a, X[i + 1], Y[i + 1]);
    float y2 = FMA(a, X[i + 2], Y[i + 2]);
    float y3 = FMA(a, X[i + 3], Y[i + 3]);
    Y[i + 0] = y0; Y[i + 1] = y1; Y[i + 2] = y2; Y[i + 3] = y3;
  }
}

/* (d) 16-tap FIR filter over 256 outputs, plain inner loop. */
static NOINLINE void fir(void)
{
  for (int n = 0; n < N_OUT; n++) {
    float acc = 0.0f;
    for (int k = 0; k < N_TAP; k++)
      acc = FMA(H[k], XS[n + k], acc);
    YS[n] = acc;
  }
}

/* (e) normalise 128 three-vectors: one fsqrt.s and one fdiv.s per vector. */
static NOINLINE void norm(void)
{
  for (int i = 0; i < N_NORM; i++) {
    float x = V[3 * i], y = V[3 * i + 1], z = V[3 * i + 2];
    float s = FMA(z, z, FMA(y, y, x * x));
    float r = 1.0f / SQRT(s);
    V[3 * i] = x * r; V[3 * i + 1] = y * r; V[3 * i + 2] = z * r;
  }
}

/* (f) integer only: bitwise CRC-32 of 1 KiB, then insertion sort of 64 words. */
static uint32_t crc_result;
static NOINLINE void control(void)
{
  uint32_t c = 0xffffffffu;
  for (int i = 0; i < N_CRC; i++) {
    c ^= BYTES[i];
    for (int b = 0; b < 8; b++)
      c = (c >> 1) ^ (0xedb88320u & -(c & 1u));
  }
  crc_result = ~c;
  for (int i = 1; i < N_SORT; i++) {
    int32_t v = S[i];
    int j = i - 1;
    while (j >= 0 && S[j] > v) { S[j + 1] = S[j]; j--; }
    S[j + 1] = v;
  }
}

/* ---- set-up and checksums --------------------------------------------- */

static void init(int k)
{
  lcg_state = 12345u + (uint32_t)k;
  if (k == K_CONTROL) {
    for (int i = 0; i < N_CRC; i++) BYTES[i] = (uint8_t)lcg();
    for (int i = 0; i < N_SORT; i++) S[i] = (int32_t)lcg() - 32768;
    return;
  }
#if !defined(NO_FLOAT)
  if (k == K_MATMUL) for (int i = 0; i < N_MM * N_MM; i++) { A[i] = frand(); B[i] = frand(); }
  if (k == K_DOT || k == K_AXPY) { for (int i = 0; i < N_VEC; i++) { X[i] = frand(); Y[i] = frand(); } axpy_a = frand(); }
  if (k == K_FIR) { for (int i = 0; i < N_TAP; i++) H[i] = frand(); for (int i = 0; i < N_OUT + N_TAP; i++) XS[i] = frand(); }
  if (k == K_NORM) for (int i = 0; i < 3 * N_NORM; i++) V[i] = frand() + 0.75f;
#endif
}

static void run(int k)
{
  switch (k) {
  case K_MATMUL: matmul(); break;
  case K_DOT: dot(); break;
  case K_AXPY: axpy(); break;
  case K_FIR: fir(); break;
  case K_NORM: norm(); break;
  case K_CONTROL: control(); break;
  }
}

static uint32_t checksum(int k)
{
  uint32_t h = 2166136261u;
  switch (k) {
  case K_MATMUL: return hash_f(C, N_MM * N_MM);
  case K_DOT: return mix(h, fbits(dot_result));
  case K_AXPY: return hash_f(Y, N_VEC);
  case K_FIR: return hash_f(YS, N_OUT);
  case K_NORM: return hash_f(V, 3 * N_NORM);
  case K_CONTROL: h = mix(h, crc_result); for (int i = 0; i < N_SORT; i++) h = mix(h, (uint32_t)S[i]); return h;
  }
  return 0;
}

static const char *const names[] = { "", "matmul", "dot", "axpy", "fir", "norm", "control" };

#ifdef HOST
int main(void)
{
  for (int k = K_MATMUL; k <= K_CONTROL; k++) {
    init(k); run(k);
    printf("%s 0x%08x\n", names[k], checksum(k));
  }
  return 0;
}
#else
#define PRINT_ADDR ((volatile uint32_t *)0x10000000u)
static void putch(char c) { *PRINT_ADDR = (uint32_t)(uint8_t)c; }
static void puts_(const char *s) { while (*s) putch(*s++); }
static void putdec(uint32_t v) { char b[11]; int n = 0; do { b[n++] = (char)('0' + v % 10); v /= 10; } while (v); while (n) putch(b[--n]); }
static void puthex(uint32_t v) { for (int i = 28; i >= 0; i -= 4) putch("0123456789abcdef"[(v >> i) & 15]); }

static inline uint32_t rd_mcycle(void) { uint32_t v; __asm__ volatile("csrr %0, mcycle" : "=r"(v) :: "memory"); return v; }
static inline uint32_t rd_minstret(void) { uint32_t v; __asm__ volatile("csrr %0, minstret" : "=r"(v) :: "memory"); return v; }

void report_trap(uint32_t cause, uint32_t epc)
{
  puts_("FPUPERF trap mcause=0x"); puthex(cause); puts_(" mepc=0x"); puthex(epc); putch('\n');
  puts_("RVCP-SUMMARY: TEST FAILED\n");
}

int main(void)
{
  init(KERNEL);
  uint32_t c0 = rd_mcycle(), i0 = rd_minstret();
  run(KERNEL);
  uint32_t c1 = rd_mcycle(), i1 = rd_minstret();
  uint32_t sum = checksum(KERNEL);
  puts_("FPUPERF kernel="); puts_(names[KERNEL]);
  puts_(" cycles="); putdec(c1 - c0);
  puts_(" instret="); putdec(i1 - i0);
  puts_(" checksum=0x"); puthex(sum);
  puts_(" expected=0x"); puthex(EXPECTED);
  putch('\n');
  int ok = sum == (uint32_t)EXPECTED;
  puts_(ok ? "RVCP-SUMMARY: TEST PASSED\n" : "RVCP-SUMMARY: TEST FAILED\n");
  return !ok;
}
#endif
