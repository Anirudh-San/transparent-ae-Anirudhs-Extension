#!/usr/bin/env python3
"""
Generate Fig 5 and Fig 6 from TranSPArent accuracy experiment timing data.

Usage:
    cd ~/transparent-ae-1.0.0/accuracy
    python3 plot_figures.py [path/to/repo_timings.csv]
"""

import sys
import csv
import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pathlib import Path

matplotlib.rcParams.update({"font.size": 11})

# ── Load data ──────────────────────────────────────────────────────────────
csv_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("repo_timings.csv")

if not csv_path.exists():
    print(f"ERROR: {csv_path} not found.")
    sys.exit(1)

repos = []
vanilla_sloc = []
vanilla_secs = []
transparent_sloc = []
transparent_secs = []

with open(csv_path, newline="") as f:
    reader = csv.DictReader(f)
    for row in reader:
        sloc = int(row["sloc"])
        v = int(row["vanilla_seconds"])
        t = int(row["transparent_seconds"])
        repos.append(row["repo"])
        vanilla_sloc.append(sloc)
        vanilla_secs.append(v)
        transparent_sloc.append(sloc)
        transparent_secs.append(t)

repos = np.array(repos)
vanilla_sloc = np.array(vanilla_sloc, dtype=float)
vanilla_secs = np.array(vanilla_secs, dtype=float)
transparent_sloc = np.array(transparent_sloc, dtype=float)
transparent_secs = np.array(transparent_secs, dtype=float)

n = len(repos)
print(f"Loaded {n} repos from {csv_path}")
print(
    f"Vanilla    — min:{vanilla_secs.min():.0f}s  max:{vanilla_secs.max():.0f}s  mean:{vanilla_secs.mean():.1f}s"
)
print(
    f"TranSPArent— min:{transparent_secs.min():.0f}s  max:{transparent_secs.max():.0f}s  mean:{transparent_secs.mean():.1f}s"
)


# ── Separate outliers for display purposes ─────────────────────────────────
# Use 3*IQR rule — outliers shown as stars, excluded from axis limits / fit
def outlier_mask(arr):
    q1, q3 = np.percentile(arr, [25, 75])
    return arr > q3 + 3 * (q3 - q1)


v_out = outlier_mask(vanilla_secs)
t_out = outlier_mask(transparent_secs)
either_out = v_out | t_out  # exclude from fit and axis if either is outlier

# Inlier sets used for linear fit and axis limits
vi_sloc = vanilla_sloc[~either_out]
vi_secs = vanilla_secs[~either_out]
ti_sloc = transparent_sloc[~either_out]
ti_secs = transparent_secs[~either_out]

# ── Fig 5: Scatter + linear fit ────────────────────────────────────────────
fig5, ax5 = plt.subplots(figsize=(6.5, 4.5))

# Inlier scatter
ax5.scatter(
    vi_sloc,
    vi_secs,
    color="#1f77b4",
    s=40,
    alpha=0.8,
    zorder=3,
    label="Data points (Vanilla CodeQL)",
)
ax5.scatter(
    ti_sloc,
    ti_secs,
    color="#ff7f0e",
    s=40,
    alpha=0.8,
    zorder=3,
    label="Data points (TranSPArent)",
)

# Outlier scatter — clipped to axis max via transform annotation
y_max_fig5 = max(vi_secs.max(), ti_secs.max()) * 1.15
x_max_fig5 = max(vi_sloc.max(), ti_sloc.max()) * 1.05

for i in range(n):
    if v_out[i]:
        # Draw clipped at top with arrow
        ax5.annotate(
            f"↑ {repos[i]}\n(Vanilla {vanilla_secs[i]:.0f}s)",
            xy=(vanilla_sloc[i], y_max_fig5),
            xytext=(vanilla_sloc[i], y_max_fig5 * 0.88),
            fontsize=7,
            ha="center",
            color="#1f77b4",
            arrowprops=dict(arrowstyle="->", color="#1f77b4", lw=1),
        )
    if t_out[i]:
        ax5.annotate(
            f"↑ {repos[i]}\n(TranSP. {transparent_secs[i]:.0f}s)",
            xy=(transparent_sloc[i], y_max_fig5),
            xytext=(transparent_sloc[i], y_max_fig5 * 0.75),
            fontsize=7,
            ha="center",
            color="#ff7f0e",
            arrowprops=dict(arrowstyle="->", color="#ff7f0e", lw=1),
        )


