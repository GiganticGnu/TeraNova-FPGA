/******************************************************************************
 * 50x50 matrix multiplication on the PL (accu_to_DDR design, ZCU102)
 * LADDER STEP 4: BURST DATA PATH  (branch burst-datapath)
 *
 * Hardware of this step (scripts/6_burst_datapath.tcl):
 *   - A, B and C are in the PS DDR at fixed addresses (DDR high, which the
 *     linker script does not use):
 *         A  0x8_0000_0000   B  0x8_0000_5000   C  0x8_0000_A000
 *   - the partitioner (v7) reads A and B itself, in bursts, through the
 *     S_AXI_HP0 port of the PS; RAM_INTERFACE writes C through the same port
 *   - start = GPIO toggle, done = pl_ps_irq0 interrupt + GPIO channel 2,
 *     exactly as in the baseline
 *
 * HP0 is NOT cache coherent, so the CPU has to:
 *   - FLUSH A and B from its data cache before start (else the PL reads old
 *     data from the DDR)
 *   - INVALIDATE C after done (else the CPU reads old data from its cache)
 *   C is also flushed+invalidated before start, so no dirty cache line of C
 *   can be written back on top of what the PL writes.
 *
 * Phases per run (same columns as the baseline CSV, so the ladder can compare):
 *   "load"      = flushing A and B (40 KB) from the cache   [was: 10 000 BRAM writes]
 *   "compute"   = start -> done
 *   "read-back" = invalidating C (20 KB) + reading C         [was: 2500 PL-DDR4 reads]
 * A and B are re-written by the CPU before every run (not timed), so every
 * flush really has dirty lines to write, like data the CPU has just produced.
 ******************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xparameters_ps.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xgpio.h"
#include "xstatus.h"
#include "xiltimer.h"

/* ----------------------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------------------- */
#define N                    50          /* matrix is N x N                  */
#define N_RUNS               10          /* PL runs per execution            */
#define N_CPU_REPEATS        5           /* CPU reference repetitions        */
#define MAT_BYTES            (N * N * sizeof(uint64_t))   /* 20 000 bytes    */

/* must match A_BASE / B_BASE / DDR_BASEADDRESS in the block design */
#define A_ADDR               0x800000000ULL
#define B_ADDR               0x800005000ULL
#define C_ADDR               0x80000A000ULL

#define GPIO_BASE            XPAR_XGPIO_0_BASEADDR
#define GPIO_START_CH        1           /* output: start toggle             */
#define GPIO_DONE_CH         2           /* input : done level               */
#define DONE_IRQ_ID          XPS_FPGA0_INT_ID                 /* pl_ps_irq0[0] = 121 */
#define TIMEOUT_US           1000000ULL  /* give up waiting after 1 s        */

/* ----------------------------------------------------------------------------
 * Globals
 * ------------------------------------------------------------------------- */
static XGpio   Gpio;
static XScuGic Intc;

static volatile int   irq_received = 0;
static volatile XTime irq_time     = 0;
static u32 start_level = 0;              /* current level of the start toggle */

static uint64_t *const A = (uint64_t *)(UINTPTR)A_ADDR;   /* shared with the PL */
static uint64_t *const B = (uint64_t *)(UINTPTR)B_ADDR;
static uint64_t *const C = (uint64_t *)(UINTPTR)C_ADDR;
static uint64_t *C_ref;
static uint64_t C_hw[N * N];

/* ----------------------------------------------------------------------------
 * Timing helpers
 * ------------------------------------------------------------------------- */
static uint64_t ticks_to_ns(XTime t) {
    return ((uint64_t)t * 1000000000ULL) / COUNTS_PER_SECOND;
}
static uint64_t ticks_to_us(XTime t) {
    return ((uint64_t)t * 1000000ULL) / COUNTS_PER_SECOND;
}
/* print nanoseconds as microseconds with 2 decimals, e.g. 1234567 -> "1234.57" */
static void print_us(uint64_t ns) {
    uint64_t r = (ns + 5) / 10;          /* hundredths of a microsecond */
    printf("%6llu.%02llu", (unsigned long long)(r / 100), (unsigned long long)(r % 100));
}

/* wait until all outstanding memory accesses are complete */
static inline void barrier(void) {
    __asm__ volatile("dsb sy" ::: "memory");
}

typedef struct {
    uint64_t min, max, sum;
    int n;
} stat_t;

static void stat_add(stat_t *s, uint64_t v) {
    if (s->n == 0 || v < s->min) s->min = v;
    if (s->n == 0 || v > s->max) s->max = v;
    s->sum += v;
    s->n++;
}

