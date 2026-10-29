"""Run every PL simulation of the TeraNova accelerator and write results.json.

Needs GHDL (VHDL-2008) and Python 3 on the PATH. Run from C:\\PLD\\sim:
    python run_all.py            (about 12 minutes)

1. tb_chain       original functional testbench (writer model), 2 data sets,
                  normal and slow (1500 cycles/block) writer
2. tb_chain_perf  same + handshake monitors: cycles per stage
                  + sweep of the writer model's busy time per block
3. tb_chain_rtl   real Vitis-HLS RAM_INTERFACE RTL (hls_rtl/) + AXI4 memory model
                  + sweep of the write-response latency and a throttled W channel
"""
import json, os, subprocess, sys
os.chdir(os.path.dirname(os.path.abspath(__file__)))
G = ['ghdl']; OPT = ['--std=08', '-frelaxed']
SRC = ['MatMul5x5.vhd', 'MatMul5x5_IF_IN.vhd', 'MatMul5x5_Accumulator.vhd', 'matrix_to_ports.vhd',
       'matrix_partitioner_B.vhd',
       'hls_rtl/RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd',
       'hls_rtl/RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd',
       'hls_rtl/RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd',
       'hls_rtl/RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd',
       'hls_rtl/RAM_INTERFACE_gmem_m_axi.vhd',
       'hls_rtl/RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd',
       'hls_rtl/RAM_INTERFACE.vhd',
       'axi_mem_model.vhd', 'tb_chain.vhd', 'tb_chain_perf.vhd', 'tb_chain_rtl.vhd']

def sh(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout + r.stderr); sys.exit('failed: ' + ' '.join(cmd))
    return r.stdout

print('analyse + elaborate ...')
import run_perf
A, B = run_perf.data('hello')
open('a_b.hex', 'w').write(''.join('%016X\n' % v for v in A + B))  # elaboration opens it
for f in SRC: sh(G + ['-a'] + OPT + [f])
for top in ['tb_chain', 'tb_chain_perf', 'tb_chain_rtl']: sh(G + ['-e'] + OPT + [top])

import run_perf, run_rtl
res = {'chain': [], 'perf': [], 'writer_sweep': [], 'rtl': [], 'latency_sweep': []}
# 1) original functional testbench (writer model), normal and slow writer
for gen in [[], ['-gWRITE_BUSY_CYCLES=1500']]:
    out = subprocess.run([sys.executable, 'run.py'] + gen, capture_output=True, text=True).stdout
    for kind, line in zip(['hello', 'random'], [l for l in out.splitlines() if 'PASS' in l or 'FAIL' in l]):
        ok = line.strip() == 'PASS'
        res['chain'].append({'data': kind, 'generics': gen, 'mismatches': 0 if ok else 1})
        print('chain %-6s %-26s %s' % (kind, ' '.join(gen) or 'normal writer', line.strip()))
for kind in ['hello', 'random']:
    p = run_perf.run(kind, 30); res['perf'].append(p)
    print('perf  %-6s cycles=%d mismatches=%d' % (kind, p['tb_cycles'], p['mismatches']))
for wb in [30, 78, 250, 500, 750, 1000, 1010, 1020, 1100, 1250, 1500]:
    p = run_perf.run('hello', wb); res['writer_sweep'].append(p)
    print('writer model busy=%4d cycles=%d mismatches=%d' % (wb, p['tb_cycles'], p['mismatches']))
for kind in ['hello', 'random']:
    p = run_rtl.run(kind, 20, 0); res['rtl'].append(p)
    print('rtl   %-6s cycles=%d mismatches=%d' % (kind, p['tb_cycles'], p['mismatches']))
for bl, ws in [(1, 0), (20, 0), (50, 0), (100, 0), (150, 0), (180, 0), (190, 0), (200, 0), (300, 0), (500, 0), (20, 2), (20, 4)]:
    p = run_rtl.run('hello', bl, ws); res['latency_sweep'].append(p)
    print('rtl   B_LATENCY=%3d W_STALL_N=%d cycles=%d mismatches=%d' % (bl, ws, p['tb_cycles'], p['mismatches']))
json.dump(res, open('results.json', 'w'), indent=1)
bad = sum(p['mismatches'] + p.get('errors_reported', 0) for v in res.values() for p in v)
print('\nALL PASS' if bad == 0 else '\n%d PROBLEMS' % bad)
