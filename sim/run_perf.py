"""Run tb_chain_perf: functional check against Python + PERF counters.
usage: python3 run_perf.py [data] [WRITE_BUSY_CYCLES]   data = hello | random"""
import random, subprocess, sys, json
N = 50; M64 = (1 << 64) - 1
def data(kind):
    if kind == 'hello':
        return ([i*N+j+1 for i in range(N) for j in range(N)], [i*N+j+2 for i in range(N) for j in range(N)])
    random.seed(1)
    return ([random.getrandbits(64) for _ in range(N*N)], [random.getrandbits(64) for _ in range(N*N)])
def run(kind='hello', wb=30):
    A, B = data(kind)
    open('a_b.hex', 'w').write(''.join('%016X\n' % v for v in A + B))
    r = subprocess.run(['ghdl', '-r', '--std=08', '-frelaxed', 'tb_chain_perf', '-gWRITE_BUSY_CYCLES=%d' % wb,
                        '--ieee-asserts=disable'], capture_output=True, text=True)
    perf = {}
    for line in r.stdout.splitlines():
        if line.startswith('PERF '):
            k, v = line[5:].split('='); perf[k] = int(v)
        if 'blocks_written=' in line:
            perf['tb_cycles'] = int(line.split('cycles=')[1])
    C = [int(x, 16) for x in open('c_out.hex').read().split()]
    err = sum(1 for i in range(N) for j in range(N)
              if C[i*N+j] != sum(A[i*N+k]*B[k*N+j] for k in range(N)) & M64)
    perf.update(data=kind, write_busy=wb, mismatches=err)
    return perf
if __name__ == '__main__':
    kind = sys.argv[1] if len(sys.argv) > 1 else 'hello'
    wb = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    print(json.dumps(run(kind, wb)))