static void stat_print(const char *name, const stat_t *s) {
    printf("%-34s", name);
    if (s->n == 0) { printf("   (no valid runs)\n"); return; }
    print_us(s->min);  printf("  ");
    print_us(s->sum / (uint64_t)s->n); printf("  ");
    print_us(s->max);  printf("\n");
}

/* ----------------------------------------------------------------------------
 * Interrupt
 * ------------------------------------------------------------------------- */
static void done_isr(void *ref) {
    (void)ref;
    XTime_GetTime((XTime *)&irq_time);
    irq_received = 1;
    XScuGic_Disable(&Intc, DONE_IRQ_ID);   /* one interrupt per run */
}

static int init_interrupts(void) {
    XScuGic_Config *cfg = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (cfg == NULL) return XST_FAILURE;
    if (XScuGic_CfgInitialize(&Intc, cfg, cfg->CpuBaseAddress) != XST_SUCCESS)
        return XST_FAILURE;

    /* priority 0xA0, trigger 0x3 = rising edge of 'done' */
    XScuGic_SetPriorityTriggerType(&Intc, DONE_IRQ_ID, 0xA0, 0x3);
    if (XScuGic_Connect(&Intc, DONE_IRQ_ID, (Xil_InterruptHandler)done_isr, NULL) != XST_SUCCESS)
        return XST_FAILURE;

    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler, &Intc);
    Xil_ExceptionEnable();
    return XST_SUCCESS;
}

/* ----------------------------------------------------------------------------
 * Data
 * ------------------------------------------------------------------------- */
static void fill_test_matrices(void) {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            A[i * N + j] = (uint64_t)(i * N + j + 1);
            B[i * N + j] = (uint64_t)(i * N + j + 2);
        }
}

static void cpu_reference(void) {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            uint64_t sum = 0;
            for (int k = 0; k < N; k++) sum += A[i * N + k] * B[k * N + j];
            C_ref[i * N + j] = sum;
        }
}

/* The CPU can reach the three buffers and they are really in the DDR:
 * write a pattern, flush, invalidate, read it back. */
static int check_buffers(void) {
    uint64_t *buf[3] = {A, B, C};
    int bad = 0;
    for (int b = 0; b < 3; b++) {
        for (int k = 0; k < N * N; k++) buf[b][k] = 0xA5A5000000000000ULL ^ ((uint64_t)b << 40) ^ (uint64_t)k;
        Xil_DCacheFlushRange((INTPTR)buf[b], MAT_BYTES);
        Xil_DCacheInvalidateRange((INTPTR)buf[b], MAT_BYTES);
        for (int k = 0; k < N * N; k++)
            if (buf[b][k] != (0xA5A5000000000000ULL ^ ((uint64_t)b << 40) ^ (uint64_t)k)) bad++;
    }
    return bad;
}

/* ----------------------------------------------------------------------------
 * One complete run on the PL. Returns the number of result mismatches,
 * or -1 if the run could not complete. Phase times (ns) are returned via t_ns,
 * the three parts of the CPU work via t_flush / t_inval / t_read.
 * ------------------------------------------------------------------------- */
enum { PH_LOAD, PH_COMPUTE, PH_READBACK, PH_TOTAL, PH_COUNT };

