#include "bram_write.h"
#include <xil_io.h>

typedef union {
    u64 value;
    u32 words[2];
    u16 shorts[4];
    u8 bytes[8];
} u64_bytes;

void bram_write_64(UINTPTR baseAddress, size_t index, u64 data) {
    size_t offset = index * sizeof(u32);
    UINTPTR bram_ptr_first = baseAddress + offset;
    UINTPTR bram_ptr_second = baseAddress + BRAM_DEPTH + offset;

    u64_bytes data_union;
    data_union.value = data;

    XBram_Out32(bram_ptr_first, data_union.words[1]); // Write higher 32 bits
    XBram_Out32(bram_ptr_second, data_union.words[0]); // Write lower 32 bits
}

u64 bram_read_64(UINTPTR baseAddress, size_t index) {
    size_t offset = index * sizeof(u32);
    UINTPTR bram_ptr_first = baseAddress + offset;
    UINTPTR bram_ptr_second = baseAddress + BRAM_DEPTH + offset;

    u64_bytes data_union;

    data_union.words[1] = XBram_In32(bram_ptr_first); // Read higher 32 bits
    data_union.words[0] = XBram_In32(bram_ptr_second); // Read lower 32 bits

    return data_union.value;
}
