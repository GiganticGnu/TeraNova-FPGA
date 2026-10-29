/******************************************************************************
 * 50x50 matrix multiplication on the PL (accu_to_DDR design, ZCU102)
 * BASELINE MEASUREMENT VERSION
 *
 * Same flow as the normal application:
 *   1. CPU writes A and B into the PL block RAMs (64-bit values split into a
 *      high and a low 32-bit BRAM).
 *   2. CPU toggles the start GPIO; the PL partitions, multiplies, accumulates
 *      and writes the 50x50 result to the PL DDR4.
 *   3. RAM_INTERFACE raises 'done' -> pl_ps_irq0 interrupt (also readable on
 *      GPIO channel 2 as a fallback).
 *   4. CPU reads the result back and compares it with its own computation.
 *
 * What this version adds, so the numbers can be used as a baseline:
 *   - N_RUNS runs instead of 2, with min / average / max per phase
 *   - nanosecond resolution (the timer ticks at ~100 MHz = 10 ns per tick)
 *     instead of whole microseconds
 *   - latency probes: cost of ONE PS->PL BRAM write, ONE BRAM read and ONE
 *     PL-DDR4 read. These explain where the load / read-back time comes from.
 *   - the CPU-only reference is repeated: first (cold cache) and best (warm)
 *   - 'done' is detected by the interrupt AND by polling GPIO channel 2, so a
 *     compute time is measured even if the interrupt path does not work
 *     (the previous group's interrupt was never seen working on hardware)
 *   - one "CSV," line per run, easy to paste into a spreadsheet
 *   - prints the compiler optimisation level, so every log says which build
 *     was measured (-O0 = previous group's setting, -O2 = current setting)
 *
 * Uses only hardware names that exist in BOTH the previous group's hardware
 * (interrupt_rerun.xsa of 30 Sep) and the restored design, so it runs on both.
 ******************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xparameters_ps.h"
#include "xil_io.h"
#include "xil_exception.h"
#include "xscugic.h"
#include "xgpio.h"
#include "xstatus.h"
#include "xiltimer.h"
#include "bram_write.h"

/* ----------------------------------------------------------------------------
 * Configuration
 * ------------------------------------------------------------------------- */
#define N                    50          /* matrix is N x N                  */
#define N_RUNS               10          /* PL runs per execution            */
#define N_CPU_REPEATS        5           /* CPU reference repetitions        */
#define N_PROBE              1000        /* accesses per latency probe       */

#define BRAM_MATRIX_A_BASE   XPAR_AXI_BRAM_CTRL_1_BASEADDR   /* A: hi @ +0, lo @ +0x8000 */
#define BRAM_MATRIX_B_BASE   XPAR_AXI_BRAM_CTRL_3_BASEADDR   /* B: hi @ +0, lo @ +0x8000 */
#define RESULT_BASE          XPAR_DDR4_0_BASEADDRESS         /* PL DDR4, written by RAM_INTERFACE */
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

static uint64_t *A, *B, *C_ref;
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

/* Only the BRAM writes, so the measured time is the pure PS->PL transfer */
static void load_brams(void) {
    for (int k = 0; k < N * N; k++) {
        bram_write_64(BRAM_MATRIX_A_BASE, k, A[k]);
        bram_write_64(BRAM_MATRIX_B_BASE, k, B[k]);
    }
    barrier();                            /* count the writes until they have landed */
}

static int check_brams(void) {
    int bad = 0;
    for (int k = 0; k < N * N; k++) {
        if (bram_read_64(BRAM_MATRIX_A_BASE, k) != A[k]) bad++;
        if (bram_read_64(BRAM_MATRIX_B_BASE, k) != B[k]) bad++;
    }
    return bad;
}

static void cpu_reference(void) {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) {
            uint64_t sum = 0;
            for (int k = 0; k < N; k++) sum += A[i * N + k] * B[k * N + j];
            C_ref[i * N + j] = sum;
        }
}

/* ----------------------------------------------------------------------------
 * Latency probes: average cost of ONE access across the PS-PL boundary.
 * Run before the PL runs; the BRAM contents they overwrite are reloaded later.
 * ------------------------------------------------------------------------- */
