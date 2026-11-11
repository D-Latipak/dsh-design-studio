#!/usr/bin/env python
"""chart.py — themed SVG/PNG charts for the design pipeline (matplotlib).

Designed for infographics, long pages and report figures: no chart junk,
explicit palette, Chinese font support, transparent background option.

Data formats
  JSON  {"labels": ["Q1","Q2"], "values": [12, 30], "unit": "人", "title": ""}
        or {"series": [{"name":"A","values":[...]}, ...], "labels": [...]}
  CSV   first row header: label,<series1>,<series2>...   (comma-separated)

Examples
  python chart.py --kind bar --data data.json --out chart.svg --palette "#E2603C,#0E1B2A"
  python chart.py --kind line --data data.csv --out chart.png --size 1200x700 --transparent
  python chart.py --kind donut --data share.json --out share.svg --labels-right
"""
from __future__ import annotations

import argparse
import csv
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.ticker import MaxNLocator

CJK_CANDIDATES = [
    "Microsoft YaHei", "SimHei", "Source Han Sans SC", "Noto Sans SC",
    "NotoSansSC", "PingFang SC", "Arial Unicode MS",
]
GROUPS = ["#E2603C", "#0E1B2A", "#7BB51C", "#C9A227", "#8E2F3C", "#4C8DFF", "#B0AEA5"]


def pick_font() -> str | None:
    available = {f.name for f in font_manager.fontManager.ttflist}
    for name in CJK_CANDIDATES:
        if name in available:
            return name
    return None


def load(path: str) -> dict:
    p = Path(path)
    if p.suffix.lower() == ".csv":
        with p.open(encoding="utf-8-sig", newline="") as fh:
            rows = list(csv.reader(fh))
        if not rows:
            raise SystemExit("empty csv")
        header, body = rows[0], rows[1:]
        labels = [r[0] for r in body]
        series = []
        for idx in range(1, len(header)):
            series.append({"name": header[idx] or f"series{idx}",
                           "values": [float(r[idx] or 0) for r in body]})
        return {"labels": labels, "series": series}
    data = json.loads(p.read_text(encoding="utf-8"))
    if isinstance(data, list):
        data = {"labels": [str(i + 1) for i in range(len(data))], "values": data}
    if "values" in data and "series" not in data:
        data["series"] = [{"name": data.get("name", "series1"), "values": data["values"]}]
    if "labels" not in data and data.get("series"):
        data["labels"] = [str(i + 1) for i in range(len(data["series"][0]["values"]))]
    return data


def style(ax, data, font, args):
    ax.yaxis.set_major_locator(MaxNLocator(nbins=4))
    ax.grid(axis="y", color=args.grid_color, linewidth=0.8, alpha=args.grid_alpha)
    ax.set_axisbelow(True)
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    for side in ("left", "bottom"):
        ax.spines[side].set_color(args.axis_color)
        ax.spines[side].set_linewidth(1)
    ax.tick_params(colors=args.text_color, labelsize=args.font_size, length=0)
    if font:
        for lab in ax.get_xticklabels() + ax.get_yticklabels():
            lab.set_fontfamily(font)
    if args.title:
        ax.set_title(args.title, color=args.text_color, fontsize=args.font_size * 1.6,
                     loc="left", pad=14, fontfamily=font or "sans-serif")
    if data.get("unit"):
        ax.set_ylabel(data["unit"], color=args.text_color, fontsize=args.font_size,
                      fontfamily=font or "sans-serif")
    ax.set_xticks(range(len(data["labels"])))
    ax.set_xticklabels(data["labels"])


def draw_bar(ax, data, colors, args):
    n = len(data["series"])
    w = 0.8 / n
    for i, s in enumerate(data["series"]):
        xs = [x + (i - (n - 1) / 2) * w for x in range(len(s["values"]))]
        ax.bar(xs, s["values"], width=w * 0.92, color=colors[i % len(colors)],
               label=s["name"], zorder=3)
    ax.set_ylim(0, max(max(s["values"]) for s in data["series"]) * 1.18)