static int run_once(int run, uint64_t t_ns[PH_COUNT], uint64_t part_ns[3], int *polled) {
    XTime t0, t1, t2, t3, t4, t5;
    *polled = 0;

    /* not timed: the CPU produces A and B (dirty in its cache) and clears C,
     * so a run that writes nothing cannot pass */
    fill_test_matrices();
    memset(C, 0, MAT_BYTES);
    Xil_DCacheFlushRange((INTPTR)C, MAT_BYTES);   /* C: clean + not cached */

    /* 1. "load": push A and B from the cache to the DDR */
    XTime_GetTime(&t0);
    Xil_DCacheFlushRange((INTPTR)A, MAT_BYTES);
    Xil_DCacheFlushRange((INTPTR)B, MAT_BYTES);
    XTime_GetTime(&t1);

    /* 2. start: toggle the start GPIO (toggle2pulse makes a start pulse) */
    irq_received = 0;
    int seen_low = ((XGpio_DiscreteRead(&Gpio, GPIO_DONE_CH) & 1u) == 0);
    XScuGic_Enable(&Intc, DONE_IRQ_ID);
    start_level ^= 1u;
    XTime_GetTime(&t2);
    XGpio_DiscreteWrite(&Gpio, GPIO_START_CH, start_level);

    /* 3. wait for done: interrupt (exact) and GPIO poll (+-1 us), as in the baseline */
    XTime now, t_poll = 0;
    do {
        XTime_GetTime(&now);
        if (!t_poll) {
            u32 d = XGpio_DiscreteRead(&Gpio, GPIO_DONE_CH) & 1u;
            if (!d)            seen_low = 1;
            else if (seen_low) t_poll = now;
        }
        if (t_poll && ticks_to_us(now - t_poll) > 100) break;
    } while (!irq_received && ticks_to_us(now - t2) < TIMEOUT_US);

    if (irq_received) {
        t3 = irq_time;
    } else if (t_poll) {
        t3 = t_poll;
        *polled = 1;
    } else {
        u32 done_level = XGpio_DiscreteRead(&Gpio, GPIO_DONE_CH) & 1u;
        printf("Run %2d: no done after %llu us (no interrupt, no rise on GPIO2), done = %u\n", run,
               (unsigned long long)ticks_to_us(now - t2), (unsigned)done_level);
        if (!done_level) return -1;
        printf("        done is high but its rise was not seen; checking the result, compute time not valid.\n");
        t3 = now;
        *polled = 2;
    }

    /* 4. read-back: drop C from the cache, then read it from the DDR */
    XTime_GetTime(&t4);
    Xil_DCacheInvalidateRange((INTPTR)C, MAT_BYTES);
    XTime_GetTime(&t5);
    for (int k = 0; k < N * N; k++) C_hw[k] = C[k];
    XTime t6; XTime_GetTime(&t6);

    int errors = 0;
    for (int k = 0; k < N * N; k++) {
        if (C_hw[k] != C_ref[k]) {
            if (errors < 5)
                printf("        mismatch C[%d][%d]: got %llu expected %llu\n", k / N, k % N,
                       (unsigned long long)C_hw[k], (unsigned long long)C_ref[k]);
            errors++;
        }
    }

    part_ns[0] = ticks_to_ns(t1 - t0);     /* flush A+B      */
    part_ns[1] = ticks_to_ns(t5 - t4);     /* invalidate C   */
    part_ns[2] = ticks_to_ns(t6 - t5);     /* read 2500 x C  */
    t_ns[PH_LOAD]     = part_ns[0];
    t_ns[PH_COMPUTE]  = ticks_to_ns(t3 - t2);
    t_ns[PH_READBACK] = part_ns[1] + part_ns[2];
    t_ns[PH_TOTAL]    = t_ns[PH_LOAD] + t_ns[PH_COMPUTE] + t_ns[PH_READBACK];

    printf("Run %2d: flush ", run);        print_us(t_ns[PH_LOAD]);
    printf("  compute ");                  print_us(t_ns[PH_COMPUTE]);
    printf("%s", *polled == 1 ? " (GPIO)" : *polled == 2 ? " (n/a) " : "");
    printf("  inval+read ");               print_us(t_ns[PH_READBACK]);
    printf("  total ");                    print_us(t_ns[PH_TOTAL]);
    printf("  us  %s\n", errors ? "FAILED" : "PASSED");

    /* same columns as the baseline CSV ... */
    printf("CSV,run,%d,%llu,%llu,%llu,%llu,%d,%d\n", run,
           (unsigned long long)t_ns[PH_LOAD], (unsigned long long)t_ns[PH_COMPUTE],
           (unsigned long long)t_ns[PH_READBACK], (unsigned long long)t_ns[PH_TOTAL],
           errors, *polled);
    /* ... plus the split of the CPU work (ns): flush A+B, invalidate C, read C */
    printf("CSV,burst,%d,%llu,%llu,%llu\n", run, (unsigned long long)part_ns[0],
           (unsigned long long)part_ns[1], (unsigned long long)part_ns[2]);
    return errors;
}

