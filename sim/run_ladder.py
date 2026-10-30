"""Improvement ladder: simulate the system after every change, in order.

    python run_ladder.py                 all steps whose sources exist
    python run_ladder.py 2_writer_fix    one step (others are taken from ladder_results.json)
    python run_ladder.py --from 1_partitioner_v5b

Steps are defined in ladder.json and are cumulative: each step inherits the
sources of the previous one and overrides only the slots it names.
For every step:
  * correctness: helloworld data, random 64-bit data, restart without reset
  * PL run time (start -> done, real RAM_INTERFACE RTL) at the nominal and
    the stress write-response latency L
  * gain against the previous step and against the baseline
Results: ladder_results.json (all steps), ladder.md (table).
Each step is built in build_ladder/<id>/ with copies of its sources;
ghdl -i / -m works out the compile order, so a step may add files.
"""
import glob, json, os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
OPT = ['--std=08', '-frelaxed']
os.chdir(HERE)
CFG = json.load(open('ladder.json'))
LN, LS = CFG['nominal_latency'], CFG['stress_latency']

def resolve():
    """Cumulative source set per step."""
    out, cur = [], {}
    for st in CFG['steps']:
        cur = dict(cur); cur.update(st['sources'])
        out.append((st, cur))
    return out

def files_of(src):
    fs = []
    for slot, v in src.items():
        if isinstance(v, str):                       # a folder (HLS RTL)
            fs += sorted(glob.glob(os.path.join(v, '*.vhd')))
        else:
            fs += v
    return fs

def available(src):
    return all(os.path.exists(f) for f in files_of(src)) and \
           all(glob.glob(os.path.join(v, '*.vhd')) for v in src.values() if isinstance(v, str))

def sh(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-3000:] + r.stderr[-3000:]); sys.exit('failed: ' + ' '.join(cmd))

def run_step(st, src):
    d = os.path.join(HERE, 'build_ladder', st['id'])
    shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    for f in files_of(src):
        shutil.copy(f, d)
    for f in ['run_perf.py', 'run_rtl.py']: shutil.copy(f, d)
    os.chdir(d); sys.path.insert(0, d)
    for m in ['run_perf', 'run_rtl']: sys.modules.pop(m, None)
    import run_perf, run_rtl
    A, B = run_perf.data('hello')
    open('a_b.hex', 'w').write(''.join('%016X\n' % v for v in A + B))
    sh(['ghdl', '-i'] + OPT + sorted(glob.glob('*.vhd')))
    sh(['ghdl', '-m'] + OPT + ['tb_chain_rtl'])
    res = {'id': st['id'], 'name': st['name'], 'git': st['git'], 'sources': src,
           'cpu_mode': st.get('cpu_mode', 'single')}
    p = run_rtl.run('hello', LN, 0);        res['nominal'] = p
    q = run_rtl.run('random', LN, 0);       res['random'] = q
    r = run_rtl.run('hello', LN, 0, 2);     res['restart'] = r
    s = run_rtl.run('hello', LS, 0);        res['stress'] = s
    ok = (p['mismatches'] == 0 and q['mismatches'] == 0 and r['mismatches'] == 0 and s['mismatches'] == 0
          and p['done'] and q['done'] and s['done'] and r.get('run2_done') and r.get('run2_blocks_total') == 200
          and q['tb_cycles'] == p['tb_cycles'] and r.get('run2_cycles') == p['tb_cycles']
          and sum(x.get('errors_reported', 0) for x in (p, q, r, s)) == 0)
    res['pass'] = bool(ok)
    res['cycles_nominal'] = p['tb_cycles']
    res['cycles_stress'] = s['tb_cycles']
    res['pair_interval'] = p.get('pair_interval_max')
    res['block_interval'] = p.get('block_interval_max')
    res['multiplier_busy_pct'] = round(100.0 * p['multiplier_busy_cycles'] / p['tb_cycles'], 2)
    os.chdir(HERE); sys.path.remove(d)
    return res