static void latency_probes(void) {
    XTime t0, t1;
    volatile u32 sink32 = 0;
    volatile u64 sink64 = 0;

    /* single 32-bit writes to BRAM A (what bram_write_64 does twice per value) */
    XTime_GetTime(&t0);
    for (int i = 0; i < N_PROBE; i++)
        XBram_Out32(BRAM_MATRIX_A_BASE + (UINTPTR)(i & 63) * 4, (u32)i);
    barrier();
    XTime_GetTime(&t1);
    uint64_t wr_ns = ticks_to_ns(t1 - t0);

    /* single 32-bit reads from BRAM A: a full round trip each */
    XTime_GetTime(&t0);
    for (int i = 0; i < N_PROBE; i++)
        sink32 += XBram_In32(BRAM_MATRIX_A_BASE + (UINTPTR)(i & 63) * 4);
    XTime_GetTime(&t1);
    uint64_t rd_ns = ticks_to_ns(t1 - t0);

    /* single 64-bit reads from the PL DDR4 (what the result read-back does) */
    XTime_GetTime(&t0);
    for (int i = 0; i < N_PROBE; i++)
        sink64 += Xil_In64(RESULT_BASE + (UINTPTR)(i & 63) * 8);
    XTime_GetTime(&t1);
    uint64_t ddr_ns = ticks_to_ns(t1 - t0);

    (void)sink32; (void)sink64;
    printf("\n--- Latency probes (average of %d accesses) ---\n", N_PROBE);
    printf("One 32-bit write PS -> BRAM       : %6llu ns\n", (unsigned long long)(wr_ns / N_PROBE));
    printf("One 32-bit read  BRAM -> PS       : %6llu ns\n", (unsigned long long)(rd_ns / N_PROBE));
    printf("One 64-bit read  PL DDR4 -> PS    : %6llu ns\n", (unsigned long long)(ddr_ns / N_PROBE));
    printf("CSV,probe,%llu,%llu,%llu\n", (unsigned long long)(wr_ns / N_PROBE),
           (unsigned long long)(rd_ns / N_PROBE), (unsigned long long)(ddr_ns / N_PROBE));
}

/* ----------------------------------------------------------------------------
 * One complete run on the PL. Returns the number of result mismatches,
 * or -1 if the run could not complete. Phase times (ns) are returned via t_ns.
 * ------------------------------------------------------------------------- */
enum { PH_LOAD, PH_COMPUTE, PH_READBACK, PH_TOTAL, PH_COUNT };

static int run_once(int run, uint64_t t_ns[PH_COUNT], int *polled) {
    XTime t0, t1, t2, t3, t4, t_rb0;
    *polled = 0;

    /* 1. load A and B into the BRAMs */
    XTime_GetTime(&t0);
    load_brams();
    XTime_GetTime(&t1);

    int bad = check_brams();
    if (bad) {
        printf("Run %2d: BRAM read-back check FAILED (%d words wrong)\n", run, bad);
        return -1;
    }

    /* clear the result area so a run that writes nothing cannot pass */
    for (int k = 0; k < N * N; k++)
        Xil_Out64(RESULT_BASE + (UINTPTR)k * sizeof(uint64_t), 0);
    barrier();

    /* 2. start: toggle the start GPIO (toggle2pulse makes a start pulse) */
    irq_received = 0;
    int seen_low = ((XGpio_DiscreteRead(&Gpio, GPIO_DONE_CH) & 1u) == 0);
    XScuGic_Enable(&Intc, DONE_IRQ_ID);
    start_level ^= 1u;
    XTime_GetTime(&t2);
    XGpio_DiscreteWrite(&Gpio, GPIO_START_CH, start_level);

    /* 3. wait for done. Two detectors run side by side:
     *    - the interrupt (exact: the ISR takes the timestamp)
     *    - polling 'done' on GPIO channel 2 (about 1 us resolution), which
     *      still gives a compute time if the interrupt path does not work.
     *      A rise is only counted after done was seen low, so a 'done' left
     *      high by the previous run is not mistaken for this run's.
     *    After the poll sees done, wait 100 us more for the interrupt, so the
     *    log shows whether the interrupt path works. */
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
        t3 = irq_time;                                  /* exact */
    } else if (t_poll) {
        t3 = t_poll;                                    /* within ~1 us */
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

    /* 4. read the result back from the PL DDR4 */
    XTime_GetTime(&t_rb0);
    for (int k = 0; k < N * N; k++)
        C_hw[k] = Xil_In64(RESULT_BASE + (UINTPTR)k * sizeof(uint64_t));
    XTime_GetTime(&t4);

    int errors = 0;
    for (int k = 0; k < N * N; k++) {
        if (C_hw[k] != C_ref[k]) {
            if (errors < 5)
                printf("        mismatch C[%d][%d]: got %llu expected %llu\n", k / N, k % N,
                       (unsigned long long)C_hw[k], (unsigned long long)C_ref[k]);
            errors++;
        }
    }

    t_ns[PH_LOAD]     = ticks_to_ns(t1 - t0);
    t_ns[PH_COMPUTE]  = ticks_to_ns(t3 - t2);
    t_ns[PH_READBACK] = ticks_to_ns(t4 - t_rb0);
    t_ns[PH_TOTAL]    = t_ns[PH_LOAD] + t_ns[PH_COMPUTE] + t_ns[PH_READBACK];

    printf("Run %2d: load ", run);        print_us(t_ns[PH_LOAD]);
    printf("  compute ");                 print_us(t_ns[PH_COMPUTE]);
    printf("%s", *polled == 1 ? " (GPIO)" : *polled == 2 ? " (n/a) " : "");
    printf("  read-back ");               print_us(t_ns[PH_READBACK]);
    printf("  total ");                   print_us(t_ns[PH_TOTAL]);
    printf("  us  %s\n", errors ? "FAILED" : "PASSED");

    printf("CSV,run,%d,%llu,%llu,%llu,%llu,%d,%d\n", run,
           (unsigned long long)t_ns[PH_LOAD], (unsigned long long)t_ns[PH_COMPUTE],
           (unsigned long long)t_ns[PH_READBACK], (unsigned long long)t_ns[PH_TOTAL],
           errors, *polled);
    return errors;
}

