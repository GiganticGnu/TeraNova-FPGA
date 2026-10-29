"""Run tb_chain_rtl (real HLS RAM_INTERFACE + AXI memory model): functional check + PERF counters.
usage: python3 run_rtl.py [hello|random] [B_LATENCY] [W_STALL_N] [RUNS]"""
import subprocess, sys, json
from run_perf import data, N, M64
def run(kind='hello', blat=20, wstall=0, runs=1):
    A, B = data(kind)
    open('a_b.hex', 'w').write(''.join('%016X\n' % v for v in A + B))
    r = subprocess.run(['ghdl', '-r', '--std=08', '-frelaxed', 'tb_chain_rtl', '-gB_LATENCY=%d' % blat,
                        '-gW_STALL_N=%d' % wstall, '-gRUNS=%d' % runs, '--ieee-asserts=disable'], capture_output=True, text=True)
    perf = {}
    for line in r.stdout.splitlines():
        if line.startswith('PERF '):
            k, v = line[5:].split('='); perf[k] = int(v)
        if 'blocks_written=' in line:
            perf['tb_cycles'] = int(line.split('cycles=')[1].split()[0])
            perf['done'] = "done='1'" in line
        if 'run2 blocks_total=' in line:
            perf['run2_blocks_total'] = int(line.split('blocks_total=')[1].split()[0])
            perf['run2_cycles'] = int(line.split('run2_cycles=')[1].split()[0])
            perf['run2_done'] = "done='1'" in line
    perf['errors_reported'] = (r.stdout + r.stderr).count('(report error)')
    C = [int(x, 16) for x in open('c_out.hex').read().split()]
    perf['mismatches'] = sum(1 for i in range(N) for j in range(N)
                             if C[i*N+j] != sum(A[i*N+k]*B[k*N+j] for k in range(N)) & M64)
    perf.update(data=kind, b_latency=blat, w_stall_n=wstall, runs=runs)
    return perf
if __name__ == '__main__':
    a = sys.argv[1:] + [None] * 4
    print(json.dumps(run(a[0] or 'hello', int(a[1] or 20), int(a[2] or 0), int(a[3] or 1))))
