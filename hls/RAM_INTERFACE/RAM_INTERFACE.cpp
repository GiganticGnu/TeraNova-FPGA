#include "RAM_INTERFACE.hpp"

// Free-running block (ap_ctrl_none): every call consumes one 5x5 block.
//
// Writer fix (2026-10-30): explicit AXI bursts with hls::burst_maxi.
// The 5 rows of a block are 5 separate address ranges (a row of the 50x50
// result is 50 values long), so a block needs 5 bursts of 5 beats. All 5
// write requests are issued first, then the 25 data beats, and only then the
// 5 write responses are collected. The responses therefore overlap instead
// of being waited for one row at a time.
void RAM_INTERFACE(hls::burst_maxi<data_t> DDR, hls::stream<matrix_t> &data, bool &done) {
#pragma HLS INTERFACE mode=m_axi port=DDR bundle=gmem offset=direct \
    depth=2500 max_write_burst_length=16 num_write_outstanding=8
#pragma HLS INTERFACE mode=ap_fifo port=data
#pragma HLS INTERFACE mode=ap_none port=done
#ifdef COSIM_HS
    // Co-simulation build only (hls_config_cosim.cfg): cosim cannot run an
    // ap_ctrl_none design with m_axi, so give it a start/done handshake.
#pragma HLS INTERFACE mode=ap_ctrl_hs port=return
#else
#pragma HLS INTERFACE mode=ap_ctrl_none port=return
#endif

    // Position of the next block in the 10x10 grid of blocks
    static ap_uint<4> chunk_x = 0;   // block column (fastest)
    static ap_uint<4> chunk_y = 0;   // block row
    // Set when the previous call wrote the last block of the matrix.
    static bool last_written = false;

    // Driven at the start of the call, i.e. after every write of the
    // previous call has been acknowledged. Stays high while waiting for the
    // next run, and goes low again once the next run has started.
    done = last_written;

    // Blocks until the accumulator presents a finished block.
    const matrix_t block = data.read();

    const unsigned base = (unsigned)chunk_y * (MATRIX_SIZE * OUTPUT_MATRIX_SIZE)
                        + (unsigned)chunk_x * MATRIX_SIZE;

    // 1. one write request (burst of 5 beats) per row of the block
REQUESTS:
    for (int i = 0; i < MATRIX_SIZE; ++i) {
#pragma HLS PIPELINE II=1
        DDR.write_request(base + i * OUTPUT_MATRIX_SIZE, MATRIX_SIZE);
    }

    // 2. the 25 values, row by row, in the order of the requests
BEATS:
    for (int e = 0; e < MATRIX_SIZE * MATRIX_SIZE; ++e) {
#pragma HLS PIPELINE II=1
        DDR.write(block.range(DATA_WIDTH * e + DATA_WIDTH - 1, DATA_WIDTH * e));
    }

    // 3. collect the 5 write responses (they overlap with each other)
RESPONSES:
    for (int i = 0; i < MATRIX_SIZE; ++i) {
#pragma HLS PIPELINE II=1
        DDR.write_response();
    }

    // Advance to the next block (column first, then row)
    bool last = false;
    if (chunk_x == OUTPUT_MATRIX_CHUNKS - 1) {
        chunk_x = 0;
        if (chunk_y == OUTPUT_MATRIX_CHUNKS - 1) {
            chunk_y = 0;
            last = true;
        } else {
            chunk_y++;
        }
    } else {
        chunk_x++;
    }
    last_written = last;
}
