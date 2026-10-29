#ifndef BRAM_WRITE_H
#define BRAM_WRITE_H

#include <xil_types.h>
#include <xparameters.h>
#include "xil_types.h"
#include "xil_io.h"
#include "xbram.h"

#define A_PARTITION_AMOUNT 1
#define B_PARTITION_AMOUNT 1
#define BRAM_DEPTH 0x8000 // 32KB per BRAM controller

/**
 * @brief Writes a 64-bit value to the BRAM at the specified base address.
 *
 * @param baseAddress The base address of the BRAM location.
 * @param data The 64-bit data to write.
 */
void bram_write_64(UINTPTR baseAddress, size_t index, u64 data);

/**
 * @brief Reads a 64-bit value from the BRAM at the specified base address.
 *
 * @param baseAddress The base address of the BRAM location.
 * @return The 64-bit data read from the BRAM.
 */
u64 bram_read_64(UINTPTR baseAddress, size_t index);

#endif //BRAM_WRITE_H
