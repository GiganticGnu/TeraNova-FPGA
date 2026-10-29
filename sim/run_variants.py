"""Simulate the partitioner variants against the same testbenches.

    python run_variants.py            (about 10 minutes)

rev4 = matrix_partitioner_B.vhd (current design)
v5a  = variants/matrix_partitioner_B_v5a.vhd (WAIT1/WAIT2 removed)
v5b  = variants/matrix_partitioner_B_v5b.vhd (pipelined, one address per cycle)

Each variant is built in its own folder build_<name>/ with copies of all
sources, so the variants never mix (they can run in parallel:
python run_variants.py rev4, ... v5a, ... v5b). Results go to
variants_results_<name>.json and are merged into variants_results.json.
"""
import json, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OPT = ['--std=08', '-frelaxed']
VARIANTS = {'rev4': 'matrix_partitioner_B.vhd',
            'v5a': 'variants/matrix_partitioner_B_v5a.vhd',
            'v5b': 'variants/matrix_partitioner_B_v5b.vhd'}
SWEEP = {'rev4': [1, 20, 100, 180, 185, 186, 187, 190, 200],
         'v5a': [1, 20, 50, 80, 85, 86, 87, 88, 90, 100, 150, 200],
         'v5b': [1, 10, 20, 30, 35, 36, 37, 38, 40, 50, 100, 200]}
COMMON = ['MatMul5x5.vhd', 'MatMul5x5_IF_IN.vhd', 'MatMul5x5_Accumulator.vhd', 'matrix_to_ports.vhd']
HLS = ['RAM_INTERFACE_flow_control_loop_pipe_sequential_init.vhd', 'RAM_INTERFACE_mac_muladd_6ns_3ns_12ns_12_4_1.vhd',
       'RAM_INTERFACE_mac_muladd_8ns_4ns_7ns_12_4_1.vhd', 'RAM_INTERFACE_partselect_64ns_1600ns_11ns_64_1_1.vhd',
       'RAM_INTERFACE_gmem_m_axi.vhd', 'RAM_INTERFACE_RAM_INTERFACE_Pipeline_ROWS_COLS.vhd', 'RAM_INTERFACE.vhd']
TBS = ['axi_mem_model.vhd', 'tb_chain.vhd', 'tb_chain_perf.vhd', 'tb_chain_rtl.vhd']
PY = ['run.py', 'run_perf.py', 'run_rtl.py']

def sh(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout + r.stderr); sys.exit('failed: ' + ' '.join(cmd))

only = sys.argv[1:] or list(VARIANTS)
allres = {}
for name in only:
    os.chdir(HERE)
    d = os.path.join(HERE, 'build_' + name)
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    for f in COMMON + TBS + PY: shutil.copy(f, d)
    for f in HLS: shutil.copy(os.path.join('hls_rtl', f), d)
    shutil.copy(VARIANTS[name], os.path.join(d, 'matrix_partitioner_B.vhd'))
    os.chdir(d)
    sys.path.insert(0, d)
    import run_perf, run_rtl
    A, B = run_perf.data('hello')
    open('a_b.hex', 'w').write(''.join('%016X\n' % v for v in A + B))
    for f in COMMON + ['matrix_partitioner_B.vhd'] + HLS + TBS: sh(['ghdl', '-a'] + OPT + [f])
    for top in ['tb_chain', 'tb_chain_perf', 'tb_chain_rtl']: sh(['ghdl', '-e'] + OPT + [top])
    res = {'chain': [], 'perf': [], 'rtl': [], 'restart': [], 'latency_sweep': []}
    for gen in [[], ['-gWRITE_BUSY_CYCLES=1500']]:
        out = subprocess.run([sys.executable, 'run.py'] + gen, capture_output=True, text=True).stdout
        for kind, line in zip(['hello', 'random'], [l for l in out.splitlines() if 'PASS' in l or 'FAIL' in l]):
            res['chain'].append({'data': kind, 'generics': gen, 'mismatches': 0 if line.strip() == 'PASS' else 1})
            print('%s chain %-6s %-26s %s' % (name, kind, ' '.join(gen) or 'normal writer', line.strip()))
    for kind in ['hello', 'random']:
        p = run_perf.run(kind, 30); res['perf'].append(p)
        print('%s perf %-6s cycles=%d pair_interval=%d mult_busy=%d mismatches=%d'
              % (name, kind, p['tb_cycles'], p['pair_interval_max'], p['multiplier_busy_cycles'], p['mismatches']))
        p = run_rtl.run(kind, 20, 0); res['rtl'].append(p)
        print('%s rtl  %-6s cycles=%d mismatches=%d' % (name, kind, p['tb_cycles'], p['mismatches']))
        p = run_rtl.run(kind, 20, 0, 2); res['restart'].append(p)
        print('%s restart %-6s run2_cycles=%s blocks_total=%s run2_done=%s mismatches(run 2)=%d'
              % (name, kind, p.get('run2_cycles'), p.get('run2_blocks_total'), p.get('run2_done'), p['mismatches']))
    for bl in SWEEP[name]:
        p = run_rtl.run('hello', bl, 0); res['latency_sweep'].append(p)
        print('%s rtl  L=%3d cycles=%d acc_stall=%d mismatches=%d' % (name, bl, p['tb_cycles'], p['accumulator_stalled_cycles'], p['mismatches']))
    allres[name] = res
    sys.path.remove(d)
    for m in ['run_perf', 'run_rtl']: sys.modules.pop(m, None)
os.chdir(HERE)
for name, r in allres.items():
    json.dump(r, open('variants_results_%s.json' % name, 'w'), indent=1)
merged = {}
for name in VARIANTS:
    f = 'variants_results_%s.json' % name
    if os.path.exists(f): merged[name] = json.load(open(f))
json.dump(merged, open('variants_results.json', 'w'), indent=1)
bad = sum(p['mismatches'] + p.get('errors_reported', 0) for r in allres.values() for v in r.values() for p in v)
bad += sum(1 for r in allres.values() for p in r['restart'] if p.get('run2_blocks_total') != 200 or not p.get('run2_done'))
print('\nALL PASS' if bad == 0 else '\n%d PROBLEMS' % bad)