/* ------------------------------------------------------------------------- */
int main(void) {
    init_platform();
    printf("\n50x50 matrix multiplication on the PL - BASELINE MEASUREMENT\n");
#if defined(__OPTIMIZE__)
    printf("Build: optimised (-O1 or higher)\n");
#else
    printf("Build: NOT optimised (-O0)\n");
#endif
    printf("Timer: %llu ticks per second (%llu ns per tick)\n",
           (unsigned long long)COUNTS_PER_SECOND,
           (unsigned long long)(1000000000ULL / COUNTS_PER_SECOND));

    A     = (uint64_t *)malloc(N * N * sizeof(uint64_t));
    B     = (uint64_t *)malloc(N * N * sizeof(uint64_t));
    C_ref = (uint64_t *)malloc(N * N * sizeof(uint64_t));
    if (!A || !B || !C_ref) { printf("malloc failed\n"); return XST_FAILURE; }

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

    latency_probes();

    /* PL runs */
    printf("\n--- %d runs on the PL (times in us) ---\n", N_RUNS);
    stat_t st[PH_COUNT] = {{0}};
    int failed = 0, irq_runs = 0, gpio_runs = 0, invalid_runs = 0;
    for (int run = 1; run <= N_RUNS; run++) {
        uint64_t t_ns[PH_COUNT];
        int polled;
        int r = run_once(run, t_ns, &polled);
        if (r != 0) { failed++; continue; }
        if (polled == 0) irq_runs++;
        if (polled == 1) gpio_runs++;
        if (polled == 2) invalid_runs++;
        stat_add(&st[PH_LOAD], t_ns[PH_LOAD]);
        stat_add(&st[PH_READBACK], t_ns[PH_READBACK]);
        /* a run whose done-rise was never seen has no valid compute time */
        if (polled != 2) {
            stat_add(&st[PH_COMPUTE], t_ns[PH_COMPUTE]);
            stat_add(&st[PH_TOTAL], t_ns[PH_TOTAL]);
        }
    }

    /* Summary */
    printf("\n--- Summary over passing runs (us) ---\n");
    printf("%-34s%9s  %9s  %9s\n", "", "min", "avg", "max");
    stat_print("BRAM load (PS->PL, 10000 writes)", &st[PH_LOAD]);
    stat_print("PL compute (start -> done)",       &st[PH_COMPUTE]);
    stat_print("Result read-back (2500 reads)",    &st[PH_READBACK]);
    stat_print("Accelerator end-to-end",           &st[PH_TOTAL]);
    stat_print("CPU-only reference",               &cpu);

    if (st[PH_TOTAL].n > 0) {
        uint64_t acc_avg = st[PH_TOTAL].sum / (uint64_t)st[PH_TOTAL].n;
        /* ratio x100 with integer math */
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
