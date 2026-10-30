# Improvement ladder (PL run time, simulated)

Cycles from start to done at 100 MHz, real RAM_INTERFACE RTL, AXI write-response latency L.

| Step | Change | Build from | PL cycles (L=20) | vs previous | vs baseline | PL cycles (L=100) | vs previous | Tests |
|---|---|---|---:|---:|---:|---:|---:|---|
| 0_baseline | Baseline: restored design | tag baseline-1 | 101186 (1.012 ms) | — | 1.00× | 101586 | — | PASS |
| 1_partitioner_v5b | Partitioner v5b: pipelined fetch | branch partitioner-v5b | 27186 (0.272 ms) | -74000 (3.72×) | 3.72× | 58576 | -43010 (1.73×) | PASS |
| 2_writer_fix | Writer: overlapped write responses | branch writer-fix | 27071 (0.271 ms) | -115 (1.00×) | 3.74× | 27151 | -31425 (2.16×) | PASS |
