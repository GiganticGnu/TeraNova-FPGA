"""Stage-timing figure for the rung-3 hardware simulation.

    python make_stage_figure.py <sim log> [latency sweep csv]

Reads the CSV,stage lines of tb_rung3_hw (run 1) and writes
rung3_stage_timing.png / .pdf next to the log.
Panel a: every stage of one run (CPU parts are a MODEL, PL parts are RTL).
Panel b: the PL run as a timeline: which blocks are active when.
Panel c: PL time vs DDR4 write-response latency (sweep), with the board value.
"""
import sys, os, csv
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

log = sys.argv[1]
sweep = sys.argv[2] if len(sys.argv) > 2 else None
st = {}
for line in open(log):
    p = line.strip().split(",")
    if len(p) == 6 and p[0] == "CSV" and p[1] == "stage" and p[2] == "1":
        st[p[3]] = (int(p[4]), int(p[5]))

INK, INK2, GRID, SURF = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
CPU, PL = "#2a78d6", "#eb6834"           # categorical slots 1 and 2
plt.rcParams.update({"font.size": 9, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2, "figure.facecolor": SURF,
                     "axes.facecolor": SURF})

fig = plt.figure(figsize=(11, 8.2))
gs = fig.add_gridspec(2, 2, height_ratios=[1.15, 1], hspace=0.45, wspace=0.28)

# ---------------- a: all stages of one run
rows = [("A_cpu_bram_load", "CPU writes A, B into BRAMs", CPU),
        ("B_start", "Start (GPIO -> toggle2pulse)", CPU),
        ("C_onchip_copy", "PL: on-chip copy of A, B", PL),
        ("D_mult_acc", "PL: multiply + accumulate", PL),
        ("E_last_product", "PL: last product", PL),
        ("F_last_block", "PL: last C block", PL),
        ("G_last_write_done", "PL: last write response -> done", PL),
        ("H_irq", "Interrupt latency", CPU),
        ("I_cpu_readback", "CPU reads C back", CPU)]
ax = fig.add_subplot(gs[0, :])
names = [r[1] for r in rows][::-1]
vals = [(st[r[0]][1] - st[r[0]][0]) / 1000 for r in rows][::-1]
cols = [r[2] for r in rows][::-1]
ax.barh(names, vals, color=cols, height=0.62)
for y, v in enumerate(vals):
    ax.text(v + 12, y, f"{v:,.2f} µs", va="center", color=INK, fontsize=8.5)
ax.set_xlabel("time per run (µs)")
ax.set_xlim(0, max(vals) * 1.15)
ax.grid(axis="x", color=GRID, lw=0.8); ax.set_axisbelow(True)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.set_title("a  One run, stage by stage (rung 3, DDR4 write latency 40 cycles)",
             loc="left", color=INK, fontsize=10.5, fontweight="bold")
from matplotlib.patches import Patch
ax.legend(handles=[Patch(color=CPU, label="CPU / PS side (model: 150 ns per BRAM write, 300 ns per DDR4 read)"),
                   Patch(color=PL, label="PL (cycle-accurate RTL, 100 MHz)")],
          loc="center right", frameon=False, fontsize=8.5)

# ---------------- b: PL timeline
ax = fig.add_subplot(gs[1, 0])
t0 = st["B_start"][1]
lanes = [("On-chip copy (LOAD)", st["C_onchip_copy"]),
         ("Multiply + accumulate", (st["D_mult_acc"][0], st["E_last_product"][1])),
         ("Write-back to DDR4", st["W_writeback_span"]),
         ("Drain + last response", (st["E_last_product"][1], st["G_last_write_done"][1]))]
for y, (name, (a, b)) in enumerate(lanes[::-1]):
    ax.barh(y, (b - a) / 1000, left=(a - t0) / 1000, color=PL, height=0.55)
    ax.text((b - t0) / 1000 + 1.5, y, f"{(b - a) / 1000:.1f} µs", va="center", fontsize=8, color=INK)
ax.set_yticks(range(len(lanes))); ax.set_yticklabels([l[0] for l in lanes][::-1])
done = (st["G_last_write_done"][1] - t0) / 1000
ax.axvline(done, color=INK2, lw=1, ls=(0, (3, 3)))
ax.text(done + 1, 2.5, f"done\n{done:.1f} µs", color=INK2, fontsize=8, ha="left", va="center")
ax.set_xlim(0, done * 1.22); ax.set_xlabel("µs after the start pulse")
ax.grid(axis="x", color=GRID, lw=0.8); ax.set_axisbelow(True)
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.set_title("b  Inside the PL: write-back overlaps the multiply", loc="left",
             color=INK, fontsize=10.5, fontweight="bold")

# ---------------- c: latency sweep
ax = fig.add_subplot(gs[1, 1])
if sweep and os.path.exists(sweep):
    L, T = zip(*[(int(a), float(b)) for a, b in csv.reader(open(sweep))])
    ax.plot(L, T, color=PL, lw=2, marker="o", ms=6, label="simulation (rung 3)")
    ax.axhline(123, color=CPU, lw=2, ls=(0, (4, 3)), label="board, Badr (123 µs, incl. IRQ)")
    for l, t in zip(L, T):
        ax.annotate(f"{t:.0f}", (l, t), textcoords="offset points", xytext=(0, 7),
                    ha="center", fontsize=8, color=INK)
    ax.set_xlabel("DDR4 write-response latency (cycles of 10 ns)")
    ax.set_ylabel("PL time, start -> done (µs)")
    ax.set_ylim(0, max(T) * 1.18)
    ax.legend(frameon=False, fontsize=8, loc="lower right")
    ax.grid(color=GRID, lw=0.8); ax.set_axisbelow(True)
    for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.set_title("c  The writer waits for every block's responses", loc="left",
             color=INK, fontsize=10.5, fontweight="bold")

out = os.path.join(os.path.dirname(os.path.abspath(log)), "rung3_stage_timing")
fig.savefig(out + ".png", dpi=170, bbox_inches="tight")
fig.savefig(out + ".pdf", bbox_inches="tight")
print("wrote", out + ".png/.pdf")
