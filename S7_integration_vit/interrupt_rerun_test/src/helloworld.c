/******************************************************************************
 * 50x50 matrix multiplication on the PL (accu_to_DDR design, ZCU102)
 *
 * Flow:
 *   1. CPU writes A and B into the PL block RAMs (64-bit values split into a
 *      high and a low 32-bit BRAM).
 *   2. CPU toggles the start GPIO; the PL partitions, multiplies, accumulates
 *      and writes the 50x50 result to the PL DDR4.
 *   3. RAM_INTERFACE raises 'done' -> pl_ps_irq0 interrupt (also readable on
 *      GPIO channel 2 as a fallback).
 *   4. CPU reads the result back and compares it with its own computation.
 *
 * Every phase is timed separately so the PS<->PL transfer cost can be
 * measured: BRAM load, PL compute, result read-back, CPU reference.
 *
 * Revision history (Kai, 2026):
 *   - interrupt system completed (exception table + enable, rising edge)
 *   - start is a toggle, so the program can be re-run without reprogramming
 *   - waiting has a timeout and a GPIO fallback, so it can never hang silently
 *   - load time measures only the BRAM writes
 *   - 64-bit values printed with printf (xil_printf has no %llu)
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
#define N                    50          /* matrix is N x N               */
#define BRAM_MATRIX_A_BASE   XPAR_AXI_BRAM_CTRL_1_BASEADDR   /* A: hi @ +0, lo @ +0x8000 */
#define BRAM_MATRIX_B_BASE   XPAR_AXI_BRAM_CTRL_3_BASEADDR   /* B: hi @ +0, lo @ +0x8000 */
#define RESULT_BASE          XPAR_DDR4_0_BASEADDRESS         /* PL DDR4, written by RAM_INTERFACE */
#define GPIO_BASE            XPAR_XGPIO_0_BASEADDR
#define GPIO_START_CH        1           /* output: start toggle          */
#define GPIO_DONE_CH         2           /* input : done level            */
#define DONE_IRQ_ID          XPS_FPGA0_INT_ID                 /* pl_ps_irq0[0] = 121 */
#define TIMEOUT_US           1000000ULL  /* give up waiting after 1 s     */

/* ----------------------------------------------------------------------------
 * Globals
 * ------------------------------------------------------------------------- */
static XGpio   Gpio;
static XScuGic Intc;

static volatile int   irq_received = 0;
static volatile XTime irq_time     = 0;
static u32 start_level = 0;              /* current level of the start toggle */

static uint64_t *A, *B, *C_ref;

/* ----------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------- */
static uint64_t ticks_to_us(XTime t) {
    return ((uint64_t)t * 1000000ULL) / COUNTS_PER_SECOND;
}

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
 * One complete run on the PL. Returns the number of result mismatches,
 * or -1 if the PL never signalled completion.
 * ------------------------------------------------------------------------- */
static int run_once(int run) {
    XTime t0, t1, t2, t3, t4;

    printf("\n=== Run %d ===\n", run);

    /* 1. load A and B into the BRAMs */
    XTime_GetTime(&t0);
    load_brams();
    XTime_GetTime(&t1);

    int bad = check_brams();
    if (bad) {
        printf("BRAM read-back check FAILED (%d words wrong)\n", bad);
        return -1;
    }

    /* clear the result area so a run that writes nothing cannot pass */
    for (int k = 0; k < N * N; k++)
        Xil_Out64(RESULT_BASE + (UINTPTR)k * sizeof(uint64_t), 0);

    /* 2. start: toggle the start GPIO (toggle2pulse makes a start pulse) */
    irq_received = 0;
    XScuGic_Enable(&Intc, DONE_IRQ_ID);
    start_level ^= 1u;
    XTime_GetTime(&t2);
    XGpio_DiscreteWrite(&Gpio, GPIO_START_CH, start_level);

    /* 3. wait for the done interrupt (busy wait, no sleep, so timing stays exact) */
    XTime now;
    do {
        XTime_GetTime(&now);
    } while (!irq_received && ticks_to_us(now - t2) < TIMEOUT_US);

    if (irq_received) {
        t3 = irq_time;
    } else {
        u32 done_level = XGpio_DiscreteRead(&Gpio, GPIO_DONE_CH) & 1u;
        printf("No interrupt after %llu us. done (GPIO2) = %u\n",
               (unsigned long long)ticks_to_us(now - t2), (unsigned)done_level);
        if (!done_level) return -1;
        printf("PL finished but the interrupt did not reach the CPU; continuing with the check.\n");
        t3 = now;
    }

    /* 4. read the result back from the PL DDR4 and compare */
    static uint64_t C_hw[N * N];
    XTime t_rb0;
    XTime_GetTime(&t_rb0);
    for (int k = 0; k < N * N; k++)
        C_hw[k] = Xil_In64(RESULT_BASE + (UINTPTR)k * sizeof(uint64_t));
    XTime_GetTime(&t4);

    int errors = 0;
    for (int k = 0; k < N * N; k++) {
        if (C_hw[k] != C_ref[k]) {
            if (errors < 10)
                printf("Mismatch C[%d][%d]: got %llu expected %llu\n", k / N, k % N,
                       (unsigned long long)C_hw[k], (unsigned long long)C_ref[k]);
            errors++;
        }
    }

    printf("BRAM load (PS->PL, 10000 writes): %8llu us\n", (unsigned long long)ticks_to_us(t1 - t0));
    printf("PL compute (start -> done)      : %8llu us%s\n", (unsigned long long)ticks_to_us(t3 - t2),
           irq_received ? "" : "  (polled, not exact)");
    printf("Result read-back (PL DDR4->PS)  : %8llu us\n", (unsigned long long)ticks_to_us(t4 - t_rb0));
    printf("Result: %s (%d mismatches)\n", errors ? "FAILED" : "PASSED", errors);
    return errors;
}

/* ------------------------------------------------------------------------- */
int main(void) {
    init_platform();
    printf("\n50x50 matrix multiplication on the PL\n");

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

    XTime c0, c1;
    XTime_GetTime(&c0);
    cpu_reference();
    XTime_GetTime(&c1);
    printf("CPU-only reference multiply     : %8llu us\n", (unsigned long long)ticks_to_us(c1 - c0));

    /* Two runs: the second one checks that the design can be restarted */
    int total = 0;
    for (int run = 1; run <= 2; run++) {
        int r = run_once(run);
        if (r != 0) total++;
    }

    printf("\n%s\n", total ? "SOME RUNS FAILED" : "ALL RUNS PASSED");
    cleanup_platform();
    return total ? XST_FAILURE : XST_SUCCESS;
}
