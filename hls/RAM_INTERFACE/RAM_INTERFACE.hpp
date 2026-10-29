#ifndef RAM_INTERFACE_HPP
#define RAM_INTERFACE_HPP

// ---------------------------------------------------------------------------
// RAM_INTERFACE  (rewritten 2026-10)
//
// Receives finished 5x5 output blocks (25 x 64-bit, packed in 1600 bits) from
// the MatMul5x5 accumulator and writes them to their place in the 50x50
// result matrix in memory.
//
// Changes compared to the previous group's version:
//  * The input is an hls::stream with an ap_fifo interface
//    (ports data_dout / data_empty_n / data_read). This is a proper
//    valid/ready handshake: one block is consumed exactly once.
//      accumulator C_valid -> data_empty_n
//      accumulator C_ready <- data_read
//      accumulator C0..C24 -> data_dout   (via the existing concat)
//  * No union between ap_uint and an array (not well defined in C++);
//    elements are extracted with .range().
//  * 'done' only rises after all writes of the last block have completed
//    (it is driven at the start of the following call).
//  * Element (i,j) of a block is bits [64*(5*i+j)+63 : 64*(5*i+j)], i.e.
//    element 0 is in the least significant bits (matches ilconcat In0 = LSB).
// ---------------------------------------------------------------------------

// 1600-bit values need a larger maximum width than the default
#ifndef AP_INT_MAX_W
#define AP_INT_MAX_W 2048
#endif
#include <ap_int.h>
#include <hls_stream.h>
#include <stdint.h>

#define DATA_WIDTH           64
#define MATRIX_SIZE          5                       // block is 5x5
#define OUTPUT_MATRIX_SIZE   50                      // result is 50x50
#define OUTPUT_MATRIX_CHUNKS (OUTPUT_MATRIX_SIZE / MATRIX_SIZE)  // 10
#define INPUT_SIZE           (MATRIX_SIZE * MATRIX_SIZE * DATA_WIDTH) // 1600

typedef ap_uint<DATA_WIDTH> data_t;
typedef ap_uint<INPUT_SIZE> matrix_t;

void RAM_INTERFACE(data_t *DDR, hls::stream<matrix_t> &data, bool &done);

#endif // RAM_INTERFACE_HPP
