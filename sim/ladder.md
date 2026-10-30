# Improvement ladder (PL run time, simulated)

PL: cycles from start to done at 100 MHz, real RTL of every block, AXI memory latency L.

| Step | Change | Build from | PL cycles (L=20) | PL vs previous | PL cycles (L=100) | Tests |
|---|---|---|---:|---:|---:|---|
| 0_baseline | Baseline: restored design | tag baseline-1 | 101186 (1.012 ms) | — | 101586 | PASS |
| 1_partitioner_v5b | Partitioner v5b: pipelined fetch | branch partitioner-v5b | 27186 (0.272 ms) | -74000 (3.72×) | 58576 | PASS |
| 2_writer_fix | Writer: overlapped write responses | branch writer-fix | 27071 (0.271 ms) | -115 (1.00×) | 27151 | PASS |
| 3_partitioner_v6 | Partitioner v6: on-chip copy, 10x reuse | branch partitioner-v6 | 10052 (0.101 ms) | -17019 (2.69×) | 18052 | PASS |
| 4_burst_datapath | Burst data path: PL reads A/B and writes C in PS DDR | branch burst-datapath | 10073 (0.101 ms) | +21 (1.00×) | 18153 | PASS |

**Estimated end-to-end time** (CPU load + PL at L=20 + CPU read-back) — CPU parts are ESTIMATES until measured on the board

| Step | CPU mode | CPU load (µs) | PL (µs) | CPU read-back (µs) | End-to-end (µs) | vs previous | vs baseline |
|---|---|---:|---:|---:|---:|---:|---:|
| 0_baseline | single | 1500 | 1012 | 750 | 3262 | — | 1.00× |
| 1_partitioner_v5b | single | 1500 | 272 | 750 | 2522 | 1.29× | 1.29× |
| 2_writer_fix | single | 1500 | 271 | 750 | 2521 | 1.00× | 1.29× |
| 3_partitioner_v6 | single | 1500 | 101 | 750 | 2351 | 1.07× | 1.39× |
| 4_burst_datapath | burst | 31 | 101 | 66 | 198 | 11.90× | 16.51× |
