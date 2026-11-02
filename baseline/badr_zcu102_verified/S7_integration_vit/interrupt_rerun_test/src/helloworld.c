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
 *   uartlite    Configurable only in HW design
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
#include "xscugic.h"
#include "xil_exception.h"
//#include "interrupt_handler.h"
#include "xparameters_ps.h"

#ifdef XPAR_PSU_CRL_APB_BASEADDR
#include "xil_io.h"
#define CRL_APB_BASEADDR XPAR_PSU_CRL_APB_BASEADDR
#define PL0_REF_CTRL_OFFSET 0x000000C0
#define PL0_THR_CTRL_OFFSET 0x000000C4
#define PL0_THR_CNT_OFFSET  0x000000C8
#define PL1_REF_CTRL_OFFSET 0x000000CC
#define PL1_THR_CTRL_OFFSET 0x000000D0
#define PL1_THR_CNT_OFFSET  0x000000D4
#define PL2_REF_CTRL_OFFSET 0x000000D8
#define PL3_REF_CTRL_OFFSET 0x000000DC
#endif

#define TOP_MATRIX_SIZE 50
#define SUBMATRIX_SIZE 5

// Test Matrices pointers
uint64_t* test_MatrixA; // Input A
uint64_t* test_MatrixB; // Input B
uint64_t* test_MatrixC; // Output C

#define BRAM_MATRIX_A_BASEADDR XPAR_AXI_BRAM_CTRL_1_BASEADDR
#define BRAM_MATRIX_B_BASEADDR XPAR_AXI_BRAM_CTRL_3_BASEADDR

#define DRAM_RETURN_BASEADDR XPAR_DDR4_0_BASEADDRESS

#define GPIO_ADDRESS 0xB0000000 

XGpio Gpio; /* The Instance of the GPIO Driver */

// // Interrupt controller instance
// XScuGic_Config *IntcConfig;
// XScuGic IntcInstance;

// // Interrupt flag - set when interrupt occurs
// volatile static int interrupt_received = 0;

XTime BRAM_LOAD;
XTime start_time;
XTime end_time;

void enable_pl_clocks(void)
{
#ifdef XPAR_PSU_CRL_APB_BASEADDR
    xil_printf("Configuring PL clocks...\n\r");
    
    // Configure PL0 clock to 100 MHz
    // Source: IOPLL (1000 MHz typical)
    // Divisor0: 10 -> 1000/10 = 100 MHz
    // Divisor1: 1
    u32 reg_val;
    
    // Read current PL0_REF_CTRL value
    reg_val = Xil_In32(CRL_APB_BASEADDR + PL0_REF_CTRL_OFFSET);
    xil_printf("PL0_REF_CTRL before: 0x%08x\n\r", reg_val);
    
    // Configure: SRCSEL=0 (IOPLL), DIVISOR0=10, DIVISOR1=1, CLKACT=1
    reg_val = 0x01010A00;  // divisor0=10 (0x0A), divisor1=1, clkact=1, srcsel=IOPLL
    Xil_Out32(CRL_APB_BASEADDR + PL0_REF_CTRL_OFFSET, reg_val);
    
    // Verify the write
    reg_val = Xil_In32(CRL_APB_BASEADDR + PL0_REF_CTRL_OFFSET);
    xil_printf("PL0_REF_CTRL after: 0x%08x\n\r", reg_val);
    
    xil_printf("PL clocks configured, waiting for stabilization...\n\r");
    usleep(100000); // Wait 100ms for clocks to stabilize
    xil_printf("PL clocks should be active now\n\r");
#else
    xil_printf("Warning: Not a ZynqMP device, skipping PL clock configuration\n\r");
#endif
}

// // Interrupt handler function
// void done_interrupt_handler(void *CallbackRef)
// {
//     XScuGic_Disable(&IntcInstance, XPS_FPGA0_INT_ID);
//     interrupt_received = 1;
//     XTime_GetTime(&end_time);
// }

int main()
{
    init_platform();

    xil_printf("Hello World\n\r");
    xil_printf("Zynq UltraScale+ Interrupt Demo\n\r");

    // ! ||--------------------------------------------------------------------------------||
    // ! ||                           INITIALIZE INTERRUPT SYSTEM                          ||
    // ! ||--------------------------------------------------------------------------------||

    // xil_printf("Initializing interrupt system...\n\r");

    // int IntercStatus;
    // IntcConfig = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    // if (IntcConfig == NULL) {
    //     xil_printf("Interrupt Configuration Lookup Failed\n\r");
    //     cleanup_platform();
    //     return XST_FAILURE;
    // }
    // IntercStatus = XScuGic_CfgInitialize(&IntcInstance, IntcConfig,
    //                                      IntcConfig->CpuBaseAddress);
    // if (IntercStatus != XST_SUCCESS) {
    //     xil_printf("Interrupt Configuration Initialization Failed (Status: %d)\n\r", IntercStatus);
    //     cleanup_platform();
    //     return XST_FAILURE;
    // }

    // IntercStatus = XScuGic_Connect(&IntcInstance, XPS_FPGA0_INT_ID,
    //                                 (Xil_InterruptHandler)done_interrupt_handler, NULL);

    // Enable PL clocks before initializing any PL peripherals
    //enable_pl_clocks();

    xil_printf("Initializing GPIO...\n\r");
    int Status = XGpio_Initialize(&Gpio, GPIO_ADDRESS);
    if (Status != XST_SUCCESS) {
        xil_printf("GPIO Initialization Failed (Status: %d)\n\r", Status);
        cleanup_platform();
        return XST_FAILURE;
    }
    xil_printf("GPIO initialized successfully\n\r");
    
    // Perhaps don't set the direction as its set to only input and only output inside of vivado
    //XGpio_SetDataDirection(&Gpio, 1, 0x0);  // Channel 1 as output
    //XGpio_SetDataDirection(&Gpio, 2, 0x1);  // Channel 2 as input
    xil_printf("GPIO data directions configured\n\r");

// ! ||--------------------------------------------------------------------------------||
// ! ||                        Allocate memory for test matrices                       ||
// ! ||--------------------------------------------------------------------------------||
    xil_printf("Allocating memory for test matrices...\n\r");
    test_MatrixA = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));
    test_MatrixB = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));
    test_MatrixC = (uint64_t*)malloc(TOP_MATRIX_SIZE * TOP_MATRIX_SIZE * sizeof(uint64_t));