# Linear fits on inliers only
def linear_fit_line(x, y, x_end):
    coeffs = np.polyfit(x, y, 1)
    x_line = np.linspace(0, x_end, 300)
    y_line = np.polyval(coeffs, x_line)
    return x_line, y_line, coeffs


vx, vy, vc = linear_fit_line(vi_sloc, vi_secs, x_max_fig5)
tx, ty, tc = linear_fit_line(ti_sloc, ti_secs, x_max_fig5)

ax5.plot(vx, vy, color="green", linewidth=2, label="Linear fit (Vanilla CodeQL)")
ax5.plot(tx, ty, color="red", linewidth=2, label="Linear fit (TranSPArent)")

print(f"\nLinear fit slopes (inliers only):")
print(f"  Vanilla    : {vc[0]*1e6:.2f} s/MLoC  (intercept {vc[1]:.1f}s)")
print(f"  TranSPArent: {tc[0]*1e6:.2f} s/MLoC  (intercept {tc[1]:.1f}s)")

ax5.set_xlabel("Sources Lines of Code (SLoC)")
ax5.set_ylabel("Duration (seconds)")
ax5.ticklabel_format(style="sci", axis="x", scilimits=(6, 6))
ax5.legend(loc="upper left", fontsize=9)
ax5.set_ylim(0, 50)
ax5.set_xlim(0, x_max_fig5)
ax5.grid(True, alpha=0.3)
ax5.set_title(f"Fig 5: Analysis performance overhead")

fig5.tight_layout()
fig5_png = csv_path.parent / "fig5_performance_overhead.png"
fig5_pdf = csv_path.parent / "fig5_performance_overhead.pdf"
fig5.savefig(fig5_png, dpi=150, bbox_inches="tight")
fig5.savefig(fig5_pdf, bbox_inches="tight")
print(f"\nFig 5 saved: {fig5_png}")

# ── Fig 6: CDF — x-axis capped at 95th percentile of combined data ─────────
fig6, ax6 = plt.subplots(figsize=(6.5, 4.5))


def plot_cdf(ax, data, color, label):
    sd = np.sort(data)
    cdf = np.arange(1, len(sd) + 1) / len(sd)
    sd = np.concatenate([[0], sd])
    cdf = np.concatenate([[0], cdf])
    ax.plot(sd, cdf, color=color, linewidth=2, label=label)


plot_cdf(ax6, vanilla_secs, color="#1f77b4", label="Vanilla CodeQL CDF")
plot_cdf(ax6, transparent_secs, color="#ff7f0e", label="TranSPArent CDF")

# Cap x-axis at 95th percentile of inliers so the chart is readable
# but annotate what lies beyond
x_cap = np.percentile(np.concatenate([vi_secs, ti_secs]), 98) * 1.1
ax6.set_xlim(0, 100)

# Annotate repos that exceed the cap


ax6.set_xlabel("Duration (seconds)")
ax6.set_ylabel("Dataset percentage")
ax6.legend(loc="lower right", fontsize=9)
ax6.set_ylim(0, 1.05)
ax6.grid(True, alpha=0.3)
ax6.set_title(f"Fig 6: CDF of analysis performance overhead")

fig6.tight_layout()
fig6_png = csv_path.parent / "fig6_cdf_overhead.png"
fig6_pdf = csv_path.parent / "fig6_cdf_overhead.pdf"
fig6.savefig(fig6_png, dpi=150, bbox_inches="tight")
fig6.savefig(fig6_pdf, bbox_inches="tight")
print(f"\nFig 6 saved: {fig6_png}")

print("\nDone. Files written to:", csv_path.parent)