/* ------------------------------------------------------------------------- */
int main(void) {
    init_platform();
    printf("\n50x50 matrix multiplication on the PL - LADDER STEP 4: BURST DATA PATH\n");
#if defined(__OPTIMIZE__)
    printf("Build: optimised (-O1 or higher)\n");
#else
    printf("Build: NOT optimised (-O0)\n");
#endif
    printf("Timer: %llu ticks per second (%llu ns per tick)\n",
           (unsigned long long)COUNTS_PER_SECOND,
           (unsigned long long)(1000000000ULL / COUNTS_PER_SECOND));
    printf("Buffers in PS DDR: A 0x%llx  B 0x%llx  C 0x%llx\n",
           (unsigned long long)A_ADDR, (unsigned long long)B_ADDR, (unsigned long long)C_ADDR);

    int bad = check_buffers();
    if (bad) { printf("Buffer check FAILED (%d words wrong) - is DDR high mapped?\n", bad); return XST_FAILURE; }
    printf("Buffer check: CPU can write, flush, invalidate and read A, B and C (ok)\n");

    C_ref = (uint64_t *)malloc(MAT_BYTES);
    if (!C_ref) { printf("malloc failed\n"); return XST_FAILURE; }

    if (XGpio_Initialize(&Gpio, GPIO_BASE) != XST_SUCCESS) {
        printf("GPIO init failed\n"); return XST_FAILURE;
    }
    start_level = XGpio_DiscreteRead(&Gpio, GPIO_START_CH) & 1u;

    if (init_interrupts() != XST_SUCCESS) {
        printf("Interrupt init failed\n"); return XST_FAILURE;
    }

    fill_test_matrices();

    /* CPU-only reference: the number the accelerator has to beat */
    stat_t cpu = {0};
    uint64_t cpu_first = 0;
    for (int r = 0; r < N_CPU_REPEATS; r++) {
        XTime c0, c1;
        XTime_GetTime(&c0);
        cpu_reference();
        XTime_GetTime(&c1);
        uint64_t ns = ticks_to_ns(c1 - c0);
        if (r == 0) cpu_first = ns;
        stat_add(&cpu, ns);
    }
    printf("\n--- CPU-only 50x50 multiply (Cortex-A53) ---\n");
    printf("First run (cold cache)            : "); print_us(cpu_first); printf(" us\n");
    printf("Best of %d (warm cache)            : ", N_CPU_REPEATS); print_us(cpu.min); printf(" us\n");
    printf("CSV,cpu,%llu,%llu\n", (unsigned long long)cpu_first, (unsigned long long)cpu.min);

    /* PL runs */
    printf("\n--- %d runs on the PL (times in us) ---\n", N_RUNS);
    stat_t st[PH_COUNT] = {{0}};
    stat_t sp[3] = {{0}};
    int failed = 0, irq_runs = 0, gpio_runs = 0, invalid_runs = 0;
    for (int run = 1; run <= N_RUNS; run++) {
        uint64_t t_ns[PH_COUNT], part_ns[3];
        int polled;
        int r = run_once(run, t_ns, part_ns, &polled);
        if (r != 0) { failed++; continue; }
        if (polled == 0) irq_runs++;
        if (polled == 1) gpio_runs++;
        if (polled == 2) invalid_runs++;
        stat_add(&st[PH_LOAD], t_ns[PH_LOAD]);
        stat_add(&st[PH_READBACK], t_ns[PH_READBACK]);
        for (int p = 0; p < 3; p++) stat_add(&sp[p], part_ns[p]);
        if (polled != 2) {
            stat_add(&st[PH_COMPUTE], t_ns[PH_COMPUTE]);
            stat_add(&st[PH_TOTAL], t_ns[PH_TOTAL]);
        }
    }

    /* Summary */
    printf("\n--- Summary over passing runs (us) ---\n");
    printf("%-34s%9s  %9s  %9s\n", "", "min", "avg", "max");
    stat_print("Cache flush A+B (40 KB)",          &st[PH_LOAD]);
    stat_print("PL compute (start -> done)",       &st[PH_COMPUTE]);
    stat_print("Invalidate C + read C",            &st[PH_READBACK]);
    stat_print("  of which invalidate (20 KB)",    &sp[1]);
    stat_print("  of which read (2500 x 64 bit)",  &sp[2]);
    stat_print("Accelerator end-to-end",           &st[PH_TOTAL]);
    stat_print("CPU-only reference",               &cpu);

    if (st[PH_TOTAL].n > 0) {
        uint64_t acc_avg = st[PH_TOTAL].sum / (uint64_t)st[PH_TOTAL].n;
        uint64_t ratio100 = (acc_avg * 100 + cpu.min / 2) / cpu.min;
        printf("\nAccelerator / CPU-only time       : %llu.%02llu x  (%s)\n",
               (unsigned long long)(ratio100 / 100), (unsigned long long)(ratio100 % 100),
               ratio100 > 100 ? "accelerator is SLOWER" : "accelerator is faster");
    }
    printf("Runs passed: %d of %d\n", N_RUNS - failed, N_RUNS);
    printf("done detected by: interrupt %d, GPIO poll %d (+-1 us), not seen %d (compute not counted)\n",
           irq_runs, gpio_runs, invalid_runs);
    printf("CSV,summary,%d,%d,%d,%d\n", N_RUNS - failed, irq_runs, gpio_runs, invalid_runs);
    printf("\n%s\n", failed ? "SOME RUNS FAILED" : "ALL RUNS PASSED");

    cleanup_platform();
    return failed ? XST_FAILURE : XST_SUCCESS;
}
