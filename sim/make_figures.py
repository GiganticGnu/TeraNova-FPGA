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
                     'axes.spines.top': False, 'axes.spines.right': False, 'pdf.fonttype': 42})
BLUE, ORANGE, GRID, INK, INK2, NEUTRAL = '#2a78d6', '#eb6834', '#e6e5e0', '#0b0b0b', '#52514e', '#c3c2b7'
R = json.load(open(os.path.join(HERE, 'results.json')))
OUT = os.path.join(HERE, '..', 'report', 'simulation_report', 'figures', '')
os.makedirs(OUT, exist_ok=True)

# ---- Figure 1: where the 101 cycles of one block pair go -------------------
fig, ax = plt.subplots(figsize=(6.2, 1.9))
segs = [('Issue address\n25', 25, BLUE), ('WAIT1 + WAIT2 (no work)\n50', 50, NEUTRAL), ('Capture\n25', 25, BLUE), ('', 1, INK2)]
x = 0
for lab, w, c in segs:
    ax.barh(1, w, left=x, height=0.55, color=c, edgecolor='#fcfcfb', linewidth=1.5)
    if lab: ax.text(x + w / 2, 1, lab, ha='center', va='center', fontsize=8.5, color='white' if c in (BLUE, INK2) else INK)
    x += w
ax.barh(0, 5, left=0, height=0.55, color=ORANGE, edgecolor='#fcfcfb', linewidth=1.5)
ax.barh(0, 96, left=5, height=0.55, color='none', edgecolor=NEUTRAL, linewidth=0.8, hatch='////')
ax.text(7, 0, '5 busy', ha='left', va='center', fontsize=8.5, color=INK)
ax.text(5 + 96 / 2, 0, 'idle 96 of 101 cycles (95 %)', ha='center', va='center', fontsize=8.5, color=INK2,
        bbox=dict(facecolor='#fcfcfb', edgecolor='none', pad=1.5))
ax.set_yticks([1, 0]); ax.set_yticklabels(['Partitioner', 'Multiplier'])
ax.set_xlim(0, 101); ax.set_xticks([0, 25, 50, 75, 100]); ax.set_xlabel('Clock cycles per block pair (100 MHz)')
ax.tick_params(axis='y', length=0); ax.spines['left'].set_visible(False)
ax.annotate('handshake 1', xy=(100.5, 1.28), xytext=(92, 1.62), fontsize=7.5, color=INK2,
            arrowprops=dict(arrowstyle='-', color=INK2, lw=0.6))
ax.set_ylim(-0.5, 1.75)
fig.tight_layout(); fig.savefig(OUT + 'cycle_budget.pdf'); plt.close(fig)

# ---- Figure 2: when does the result writer become the bottleneck? ----------
fig, (a, b) = plt.subplots(1, 2, figsize=(6.4, 2.5), sharey=True)
ws = R['writer_sweep']
a.plot([p['write_busy'] for p in ws], [p['tb_cycles'] / 1000 for p in ws], color=BLUE, lw=2, marker='o', ms=4,
       markeredgecolor='#fcfcfb', markeredgewidth=0.8, zorder=3)
a.axvline(1009, color=INK2, lw=0.8, ls=(0, (3, 3)))
a.text(980, 140, 'writer slower than\none block per 1010 cycles', ha='right', fontsize=7.5, color=INK2)
a.set_xlabel('Writer-model busy time per block (cycles)'); a.set_ylabel('PL run time (thousand cycles)')
a.set_title('(a) Writer model (tb_chain_perf)', fontsize=9, loc='left', color=INK)
ls = [p for p in R['latency_sweep'] if p['w_stall_n'] == 0]
b.plot([p['b_latency'] for p in ls], [p['tb_cycles'] / 1000 for p in ls], color=BLUE, lw=2, marker='o', ms=4,
       markeredgecolor='#fcfcfb', markeredgewidth=0.8, zorder=3)
b.axvline(185.5, color=INK2, lw=0.8, ls=(0, (3, 3)))
b.text(495, 30, 'writer needs per block:\n85 + 5 x latency cycles', ha='right', fontsize=7.5, color=INK2)
b.set_xlabel('AXI write-response latency (cycles)')
b.set_title('(b) Real HLS RTL (tb_chain_rtl)', fontsize=9, loc='left', color=INK)
for ax in (a, b):
    ax.grid(axis='y', color=GRID, lw=0.6); ax.set_axisbelow(True)
    ax.axhline(101.008, color=ORANGE, lw=0.8); ax.set_ylim(0, 270)
a.text(40, 108, 'partitioner limit 101 008', fontsize=7.5, color=INK2)
fig.tight_layout(); fig.savefig(OUT + 'bottleneck_sweep.pdf'); plt.close(fig)
print('ok')

# ---- Figure 3: partitioner variants against memory latency (variants_results.json)
VR = os.path.join(HERE, 'variants_results.json')
if os.path.exists(VR):
    V = json.load(open(VR))
    AQUA = '#1baf7a'
    fig, ax = plt.subplots(figsize=(6.2, 2.9))
    spec = [('rev4', 'Current (rev. 4)', BLUE), ('v5a', 'Without wait states (v5a)', ORANGE),
            ('v5b', 'Pipelined (v5b)', AQUA)]
    for key, label, col in spec:
        if key not in V: continue
        pts = sorted((p['b_latency'], p['tb_cycles']) for p in V[key]['latency_sweep'])
        xs = [x for x, _ in pts]; ys = [y / 1000 for _, y in pts]
        ax.plot(xs, ys, color=col, lw=2, marker='o', ms=3.5, markeredgecolor='#fcfcfb', markeredgewidth=0.7,
                label=label, zorder=3)
    ax.set_xlim(0, 200); ax.set_ylim(0, 125)
    ax.set_xlabel('AXI write-response latency L (cycles)'); ax.set_ylabel('PL run time (thousand cycles)')
    ax.grid(axis='y', color=GRID, lw=0.6); ax.set_axisbelow(True)
    for xk, yk, txt in [(185, 102.0, 'L = 185'), (85, 51.5, 'L = 85'), (37, 27.3, 'L = 37')]:
        ax.annotate(txt, xy=(xk, yk), xytext=(xk - 4, yk + 9), ha='right', fontsize=7.5, color=INK2,
                    arrowprops=dict(arrowstyle='-', color=INK2, lw=0.6))
    ax.text(198, 40, 'above its limit every version runs\nat the writer\'s pace (same line)', ha='right', va='bottom',
            fontsize=7.5, color=INK2)
    ax.legend(loc='lower right', frameon=False, fontsize=7.5)
    fig.tight_layout(); fig.savefig(OUT + 'variants_latency.pdf'); plt.close(fig)
    print('variants figure ok')