def cpu_us(mode):
    """Estimated CPU time (us) for moving the data, per cpu_mode (see ladder.json)."""
    e = CFG['cpu_estimates']
    if mode == 'single':
        load = 10000 * e['t_bram_write_ns'] / 1000.0          # 2 x 2500 values, 2 x 32-bit writes each
        back = 2500 * e['t_plddr_read_ns'] / 1000.0
    else:
        load = (2 * 20000 / 64) * e['t_cache_line_ns'] / 1000.0                       # flush A and B
        back = (20000 / 64) * e['t_cache_line_ns'] / 1000.0 + 2500 * e['t_ddr_read_ns'] / 1000.0  # invalidate + read C
    return load, back

def table(results):
    base = results[0]
    lines = ['| Step | Change | Build from | PL cycles (L=%d) | PL vs previous | PL cycles (L=%d) | Tests |' % (LN, LS),
             '|---|---|---|---:|---:|---:|---|']
    prev = None
    for r in results:
        dn = '—' if prev is None else '%+d (%.2f×)' % (r['cycles_nominal'] - prev['cycles_nominal'],
                                                       prev['cycles_nominal'] / r['cycles_nominal'])
        lines.append('| %s | %s | %s | %d (%.3f ms) | %s | %d | %s |' % (
            r['id'], r['name'], r['git'], r['cycles_nominal'], r['cycles_nominal'] / 1e5, dn,
            r['cycles_stress'], 'PASS' if r['pass'] else 'FAIL'))
        prev = r
    est = '' if CFG['cpu_estimates'].get('measured') else ' — CPU parts are ESTIMATES until measured on the board'
    lines += ['', '**Estimated end-to-end time** (CPU load + PL at L=%d + CPU read-back)%s' % (LN, est), '',
              '| Step | CPU mode | CPU load (µs) | PL (µs) | CPU read-back (µs) | End-to-end (µs) | vs previous | vs baseline |',
              '|---|---|---:|---:|---:|---:|---:|---:|']
    prev = base_t = None
    for r in results:
        load, back = cpu_us(r.get('cpu_mode', 'single'))
        pl = r['cycles_nominal'] / 100.0
        t = load + pl + back
        if base_t is None: base_t = t
        vp = '—' if prev is None else '%.2f×' % (prev / t)
        lines.append('| %s | %s | %.0f | %.0f | %.0f | %.0f | %s | %.2f× |' % (
            r['id'], r.get('cpu_mode', 'single'), load, pl, back, t, vp, base_t / t))
        prev = t
    return '\n'.join(lines)

if __name__ == '__main__':
    steps = resolve()
    ids = [s['id'] for s, _ in steps]
    args = sys.argv[1:]
    if args[:1] == ['--from']:
        todo = ids[ids.index(args[1]):]
    elif args:
        todo = args
    else:
        todo = ids
    old = {}
    if os.path.exists('ladder_results.json'):
        old = {r['id']: r for r in json.load(open('ladder_results.json'))}
    for st, src in steps:
        if st['id'] not in todo: continue
        if not available(src):
            print('%-20s skipped: sources not there yet (%s)' % (st['id'], ', '.join(
                v for v in src.values() if isinstance(v, str) and not glob.glob(os.path.join(v, '*.vhd')))))
            continue
        print('%-20s running ...' % st['id'], flush=True)
        r = run_step(st, src); old[st['id']] = r
        print('%-20s %s  L=%d: %d cycles   L=%d: %d cycles' % (st['id'], 'PASS' if r['pass'] else 'FAIL',
              LN, r['cycles_nominal'], LS, r['cycles_stress']), flush=True)
    results = [old[i] for i in ids if i in old]
    for st, _ in steps:                       # keep cpu_mode in sync with ladder.json
        if st['id'] in old: old[st['id']]['cpu_mode'] = st.get('cpu_mode', 'single')
    json.dump(results, open('ladder_results.json', 'w'), indent=1)
    t = table(results)
    open('ladder.md', 'w').write('# Improvement ladder (PL run time, simulated)\n\n'
        'PL: cycles from start to done at 100 MHz, real RTL of every block, AXI memory latency L.\n\n' + t + '\n')
    print('\n' + t)
