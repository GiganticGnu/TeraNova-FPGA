/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * helloworld.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "bram_write.h"
#include <stdlib.h>
#include "xgpio.h"
#include "sleep.h"
#include "xstatus.h"
#include <xiltimer.h>
#include <xtimer_config.h>
#include "xscugic.h"
#include "xil_exception.h"
//#include "interrupt_handler.h"
#include "xparameters_ps.h"

#ifdef XPAR_PSU_CRL_APB_BASEADDR
#include "xil_io.h"

// #define CRL_APB_BASEADDR XPAR_PSU_CRL_APB_BASEADDR
// #define PL0_REF_CTRL_OFFSET 0x000000C0
// #define PL0_THR_CTRL_OFFSET 0x000000C4
// #define PL0_THR_CNT_OFFSET  0x000000C8
// #define PL1_REF_CTRL_OFFSET 0x000000CC
// #define PL1_THR_CTRL_OFFSET 0x000000D0
// #define PL1_THR_CNT_OFFSET  0x000000D4
// #define PL2_REF_CTRL_OFFSET 0x000000D8
// #define PL3_REF_CTRL_OFFSET 0x000000DC

#endif

#define TOP_MATRIX_SIZE 50
#define SUBMATRIX_SIZE 5
#define POISON_VALUE 0xDEADBEEFDEADBEEFULL

#define TO_US(start, end) ((u64)((end) - (start)) * 1000000ULL / COUNTS_PER_SECOND)


// Test Matrices pointers
uint64_t* test_MatrixA; // Input A
uint64_t* test_MatrixB; // Input B
uint64_t* test_MatrixC; // Expected CPU output C

uint64_t* test_MatrixHW;

#define BRAM_MATRIX_A_BASEADDR XPAR_AXI_BRAM_CTRL_1_BASEADDR
#define BRAM_MATRIX_B_BASEADDR XPAR_AXI_BRAM_CTRL_3_BASEADDR

#define DRAM_RETURN_BASEADDR XPAR_DDR4_0_BASEADDRESS

#define GPIO_ADDRESS 0xB0000000


XGpio Gpio; /* The Instance of the GPIO Driver */




XTime t_gen_start, t_gen_end;
XTime t_bramA_start, t_bramA_end;
XTime t_bramB_start, t_bramB_end;
XTime t_poison_start, t_poison_end;
XTime t_accel_start, t_accel_end;
XTime t_cpu_start, t_cpu_end;
XTime t_compare_start, t_compare_end;
XTime t_readback_start, t_readback_end;

XScuGic IntcInstance;
XScuGic_Config *IntcConfig;


volatile int interrupt_received = 0;

void DoneISR(void *CallbackRef)
{
    interrupt_received = 1;
}


// ! ||--------------------------------------------------------------------------------||
// ! ||                           SETUP INTERRUPT SYSTEM                               ||
// ! ||--------------------------------------------------------------------------------||

int SetupInterruptSystem(void)
{
    int Status;

    IntcConfig = XScuGic_LookupConfig(XPAR_SCUGIC_SINGLE_DEVICE_ID);

    if (IntcConfig == NULL) {
        xil_printf("GIC config lookup failed\n\r");
        return XST_FAILURE;
    }

    Status = XScuGic_CfgInitialize(&IntcInstance, IntcConfig, IntcConfig->CpuBaseAddress);

    if (Status != XST_SUCCESS) {
        xil_printf("GIC initialization failed\n\r");
        return XST_FAILURE;
    }

    Xil_ExceptionInit();

    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler)XScuGic_InterruptHandler, &IntcInstance);

    Status = XScuGic_Connect(&IntcInstance, XPS_FPGA0_INT_ID, (Xil_ExceptionHandler)DoneISR, NULL);

    if (Status != XST_SUCCESS) {
        xil_printf("Interrupt connect failed\n\r");
        return XST_FAILURE;
    }

    // DONE is a short pulse from the PL, so GIC uses rising-edge triggering
    XScuGic_SetPriorityTriggerType(&IntcInstance, XPS_FPGA0_INT_ID, 0xA0, 0x3);
    // 0xA0 = normal priority
    // 0x3  = rising-edge triggered

    XScuGic_Enable(&IntcInstance, XPS_FPGA0_INT_ID);
    Xil_ExceptionEnable();

    xil_printf("Interrupt system initialized\n\r");

    return XST_SUCCESS;
}