// ! ||--------------------------------------------------------------------------------||
// ! ||                               Run BRAM write test                              ||
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
// ! ||                        Write actual test values to BRAMs                       ||
// ! ||--------------------------------------------------------------------------------||
    xil_printf("Writing actual test values to BRAMs...\n\r");
    XTime_GetTime(&BRAM_LOAD);
    xil_printf("Filling Matrix A\n\r");
    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {
            bram_write_64(BRAM_MATRIX_A_BASEADDR, i * TOP_MATRIX_SIZE + j, (u64)(i * TOP_MATRIX_SIZE + j + 1));
            test_MatrixA[i * TOP_MATRIX_SIZE + j] = (u64)(i * TOP_MATRIX_SIZE + j + 1);
        }
    }
    xil_printf("Filling Matrix B\n\r");
    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {
            bram_write_64(BRAM_MATRIX_B_BASEADDR, i * TOP_MATRIX_SIZE + j, (u64)(i * TOP_MATRIX_SIZE + j + 2));
            test_MatrixB[i * TOP_MATRIX_SIZE + j] = (u64)(i * TOP_MATRIX_SIZE + j + 2);
        }
    }

// ! ||--------------------------------------------------------------------------------||
// ! ||                                start the module                                ||
// ! ||--------------------------------------------------------------------------------||

    // XScuGic_Enable(&IntcInstance, XPS_FPGA0_INT_ID);
    xil_printf("Starting matrix multiplication module...\n\r");
    XTime_GetTime(&start_time);
    XGpio_DiscreteWrite(&Gpio, 1, 1); // Set start signal

    // ! ||--------------------------------------------------------------------------------||
    // ! ||                          WAIT FOR INTERRUPT COMPLETION                        ||
    // ! ||--------------------------------------------------------------------------------||
    
    // xil_printf("Waiting for done signal via interrupt...\n\r");
    // while (!interrupt_received) {
    //     // Optionally, add a small delay or sleep here to reduce CPU usage
    //     msleep(1);
    // }

    // If end_time wasn't set by interrupt handler, set it now
    if (end_time == start_time) {
        XTime_GetTime(&end_time);
    }
    
    xil_printf("Module completed.\n\r");

// ! ||--------------------------------------------------------------------------------||
// ! ||                     Calculate and print timing information                     ||
// ! ||--------------------------------------------------------------------------------||
    
    // Calculate total time
    double total_time = 1.0 * (end_time - start_time) / (COUNTS_PER_SECOND);
    // Convert to microseconds for printing (xil_printf doesn't support floating point)
    xil_printf("Total time: %llu microseconds\n\r", (unsigned long long)(total_time * 1e6));
    
    // Calculate BRAM load time
    double bram_load_time = 1.0 * (start_time - BRAM_LOAD) / (COUNTS_PER_SECOND);
    xil_printf("BRAM load time: %llu microseconds\n\r", (unsigned long long)(bram_load_time * 1e6));

// ! ||--------------------------------------------------------------------------------||
// ! ||                           Calculate CPU expected data                          ||
// ! ||--------------------------------------------------------------------------------||

    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {
            uint64_t sum = 0;
            for (size_t k = 0; k < TOP_MATRIX_SIZE; k++) {
                sum += test_MatrixA[i * TOP_MATRIX_SIZE + k] * test_MatrixB[k * TOP_MATRIX_SIZE + j];
            }
            test_MatrixC[i * TOP_MATRIX_SIZE + j] = sum;
        }
    }

// ! ||--------------------------------------------------------------------------------||
// ! ||                                 Compare results                                ||
// ! ||--------------------------------------------------------------------------------||
    xil_printf("Comparing results from DRAM with expected results...\n\r");
    int error_found = 0;
    for (size_t i = 0; i < TOP_MATRIX_SIZE; i++) {
        for (size_t j = 0; j < TOP_MATRIX_SIZE; j++) {
            u64 dram_value = Xil_In64(DRAM_RETURN_BASEADDR + ((i * TOP_MATRIX_SIZE + j) * sizeof(u64)));
            if (dram_value != test_MatrixC[i * TOP_MATRIX_SIZE + j]) {
                xil_printf("Mismatch at C[%d][%d]: expected %llu, got %llu\n\r", i, j, test_MatrixC[i * TOP_MATRIX_SIZE + j], dram_value);
                error_found++;
            }
        }
    }

    if (error_found) {
        xil_printf("Test failed with %d errors.\n\r", error_found);
    } else {
        xil_printf("Test passed successfully.\n\r");
    }

    // ! ||--------------------------------------------------------------------------------||
    // ! ||                              CLEANUP INTERRUPT SYSTEM                        ||
    // ! ||--------------------------------------------------------------------------------||

    xil_printf("Successfully ran Hello World application\n\r");
    cleanup_platform();
    return 0;
}
