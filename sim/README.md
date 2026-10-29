# RTL simulation of the PL data path (GHDL)

`tb_chain.vhd` connects a BRAM model, `matrix_partitioner_B` (newest), two
`matrix_to_ports`, `MatMul5x5_PAR_IF`, `MatMul5x5_Accumulator` (10 accumulations)
and a model of the new `RAM_INTERFACE` handshake (ap_fifo). `run.py` writes the
input matrices, runs the simulation and compares the 50x50 result with Python.

    for f in MatMul5x5.vhd MatMul5x5_IF_IN.vhd MatMul5x5_Accumulator.vhd matrix_to_ports.vhd matrix_partitioner_B.vhd tb_chain.vhd; do ghdl -a --std=08 -frelaxed $f; done
    ghdl -e --std=08 -frelaxed tb_chain
    python3 run.py                          # normal writer
    python3 run.py -gWRITE_BUSY_CYCLES=1500 # slow writer (back-pressure)

Results (Oct 2026): all PASS, 101 008 cycles for one 50x50 multiplication.
The same testbench can be opened in the Vivado simulator (add the files, set
tb_chain as top, put a_b.hex in the simulation run directory).
