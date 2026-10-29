#include "RAM_INTERFACE.hpp"

// Free-running block (ap_ctrl_none): every call consumes one 5x5 block.
void RAM_INTERFACE(data_t *DDR, hls::stream<matrix_t> &data, bool &done) {
#pragma HLS INTERFACE mode=m_axi port=DDR bundle=gmem offset=direct \
    depth=2500 max_widen_bitwidth=128 max_write_burst_length=16 num_write_outstanding=4
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

ROWS:
    for (int i = 0; i < MATRIX_SIZE; ++i) {
    COLS:
        for (int j = 0; j < MATRIX_SIZE; ++j) {
#pragma HLS PIPELINE II=1
            const int e = i * MATRIX_SIZE + j;
            DDR[base + i * OUTPUT_MATRIX_SIZE + j] =
                block.range(DATA_WIDTH * e + DATA_WIDTH - 1, DATA_WIDTH * e);
        }
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
