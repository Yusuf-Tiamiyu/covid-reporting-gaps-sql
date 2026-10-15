"""Draw the README charts from the query results in ../results/.

    python charts/make_charts.py
"""
from pathlib import Path

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
RESULTS, OUT = ROOT / "results", ROOT / "charts"

SURFACE, INK, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
BLUE, BLUE_LIGHT, GREY = "#2a78d6", "#9ec5f4", "#c9c8c3"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "font.family": "Segoe UI", "font.size": 10, "text.color": INK,
    "axes.edgecolor": GRID, "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False, "axes.spines.left": False,
})


def cameroon():
    df = pd.read_csv(RESULTS / "cameroon_spread.tsv", sep="\t", parse_dates=["report_date"])
    fig, ax = plt.subplots(figsize=(9, 3.8), dpi=150)
    ax.bar(df["report_date"], df["reported"], width=0.9, color=GREY, label="Reported that day")
    ax.plot(df["report_date"], df["spread"], color=BLUE, linewidth=2, label="Spread over the days it covers")
    ax.yaxis.grid(True, color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)
    ax.tick_params(length=0)
    ax.xaxis.set_major_locator(mdates.MonthLocator())
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%b %Y"))
    ax.yaxis.set_major_formatter(lambda v, _: f"{v:,.0f}")

    peak = df.loc[df["reported"].idxmax()]
    ax.annotate(f"{peak['reported']:,.0f} reported on 1 Apr 2021,\nafter five days of zeros",
                xy=(peak["report_date"], peak["reported"]), xytext=(-10, -6), textcoords="offset points",
                ha="right", va="top", color=INK, fontsize=9)
    ax.legend(loc="upper left", frameon=False, fontsize=9)

    fig.text(0.01, 0.97, "Cameroon: daily COVID-19 cases, Dec 2020 to Apr 2021", fontsize=12, weight="bold", va="top")
    fig.text(0.01, 0.89, "Most days show zero, then one large report. Spreading each report back over its days "
             "gives the real daily trend.", color=MUTED, va="top")
    fig.subplots_adjust(top=0.8, left=0.07, right=0.99, bottom=0.09)
    fig.savefig(OUT / "cameroon_batches.png")


def weekday():
    df = pd.read_csv(RESULTS / "weekday.tsv", sep="\t")
    fig, ax = plt.subplots(figsize=(7.5, 3), dpi=150)
    colors = [BLUE if d in ("Sunday", "Monday") else BLUE_LIGHT for d in df["weekday"]]
    ax.bar(df["weekday"].str[:3], df["pct_of_week"], color=colors, width=0.62)
    ax.axhline(100 / 7, color=MUTED, linewidth=1, linestyle=(0, (3, 3)), zorder=0)
    for x, (d, v) in enumerate(zip(df["weekday"], df["pct_of_week"])):
        ax.text(x, v - 0.45, f"{v:.1f}%", ha="center", va="top", fontsize=9,
                color="white" if d in ("Sunday", "Monday") else INK)
    ax.set_ylim(0, 18.5)
    ax.yaxis.set_visible(False)
    ax.tick_params(length=0)
    fig.text(0.01, 0.97, "Share of the week's reported cases, by weekday", fontsize=12, weight="bold", va="top")
    fig.text(0.01, 0.87, "All countries, June 2020 to April 2021. Dashed line: 14.3%, an even split across the week",
             color=MUTED, va="top")
    fig.subplots_adjust(top=0.76, left=0.03, right=0.99, bottom=0.1)
    fig.savefig(OUT / "weekday_effect.png")


if __name__ == "__main__":
    cameroon()
    weekday()
    print("charts written to", OUT)