// ! ||--------------------------------------------------------------------------------||
// ! ||                                      MAIN                                     ||
// ! ||--------------------------------------------------------------------------------||

int main()
{
    init_platform();

    xil_printf("Hello World\n\r");
    xil_printf("Zynq UltraScale+ Interrupt Demo\n\r");


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                                INITIALIZE GPIO                                 ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("Initializing GPIO...\n\r");

    int Status = XGpio_Initialize(&Gpio, GPIO_ADDRESS);

    if (Status != XST_SUCCESS) {
        xil_printf("GPIO Initialization Failed (Status: %d)\n\r", Status);
        cleanup_platform();
        return XST_FAILURE;
    }

    xil_printf("GPIO initialized successfully\n\r");

    XGpio_SetDataDirection(&Gpio, 1, 0x0); // Channel 1 as output
    XGpio_SetDataDirection(&Gpio, 2, 0x1); // Channel 2 as input

    xil_printf("GPIO data directions configured\n\r");


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                            INITIALIZE INTERRUPT SYSTEM                          ||
    // ! ||--------------------------------------------------------------------------------||

    Status = SetupInterruptSystem();

    if (Status != XST_SUCCESS) {
        xil_printf("Interrupt setup failed\n\r");
        cleanup_platform();
        return XST_FAILURE;
    }


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                         ALLOCATE MEMORY FOR MATRICES                           ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("Allocating memory for test matrices...\n\r");

    test_MatrixA = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));
    test_MatrixB = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));
    test_MatrixC = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));
    test_MatrixHW = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));

    if (test_MatrixA == NULL || test_MatrixB == NULL || test_MatrixC == NULL || test_MatrixHW == NULL) {
        xil_printf("Matrix malloc failed\n\r");
        cleanup_platform();
        return XST_FAILURE;
    }


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                              BRAM WRITE/READ TEST                              ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("Running BRAM write/read test...\n\r");

    const u64 test_value = 0xDEADBEEFDEADBEEF;


    // Write to matrix A BRAM and read back

    xil_printf("Writing to Matrix A BRAM and reading back...\n\r");

    bram_write_64(BRAM_MATRIX_A_BASEADDR, 0, test_value);

    u64 read_data = bram_read_64(BRAM_MATRIX_A_BASEADDR, 0);

    if (read_data != test_value) {
        xil_printf("BRAM write/read test failed for Matrix A\n\r");
        cleanup_platform();
        return -1;
    } else {
        xil_printf("BRAM write/read test passed for Matrix A\n\r");
    }


    // Do the same for matrix B

    xil_printf("Writing to Matrix B BRAM and reading back...\n\r");

    bram_write_64(BRAM_MATRIX_B_BASEADDR, 0, test_value);

    read_data = bram_read_64(BRAM_MATRIX_B_BASEADDR, 0);

    if (read_data != test_value) {
        xil_printf("BRAM write/read test failed for Matrix B\n\r");
        cleanup_platform();
        return -1;
    } else {
        xil_printf("BRAM write/read test passed for Matrix B\n\r");
    }


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                           GENERATE TEST MATRICES                               ||
    // ! ||--------------------------------------------------------------------------------||

    XTime_GetTime(&t_gen_start);

    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {
            test_MatrixA[i * TOP_MATRIX_SIZE + j] = (u64)(i * TOP_MATRIX_SIZE + j + 1);
            test_MatrixB[i * TOP_MATRIX_SIZE + j] = (u64)(i * TOP_MATRIX_SIZE + j + 7); // Was +2, tested with +7
        }
    }

    XTime_GetTime(&t_gen_end);

    XTime_GetTime(&t_bramA_start);

    // for (size_t i = 0; i < TOP_MATRIX_SIZE * TOP_MATRIX_SIZE; i++) {
    //     bram_write_64(BRAM_MATRIX_A_BASEADDR, i, test_MatrixA[i]);
    // }

    bram_write_matrix(BRAM_MATRIX_A_BASEADDR, test_MatrixA, TOP_MATRIX_SIZE * TOP_MATRIX_SIZE);

    XTime_GetTime(&t_bramA_end);


    XTime_GetTime(&t_bramB_start);

    // for (size_t i = 0; i < TOP_MATRIX_SIZE * TOP_MATRIX_SIZE; i++) {
    //     bram_write_64(BRAM_MATRIX_B_BASEADDR, i, test_MatrixB[i]);
    // }
    bram_write_matrix(BRAM_MATRIX_B_BASEADDR, test_MatrixB, TOP_MATRIX_SIZE * TOP_MATRIX_SIZE);

    XTime_GetTime(&t_bramB_end);


    //  Poisoning DDR
    XTime_GetTime(&t_poison_start);

    for (size_t i = 0; i < TOP_MATRIX_SIZE * TOP_MATRIX_SIZE; i++) {
        Xil_Out64(DRAM_RETURN_BASEADDR + i * sizeof(u64), POISON_VALUE);
    }

    XTime_GetTime(&t_poison_end);

    u64 before_result = Xil_In64(DRAM_RETURN_BASEADDR);


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                                START THE MODULE                                ||
    // ! ||--------------------------------------------------------------------------------||

    interrupt_received = 0;

    // Force START low first so toggle2pulse sees a 0 -> 1 transition
    XGpio_DiscreteWrite(&Gpio, 1, 0);
    usleep(10);

    XTime_GetTime(&t_accel_start);

    // Rising edge starts the accelerator
    XGpio_DiscreteWrite(&Gpio, 1, 1);


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                          WAIT FOR INTERRUPT COMPLETION                         ||
    // ! ||--------------------------------------------------------------------------------||

    XTime timeout_start;
    XTime_GetTime(&timeout_start);

    while (!interrupt_received) {

        XTime now;
        XTime_GetTime(&now);

        // 1 second timeout
        if ((now - timeout_start) > COUNTS_PER_SECOND) {
            break;
        }
    }

    XTime_GetTime(&t_accel_end);

    int accelerator_completed = interrupt_received;

    u64 result_after = Xil_In64(DRAM_RETURN_BASEADDR);


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                         CALCULATE CPU EXPECTED DATA                            ||
    // ! ||--------------------------------------------------------------------------------||

    XTime_GetTime(&t_cpu_start);

    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {

            uint64_t sum = 0;

            for (size_t k = 0; k < TOP_MATRIX_SIZE; k++) {
                sum += test_MatrixA[i * TOP_MATRIX_SIZE + k] * test_MatrixB[k * TOP_MATRIX_SIZE + j];
            }

            test_MatrixC[i * TOP_MATRIX_SIZE + j] = sum;
        }
    }

    XTime_GetTime(&t_cpu_end);




    // ! ||--------------------------------------------------------------------------------||
    // ! ||                              Readback and Comparison                           ||
    // ! ||--------------------------------------------------------------------------------||

    XTime_GetTime(&t_readback_start);

    for (size_t i = 0; i < TOP_MATRIX_SIZE * TOP_MATRIX_SIZE; i++) {
        test_MatrixHW[i] = Xil_In64(DRAM_RETURN_BASEADDR + i * sizeof(u64));
    }
    XTime_GetTime(&t_readback_end);

    XTime_GetTime(&t_compare_start);

    int error_found = 0;

    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {

            size_t index = i * TOP_MATRIX_SIZE + j;

            if (test_MatrixHW[index] != test_MatrixC[index]) {

                if (error_found < 5) {
                    xil_printf("Mismatch at C[%d][%d]: expected %llu, got %llu\n\r", i, j, test_MatrixC[index], test_MatrixHW[index]);
                }

                error_found++;
            }
        }
    }

    XTime_GetTime(&t_compare_end);


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                               CALCULATE TIMINGS                                ||
    // ! ||--------------------------------------------------------------------------------||

    u64 matrix_generation_us = TO_US(t_gen_start, t_gen_end);
    u64 bramA_load_us = TO_US(t_bramA_start, t_bramA_end);
    u64 bramB_load_us = TO_US(t_bramB_start, t_bramB_end);
    u64 ddr_poison_us = TO_US(t_poison_start, t_poison_end);
    u64 accelerator_us = TO_US(t_accel_start, t_accel_end);
    u64 cpu_reference_us = TO_US(t_cpu_start, t_cpu_end);
    u64 comparison_us = TO_US(t_compare_start, t_compare_end);
    u64 readback_us = TO_US(t_readback_start, t_readback_end);



    u64 operational_us = matrix_generation_us + bramA_load_us + bramB_load_us + accelerator_us;
    u64 total_validation_us = operational_us + ddr_poison_us + cpu_reference_us + readback_us + comparison_us;


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                                  PRINT RESULTS                                 ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("\n\r=== TIMING RESULTS ===\n\r");

    xil_printf("Matrix generation: %llu us\n\r", (unsigned long long)matrix_generation_us);
    xil_printf("BRAM A load:       %llu us\n\r", (unsigned long long)bramA_load_us);
    xil_printf("BRAM B load:       %llu us\n\r", (unsigned long long)bramB_load_us);
    xil_printf("DDR poison:        %llu us\n\r", (unsigned long long)ddr_poison_us);

    xil_printf("\n\r");

    if (accelerator_completed) {
        xil_printf("Accelerator interrupt: RECEIVED\n\r");
    } else {
        xil_printf("Accelerator interrupt: TIMEOUT\n\r");
    }

    xil_printf("Accelerator:       %llu us\n\r", (unsigned long long)accelerator_us);

    xil_printf("\n\r");

    xil_printf("CPU reference:     %llu us\n\r", (unsigned long long)cpu_reference_us);
    xil_printf("Result readback:   %llu us\n\r", (unsigned long long)readback_us);
    xil_printf("Comparison:        %llu us\n\r", (unsigned long long)comparison_us);

    xil_printf("\n\r");

    xil_printf("Operational time:  %llu us\n\r", (unsigned long long)operational_us);
    xil_printf("Total validation:  %llu us\n\r", (unsigned long long)total_validation_us);


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                              PRINT DEBUG INFORMATION                           ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("\n\r=== VALIDATION RESULTS ===\n\r");

    xil_printf("Result before accelerator: 0x%llx\n\r", (unsigned long long)before_result);
    xil_printf("Result after accelerator:  0x%llx\n\r", (unsigned long long)result_after);

    xil_printf("Total mismatches: %d / %d\n\r", error_found, TOP_MATRIX_SIZE * TOP_MATRIX_SIZE);

    if (error_found) {
        xil_printf("Test failed with %d errors.\n\r", error_found);
    } else {
        xil_printf("Test passed successfully.\n\r");
    }

    xil_printf("Successfully ran Hello World application\n\r");


    // ! ||--------------------------------------------------------------------------------||
    // ! ||                                      CLEANUP                                   ||
    // ! ||--------------------------------------------------------------------------------||

    free(test_MatrixA);
    free(test_MatrixB);
    free(test_MatrixC);
    free(test_MatrixHW);

    cleanup_platform();

    return 0;
}