def draw_line(ax, data, colors, args):
    for i, s in enumerate(data["series"]):
        ax.plot(range(len(s["values"])), s["values"], color=colors[i % len(colors)],
                linewidth=args.line_width, marker="o", markersize=5,
                markeredgecolor="white", markeredgewidth=1, label=s["name"], zorder=3)
    ax.set_ylim(0, max(max(s["values"]) for s in data["series"]) * 1.18)


def draw_donut(ax, data, colors, args):
    values = data["series"][0]["values"]
    labels = data["labels"]
    total = sum(values) or 1
    wedges, _ = ax.pie(values, colors=colors[: len(values)], startangle=90,
                       counterclock=False, wedgeprops=dict(width=args.ring, edgecolor="none"))
    ax.set_aspect("equal")
    ax.text(0, 0.06, f"{max(values) / total * 100:.0f}%", ha="center", va="center",
            fontsize=args.font_size * 2.2, color=args.text_color, fontweight="bold")
    ax.text(0, -0.18, labels[values.index(max(values))], ha="center", va="center",
            fontsize=args.font_size, color=args.text_color)
    if args.legend:
        ax.legend(wedges, [f"{l}  {v / total * 100:.0f}%" for l, v in zip(labels, values)],
                  loc="center left", bbox_to_anchor=(1.02, 0.5), frameon=False,
                  fontsize=args.font_size, labelcolor=args.text_color)


def main() -> int:
    ap = argparse.ArgumentParser(description="themed chart renderer")
    ap.add_argument("--kind", choices=["bar", "line", "donut"], default="bar")
    ap.add_argument("--data", required=True, help="JSON or CSV data file")
    ap.add_argument("--out", required=True, help="output .svg/.png/.pdf")
    ap.add_argument("--palette", default="", help='comma list, e.g. "#E2603C,#0E1B2A"')
    ap.add_argument("--size", default="1200x700", help="WxH in px")
    ap.add_argument("--title", default="")
    ap.add_argument("--transparent", action="store_true")
    ap.add_argument("--font-size", type=float, default=14)
    ap.add_argument("--line-width", type=float, default=3)
    ap.add_argument("--ring", type=float, default=0.34, help="donut ring width (0-0.5 of radius)")
    ap.add_argument("--legend", action="store_true", help="show legend (default on for donut)")
    ap.add_argument("--grid-alpha", type=float, default=0.25)
    ap.add_argument("--grid-color", default="#8A8378")
    ap.add_argument("--axis-color", default="#8A8378")
    ap.add_argument("--text-color", default="#1B1B1B")
    args = ap.parse_args()

    colors = [c.strip() for c in args.palette.split(",") if c.strip()] or GROUPS
    font = pick_font()
    if font:
        plt.rcParams["font.family"] = [font, "DejaVu Sans"]
        plt.rcParams["axes.unicode_minus"] = False

    try:
        data = load(args.data)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"error: cannot read data: {exc}", file=sys.stderr)
        return 2
    if not data.get("series") or not data["labels"]:
        print("error: data has no series/labels", file=sys.stderr)
        return 2

    w, h = (float(v) for v in args.size.lower().split("x"))
    dpi = 100
    fig, ax = plt.subplots(figsize=(w / dpi, h / dpi), dpi=dpi)
    if args.transparent:
        fig.patch.set_alpha(0)
        ax.set_facecolor("none")
    else:
        fig.patch.set_facecolor("#FFFFFF")

    if args.legend and args.kind != "donut":
        ax.legend(frameon=False, fontsize=args.font_size, labelcolor=args.text_color,
                  loc="upper left", ncol=len(data["series"]), handlelength=1.2)
    if args.kind == "donut":
        draw_donut(ax, data, colors, args)
    else:
        style(ax, data, font, args)
        (draw_bar if args.kind == "bar" else draw_line)(ax, data, colors, args)
        if args.legend:
            ax.legend(frameon=False, fontsize=args.font_size, labelcolor=args.text_color,
                      loc="upper left", ncol=len(data["series"]), handlelength=1.2)

    fig.tight_layout(pad=1.2)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    fmt = out.suffix.lstrip(".").lower()
    fig.savefig(out, format=fmt, dpi=dpi, transparent=args.transparent,
                facecolor=fig.get_facecolor())
    plt.close(fig)
    print(json.dumps({"ok": True, "out": str(out.resolve()), "kind": args.kind,
                      "font": font, "bytes": out.stat().st_size}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
