import random, subprocess, sys
N = 50
M64 = (1 << 64) - 1

def run(name, A, B):
    with open('a_b.hex', 'w') as f:
        for v in A + B:
            f.write('%016X\n' % v)
    r = subprocess.run(['ghdl', '-r', '--std=08', '-frelaxed', 'tb_chain', '--ieee-asserts=disable'] + sys.argv[1:] + ['--ieee-asserts=disable'],
                       capture_output=True, text=True)
    print(name, '|', (r.stdout + r.stderr).strip().splitlines()[-1])
    C = [int(x, 16) for x in open('c_out.hex').read().split()]
    err = 0
    for i in range(N):
        for j in range(N):
            ref = sum(A[i*N+k] * B[k*N+j] for k in range(N)) & M64
            if C[i*N+j] != ref:
                if err < 5: print('  mismatch (%d,%d): got %x expected %x' % (i, j, C[i*N+j], ref))
                err += 1
    print('  ', 'PASS' if err == 0 else 'FAIL (%d mismatches)' % err)
    return err

errs = 0
# 1) the test data used in helloworld.c
A = [i*N + j + 1 for i in range(N) for j in range(N)]
B = [i*N + j + 2 for i in range(N) for j in range(N)]
errs += run('helloworld data', A, B)
# 2) full-range random 64-bit data (checks signed/unsigned and wrap-around)
random.seed(1)
A = [random.getrandbits(64) for _ in range(N*N)]
B = [random.getrandbits(64) for _ in range(N*N)]
errs += run('random 64-bit', A, B)
sys.exit(1 if errs else 0)
