"""plot_waveform.py -- draw the first 13 branches of the loop10 VCD as a timing diagram.

Owner: Sarvesh  |  Project 5: Dynamic Branch Prediction Unit
Output: results/charts/waveform_loop10.png  (run after make wave)
"""
import re, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

want = ["clk", "pc", "counter_state", "pred_taken", "actual_taken", "btb_hit",
        "mispredict", "flush", "next_pc"]
ids, scope, changes, t = {}, [], {}, 0
for line in open("results/waveforms/predictor_loop10.vcd"):
    s = line.split()
    if not s: continue
    if s[0] == "$scope": scope.append(s[2])
    elif s[0] == "$upscope": scope.pop()
    elif s[0] == "$var" and scope == ["tb_predictor"] and s[4] in want:
        ids[s[3]] = s[4]
    elif s[0].startswith("#"): t = int(s[0][1:])
    elif s[0][0] in "01xz" and s[0][1:] in ids:
        changes.setdefault(ids[s[0][1:]], []).append((t, s[0][0]))
    elif s[0][0] == "b" and len(s) == 2 and s[1] in ids:
        v = s[0][1:]
        changes.setdefault(ids[s[1]], []).append((t, int(v, 2) if set(v) <= {"0", "1"} else None))

PER = 10000                       # ps per clock
t0 = next(ct for ct, cv in changes["pc"] if cv)          # first branch driven
t1 = t0 + 13 * PER                                        # first 13 branches
def value_at(name, tt):
    v = None
    for ct, cv in changes[name]:
        if ct <= tt: v = cv
        else: break
    return v

fig, ax = plt.subplots(figsize=(11, 5.2))
row_h, ink, quiet, accent = 1.0, "#0b0b0b", "#52514e", "#2a78d6"
labels = {"clk": "clk", "pc": "pc", "counter_state": "counter_state", "pred_taken": "pred_taken",
          "actual_taken": "actual_taken", "btb_hit": "btb_hit", "mispredict": "mispredict",
          "flush": "flush", "next_pc": "next_pc"}
for r, name in enumerate(want):
    y = (len(want) - 1 - r) * row_h * 1.25
    ax.text(t0 - 400, y + 0.35, labels[name], ha="right", va="center", fontsize=10, color=ink, family="monospace")
    ev = [(ct, cv) for ct, cv in changes[name] if ct < t1]
    pts = sorted({t0} | {ct for ct, _ in ev if ct > t0} | {t1})
    bus = name in ("pc", "counter_state", "next_pc")
    for a, b in zip(pts, pts[1:]):
        v = value_at(name, a)
        if bus:
            ax.plot([a + 150, b - 150], [y + 0.7, y + 0.7], color=quiet, lw=1)
            ax.plot([a + 150, b - 150], [y, y], color=quiet, lw=1)
            if b - a >= PER * 0.45 and v is not None:
                txt = f"{v:02b}" if name == "counter_state" else f"{v & 0xFFFF:04x}"
                ax.text((a + b) / 2, y + 0.35, txt, ha="center", va="center", fontsize=8.5, color=ink, family="monospace")
        else:
            lvl = 0.7 if str(v) == "1" else 0
            col = accent if name in ("mispredict", "flush") and lvl else quiet
            ax.plot([a, b], [y + lvl, y + lvl], color=col, lw=1.8 if col == accent else 1.2)
            nv = value_at(name, b)
            if b < t1 and str(nv) != str(v):
                ax.plot([b, b], [y, y + 0.7], color=quiet, lw=1.2)
# branch labels under the diagram
for k in range(13):
    mid = t0 + k * PER + PER // 2
    ax.text(mid, -0.75, f"br {k}", ha="center", fontsize=8, color=quiet)
for k, note in ((0, "cold miss"), (9, "loop exit"), (10, "re-entry OK")):
    ax.text(t0 + k * PER + PER // 2, -1.35, note, ha="center", fontsize=8.5, color=accent if k != 10 else ink, weight="bold")
ax.set_xlim(t0 - 9000, t1 + 300)
ax.set_ylim(-1.7, len(want) * 1.25)
ax.axis("off")
ax.set_title("2-bit predictor on loop10: flush only at the cold start and the loop exit",
             loc="left", fontsize=12, color=ink)
fig.tight_layout()
fig.savefig("results/charts/waveform_loop10.png", dpi=160, facecolor="white")
print("ok")
