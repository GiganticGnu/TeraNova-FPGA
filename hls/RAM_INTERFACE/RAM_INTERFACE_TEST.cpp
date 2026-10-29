// C-simulation testbench for RAM_INTERFACE.
// Builds a reference 50x50 result, feeds it block by block in the order the
// accumulator produces it (block column fastest), and checks memory + done.
// Runs two complete matrices back to back to check that restarting works.
#include "RAM_INTERFACE.hpp"
#include <cstdio>

static const int N = OUTPUT_MATRIX_SIZE;
static const int B = MATRIX_SIZE;
static const int NB = OUTPUT_MATRIX_CHUNKS;

static data_t mem[N * N];

static uint64_t ref_value(int run, int r, int c) {
    // distinct, 64-bit wide values (exercise the upper bits too)
    return 0x0123456789ABCDEFull * (uint64_t)(run + 1) + (uint64_t)r * 1000003ull + (uint64_t)c * 7919ull;
}

static matrix_t make_block(int run, int by, int bx) {
    matrix_t m = 0;
    for (int i = 0; i < B; ++i)
        for (int j = 0; j < B; ++j) {
            int e = i * B + j;
            m.range(64 * e + 63, 64 * e) = ref_value(run, by * B + i, bx * B + j);
        }
    return m;
}

int main() {
    int errors = 0;
    hls::stream<matrix_t> s;
    bool done = false;

    for (int run = 0; run < 2; ++run) {
        for (int k = 0; k < N * N; ++k) mem[k] = 0;
        for (int by = 0; by < NB; ++by) {
            for (int bx = 0; bx < NB; ++bx) {
                s.write(make_block(run, by, bx));
                RAM_INTERFACE(mem, s, done);
                int call = by * NB + bx;   // 0..99 within this run
                // done must be high only on the first call of the second run
                bool expect_done = (run == 1 && call == 0);
                if (done != expect_done) {
                    printf("done error: run %d call %d done=%d expected %d\n", run, call, (int)done, (int)expect_done);
                    errors++;
                }
            }
        }
        for (int r = 0; r < N; ++r)
            for (int c = 0; c < N; ++c)
                if ((uint64_t)mem[r * N + c] != ref_value(run, r, c)) {
                    if (errors < 10) printf("data error run %d at (%d,%d)\n", run, r, c);
                    errors++;
                }
        if (!s.empty()) { printf("stream not empty after run %d\n", run); errors++; }
    }

    if (errors == 0) printf("PASS: 2 x 100 blocks written correctly, done behaves as expected\n");
    else             printf("FAIL: %d errors\n", errors);
    return errors ? 1 : 0;
}
