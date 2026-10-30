"""Figures of the improvement ladder for the simulation report (reads ladder_results.json + ladder.json)."""
import json, os, matplotlib
HERE = os.path.dirname(os.path.abspath(__file__))
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib import font_manager as fm
for f in fm.findSystemFonts():
    try: fm.fontManager.addfont(f)
    except Exception: pass
plt.rcParams.update({'font.family': ['Latin Modern Roman', 'DejaVu Serif'], 'font.size': 9, 'axes.edgecolor': '#52514e',
                     'axes.labelcolor': '#0b0b0b', 'xtick.color': '#52514e', 'ytick.color': '#52514e',
                     'axes.spines.top': False, 'axes.spines.right': False, 'pdf.fonttype': 42, 'hatch.linewidth': 0.6})
BLUE, ORANGE, GRID, INK, INK2, NEUTRAL = '#2a78d6', '#eb6834', '#e6e5e0', '#0b0b0b', '#52514e', '#c3c2b7'
R = json.load(open(os.path.join(HERE, 'ladder_results.json')))
C = json.load(open(os.path.join(HERE, 'ladder.json')))
OUT = os.environ.get('FIG_OUT', os.path.join(HERE, '..', 'report', 'simulation_report', 'figures', ''))
os.makedirs(OUT, exist_ok=True)
labels = ['0 Baseline', '1 Partitioner\nv5b', '2 Writer\nfix', '3 Partitioner\nv6', '4 Burst\ndata path']

# ---- Figure: PL run time per rung, nominal and stress latency ---------------
nom = [r['cycles_nominal'] / 100.0 for r in R]
st = [r['cycles_stress'] / 100.0 for r in R]
fig, ax = plt.subplots(figsize=(6.3, 2.6))
x = range(len(R)); w = 0.36
ax.yaxis.grid(True, color=GRID, lw=0.6); ax.set_axisbelow(True)
b1 = ax.bar([i - w / 2 - 0.01 for i in x], nom, w, color=BLUE, label='L = %d cycles (nominal)' % C['nominal_latency'])
b2 = ax.bar([i + w / 2 + 0.01 for i in x], st, w, color=ORANGE, label='L = %d cycles (stress)' % C['stress_latency'])
for i, v in enumerate(nom):
    ax.text(i - w / 2 - 0.01, v + 12, '%.0f' % v, ha='center', va='bottom', fontsize=7.5, color=INK)
for i, v in enumerate(st):
    ax.text(i + w / 2 + 0.01, v + 12, '%.0f' % v, ha='center', va='bottom', fontsize=7.5, color=INK2)
ax.set_xticks(list(x)); ax.set_xticklabels(labels, fontsize=8)
ax.set_ylabel('PL run time (µs, 100 MHz)'); ax.set_ylim(0, 1150)
ax.tick_params(axis='x', length=0)
ax.legend(frameon=False, fontsize=8, loc='upper right')
fig.tight_layout(); fig.savefig(OUT + 'ladder_pl.pdf'); plt.close(fig)

# ---- Figure: estimated end-to-end time per rung ------------------------------
est = C['cpu_estimates']
def cpu(mode):
    if mode == 'single':
        return 10000 * est['t_bram_write_ns'] / 1000.0, 2500 * est['t_plddr_read_ns'] / 1000.0
    lines = lambda b: (b + 63) // 64
    load = 2 * lines(20000) * est['t_cache_line_ns'] / 1000.0
    rb = lines(20000) * est['t_cache_line_ns'] / 1000.0 + 2500 * est['t_ddr_read_ns'] / 1000.0
    return load, rb
fig, ax = plt.subplots(figsize=(6.3, 2.7))
ax.xaxis.grid(True, color=GRID, lw=0.6); ax.set_axisbelow(True)
for i, r in enumerate(R):
    y = len(R) - 1 - i
    ld, rb = cpu(r.get('cpu_mode', 'single'))
    pl = r['cycles_nominal'] / 100.0
    segs = [(ld, NEUTRAL, '////', 'CPU load (estimate)'), (pl, BLUE, None, 'PL run (simulated, L = 20)'),
            (rb, '#9a9890', '\\\\\\\\', 'CPU read-back (estimate)')]
    left = 0
    for v, c, h, lab in segs:
        ax.barh(y, v, left=left, height=0.6, color=c, hatch=h, edgecolor='#fcfcfb', linewidth=1.2,
                label=lab if i == 0 else None)
        left += v
    ax.text(left + 30, y, '%.0f µs' % left, va='center', fontsize=8, color=INK)
ax.set_yticks(range(len(R))); ax.set_yticklabels([l.replace('\n', ' ') for l in labels][::-1], fontsize=8)
ax.tick_params(axis='y', length=0); ax.spines['left'].set_visible(False)
ax.set_xlabel('Time for one 50×50 multiplication (µs)'); ax.set_xlim(0, 3700)
ax.legend(frameon=False, fontsize=7.5, loc='lower center', bbox_to_anchor=(0.5, 1.0), ncol=3)
fig.tight_layout(); fig.savefig(OUT + 'ladder_e2e.pdf'); plt.close(fig)
print('figures written to', OUT)
