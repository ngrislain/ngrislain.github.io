#!/usr/bin/env python3
"""Turn the anomaly-detection report into self-contained blog figures.

Reads the per-character log-probabilities out of the standalone report
produced by https://github.com/ngrislain/anomaly-detection (its
`examples/report_example.py`) and emits one small interactive HTML file per
figure into static/blog/genai-anomaly-detection/.

Everything is in absolute nats, on one scale shared by every panel of every
figure, so any two panels can be compared directly. Each panel shades its
characters by surprise and repeats the same values as a raw, unsmoothed trace
underneath: smoothing would turn the language model's boundary spikes into a
plateau, which is exactly the thing worth seeing.

Run with:
    python3 scripts/gen-anomaly-figures.py path/to/anomaly_report.html
"""

import html
import json
import math
import re
import statistics
import sys
from pathlib import Path
from string import Template

OUT_DIR = Path(__file__).resolve().parent.parent / "static" / "blog" / "genai-anomaly-detection"

QWEN = "Qwen/Qwen3.5-0.8B-Base"

# The one scale every panel is drawn on, taken from the report: a character at
# 0.73 nats is left transparent, one at 7.71 nats is solid. Those are the
# bounds the English-fitted n-gram covers on the clean text.
CLEAR_NATS, SOLID_NATS = 0.73, 7.71

# Top of the trace's y-axis. Surprises above this are clamped.
TRACE_MAX_NATS = 8.0

LEVELS = 24
HIGHLIGHT = (255, 80, 120)


# --------------------------------------------------------------------------
# Reading the report
# --------------------------------------------------------------------------

TOKEN_RE = re.compile(
    r'<mark class="ins">|</mark>'
    r'|<span(?: class="l\d+")? data-lp="(-?[\d.]+)">(.*?)</span>'
    r"|([^<]+)",
    re.S,
)

PANEL_RE = re.compile(
    r'<span class="panel-name">(.*?)</span>'
    r'<span class="stat">.*?</span></figcaption>'
    r'<div class="box scored"[^>]*>(.*?)</div></figure>',
    re.S,
)


def parse_panel(body):
    """Characters, surprises in nats, and inserted-flags of one scored panel."""
    chars, nats, inserted = [], [], []
    inside = False
    for match in TOKEN_RE.finditer(body):
        if match.group(0) == '<mark class="ins">':
            inside = True
            continue
        if match.group(0) == "</mark>":
            inside = False
            continue
        if match.group(1) is not None:
            text, value = html.unescape(match.group(2)), -float(match.group(1))
        else:
            text, value = html.unescape(match.group(3)), float("nan")
        for char in text:
            chars.append(char)
            nats.append(value)
            inserted.append(inside)
    return "".join(chars), nats, inserted


def read_report(path):
    """Map (section title, panel name) -> (text, nats, inserted flags)."""
    source = Path(path).read_text()
    panels = {}
    for section in re.split(r"<section", source)[1:]:
        heading = re.search(r"<h2>(.*?)</h2>", section)
        if not heading:
            continue
        for name, body in PANEL_RE.findall(section):
            panels[(heading.group(1), name)] = parse_panel(body)
    return panels


# --------------------------------------------------------------------------
# Encoding a panel for the browser
# --------------------------------------------------------------------------


def runs(text, nats, inserted, marked):
    """Collapse the characters into [text, nats, inserted] runs.

    Neighbours only merge when they carry the same value, so the number shown
    on hover is always that character's own. Runs also break at every annotated
    index, which gives each arrow its own element to point at.
    """
    out = []
    for index, (char, value, flag) in enumerate(zip(text, nats, inserted)):
        rounded = None if math.isnan(value) else round(value, 3)
        joins = out and out[-1][1] == rounded and out[-1][2] == flag and index not in marked
        if joins:
            out[-1][0] += char
        else:
            out.append([char, rounded, flag])
    return [[chars, value, 1 if flag else 0] for chars, value, flag in out]


def trace(nats, width=560.0, height=64.0):
    """Path through the raw per-character surprise, 0 nats at the bottom.

    Deliberately unsmoothed. A moving average would spread the language
    model's two boundary spikes into one plateau and hide the whole point.
    """

    def y_of(value):
        clamped = min(TRACE_MAX_NATS, max(0.0, 0.0 if math.isnan(value) else value))
        return height * (1.0 - clamped / TRACE_MAX_NATS)

    step = width / max(1, len(nats) - 1)
    points = [f"{i * step:.1f},{y_of(v):.1f}" for i, v in enumerate(nats)]
    return "M" + "L".join(points), y_of


def panel_payload(title, text, nats, inserted, notes):
    finite = [v for v in nats if math.isfinite(v)]
    mean = statistics.mean(finite)
    path, y_of = trace(nats)
    span = [i for i, flag in enumerate(inserted) if flag]
    return {
        "title": title,
        "subtitle": f"{mean:.2f} nats/char",
        "runs": runs(text, nats, inserted, {note["at"] for note in notes}),
        "path": path,
        "meanY": round(y_of(mean), 1),
        "span": [span[0] / len(text), (span[-1] + 1) / len(text)] if span else None,
        "notes": notes,
    }


# --------------------------------------------------------------------------
# The page
# --------------------------------------------------------------------------


def level_rules():
    rules = []
    for level in range(1, LEVELS):
        alpha = level / (LEVELS - 1)
        rules.append(f".l{level}{{background:rgba{(*HIGHLIGHT, round(alpha, 3))}}}")
    return "\n".join(rules)


def gradient():
    stops = []
    for level in range(LEVELS):
        alpha = level / (LEVELS - 1)
        stops.append(f"rgba{(*HIGHLIGHT, round(alpha, 3))} {100 * level / (LEVELS - 1):.0f}%")
    return "linear-gradient(90deg, " + ", ".join(stops) + ")"


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
:root{
  --ink:#23272f; --muted:#6b7280; --rule:#e5e7eb; --bg:#f7f8fa; --panel:#fff;
  --mark:#c81e56;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
}
*{box-sizing:border-box}
body{margin:0;padding:.9rem;background:var(--bg);color:var(--ink);
  font-family:var(--sans);font-size:14px;line-height:1.6}
.caption{font-weight:600;font-size:.92rem;margin:0 0 .8rem}
.grid{display:grid;gap:1rem}
figure{margin:0;min-width:0}
figcaption{display:flex;justify-content:space-between;align-items:baseline;gap:.6rem;
  margin-bottom:.3rem;font-size:.8rem}
.name{font-weight:600;font-size:.85rem}
.stat{color:var(--muted);font-variant-numeric:tabular-nums;text-align:right}
.textwrap{position:relative}
/* The generous leading is what the arrows are placed into, so they never sit
   on top of a line of text. */
.text{background:var(--panel);border:1px solid var(--rule);border-radius:6px 6px 0 0;
  border-bottom:0;padding:1.6rem .7rem .7rem;white-space:pre-wrap;
  overflow-wrap:break-word;font-size:12.5px;line-height:2.5}
.text span{cursor:help}
mark.ins{background:#fdf6e9;color:inherit}
.marker{position:absolute;z-index:3;pointer-events:none;
  transform:translate(-50%,-100%);text-align:center;font-size:.6rem;line-height:1.15;
  font-weight:600;color:var(--mark);white-space:nowrap}
.marker b{display:block;background:var(--panel);border:1px solid #f0adc2;
  border-radius:3px;padding:0 .28rem;box-shadow:0 1px 2px rgba(16,24,40,.09)}
.marker i{display:block;width:0;height:0;margin:0 auto;
  border:3px solid transparent;border-top-color:var(--mark);border-bottom:0}
.tracewrap{position:relative}
.trace{display:block;width:100%;height:64px;
  background:var(--panel);border:1px solid var(--rule);border-radius:0 0 6px 6px}
.tracelabel{position:absolute;left:.5rem;top:.1rem;color:#9ca3af;font-size:.64rem;
  pointer-events:none;background:rgba(255,255,255,.82);padding:0 .2rem;border-radius:2px}
.foot{display:flex;flex-wrap:wrap;align-items:center;gap:.4rem .7rem;margin-top:.8rem;
  padding-top:.6rem;border-top:1px solid var(--rule);color:var(--muted);font-size:.75rem}
.bar{flex:0 0 110px;height:.55rem;border-radius:3px;border:1px solid var(--rule);
  background:$gradient}
.swatch{display:inline-block;width:.75rem;height:.75rem;vertical-align:-1px;
  border:1px solid var(--rule);background:#fdf6e9;border-radius:2px}
#tip{position:fixed;z-index:9;pointer-events:none;opacity:0;transition:opacity .08s;
  background:var(--ink);color:#fff;padding:.15rem .45rem;border-radius:4px;
  font-size:.72rem;font-variant-numeric:tabular-nums;white-space:nowrap}
$levels
</style>
</head>
<body>
<p class="caption">$caption</p>
<div class="grid" id="grid"></div>
<div class="foot">
  <span>0.7 nats</span><span class="bar"></span><span>7.7 nats and above</span>
  <span>&mdash; one scale shared by every panel</span>
  $wash
</div>
<div id="tip"></div>
<script>
const PANELS = $panels;
const LEVELS = $nlevels, CLEAR = $clear, SOLID = $solid;

const shade = (nats) => nats === null ? 0 :
  Math.round(Math.min(1, Math.max(0, (nats - CLEAR) / (SOLID - CLEAR))) * (LEVELS - 1));

const grid = document.getElementById("grid");
for (const p of PANELS) {
  const fig = document.createElement("figure");
  fig.innerHTML =
    '<figcaption><span class="name"></span><span class="stat"></span></figcaption>' +
    '<div class="textwrap"><div class="text"></div></div>' +
    '<div class="tracewrap">' +
    '<svg class="trace" viewBox="0 0 560 64" preserveAspectRatio="none" aria-hidden="true">' +
      (p.span ? '<rect x="' + (p.span[0] * 560).toFixed(1) + '" y="0" width="' +
        ((p.span[1] - p.span[0]) * 560).toFixed(1) + '" height="64" fill="#fdf6e9"/>' : "") +
      '<line x1="0" x2="560" y1="' + p.meanY + '" y2="' + p.meanY +
        '" stroke="#d1d5db" stroke-width="1" stroke-dasharray="3 3"/>' +
      '<path d="' + p.path + '" fill="none" stroke="#e11d63" stroke-width="1" ' +
        'vector-effect="non-scaling-stroke"/>' +
    '</svg><span class="tracelabel">surprise per character, 0 to 8 nats ' +
    '(dashed: this panel\\u2019s average)</span></div>';
  fig.querySelector(".name").textContent = p.title;
  fig.querySelector(".stat").textContent = p.subtitle;
  p.box = fig.querySelector(".text");
  p.wrap = fig.querySelector(".textwrap");
  grid.appendChild(fig);
}

for (const p of PANELS) {
  let out = "", open = false, index = 0;
  const anchors = new Map(p.notes.map((note, i) => [note.at, i]));
  for (const [text, nats, ins] of p.runs) {
    if (ins && !open) { out += '<mark class="ins">'; open = true; }
    if (!ins && open) { out += "</mark>"; open = false; }
    const escaped = text.replace(/&/g, "&amp;").replace(/</g, "&lt;");
    const note = anchors.has(index) ? ' data-note="' + anchors.get(index) + '"' : "";
    index += text.length;
    if (nats === null) { out += escaped; continue; }
    const level = shade(nats);
    out += "<span" + (level ? ' class="l' + level + '"' : "") + note +
      ' data-v="' + nats.toFixed(2) + ' nats">' + escaped + "</span>";
  }
  p.box.innerHTML = out + (open ? "</mark>" : "");
}

// Arrows sit absolutely over the text, so they can only be placed once the
// text has laid out, and have to be replaced whenever it rewraps. Labels that
// would collide on the same line stack upwards instead.
function place(p) {
  p.wrap.querySelectorAll(".marker").forEach((marker) => marker.remove());
  const base = p.wrap.getBoundingClientRect();
  const placed = [];
  p.notes.forEach((note, i) => {
    const target = p.box.querySelector('[data-note="' + i + '"]');
    if (!target) return;
    const box = target.getBoundingClientRect();
    const marker = document.createElement("div");
    marker.className = "marker";
    marker.innerHTML = "<b></b><i></i>";
    marker.querySelector("b").textContent = note.label;
    p.wrap.appendChild(marker);
    const half = marker.offsetWidth / 2;
    const anchorX = box.left - base.left + box.width / 2;
    const x = Math.min(Math.max(anchorX, half + 2), Math.max(half + 2, base.width - half - 2));
    let y = box.top - base.top;
    for (const seen of placed)
      if (Math.abs(seen.y - y) < 4 && Math.abs(seen.x - x) < seen.half + half + 6)
        y = seen.y - marker.offsetHeight - 3;
    marker.style.left = x + "px";
    marker.style.top = y + "px";
    // A label pushed off the edge keeps its arrow over the character it means.
    marker.querySelector("i").style.transform =
      "translateX(" + Math.max(-half + 5, Math.min(half - 5, anchorX - x)) + "px)";
    placed.push({x, y, half});
  });
}

const placeAll = () => PANELS.forEach(place);

const tip = document.getElementById("tip");
document.addEventListener("mousemove", (event) => {
  const value = event.target.dataset && event.target.dataset.v;
  if (!value) { tip.style.opacity = 0; return; }
  tip.textContent = value;
  tip.style.left = (event.clientX + 12) + "px";
  tip.style.top = (event.clientY + 14) + "px";
  tip.style.opacity = 1;
});

placeAll();
new ResizeObserver(placeAll).observe(document.documentElement);
addEventListener("load", placeAll);

// Let a host page size its iframe to this figure, so nothing scrolls inside it.
const report = () => parent !== window &&
  parent.postMessage({figHeight: document.body.scrollHeight + 2}, "*");
new ResizeObserver(report).observe(document.body);
addEventListener("load", report);
report();
</script>
</body>
</html>
"""


def write_figure(name, title, caption, panels, wash=True):
    page = Template(PAGE).substitute(
        title=title,
        caption=caption,
        levels=level_rules(),
        gradient=gradient(),
        wash=(
            '<span><span class="swatch"></span> where the text was really spliced in</span>'
            if wash
            else ""
        ),
        panels=json.dumps(panels, ensure_ascii=False, separators=(",", ":")),
        nlevels=LEVELS,
        clear=CLEAR_NATS,
        solid=SOLID_NATS,
    )
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / name
    path.write_text(page)
    print(f"wrote {path} ({len(page) / 1024:.0f} KB)")


# --------------------------------------------------------------------------
# The banner image used as the post's hero
# --------------------------------------------------------------------------

HERO = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>hero</title><style>
:root{--ink:#23272f;--muted:#6b7280;--rule:#e5e7eb;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif}
*{box-sizing:border-box}
body{margin:0;width:1200px;height:420px;background:#f7f8fa;color:var(--ink);
  font-family:var(--sans);padding:26px 30px;display:flex;flex-direction:column}
h1{font-size:19px;margin:0 0 4px;font-weight:600;letter-spacing:-.01em}
.sub{font-size:12.5px;color:var(--muted);margin:0 0 16px}
.cols{display:grid;grid-template-columns:1fr 1fr;gap:22px;flex:1;min-height:0}
.name{font-size:12px;font-weight:600;margin-bottom:5px;display:flex;
  justify-content:space-between}
.name em{font-style:normal;color:var(--muted);font-weight:400;
  font-variant-numeric:tabular-nums}
.text{background:#fff;border:1px solid var(--rule);border-radius:6px;padding:11px 13px;
  font-size:12px;line-height:1.6;white-space:pre-wrap;overflow:hidden;flex:1}
figure{margin:0;display:flex;flex-direction:column;min-height:0}
$levels
</style></head><body>
<h1>The same clean English, read by two models, on one scale</h1>
<p class="sub">Every character shaded by &minus;log P(character | everything before it).
Pink is surprise.</p>
<div class="cols">$cols</div>
</body></html>
"""


def hero_column(name, stat, text, nats):
    out = []
    for char, value in zip(text, nats):
        escaped = char.replace("&", "&amp;").replace("<", "&lt;")
        if math.isnan(value):
            out.append(escaped)
            continue
        share = (value - CLEAR_NATS) / (SOLID_NATS - CLEAR_NATS)
        level = round(min(1.0, max(0.0, share)) * (LEVELS - 1))
        out.append(f'<span class="l{level}">{escaped}</span>' if level else escaped)
    return (
        f'<figure><div class="name"><span>{name}</span><em>{stat}</em></div>'
        f'<div class="text">{"".join(out)}</div></figure>'
    )


def write_hero(panels):
    columns = []
    for model, name in (
        ("5-gram", "5-gram, fitted on 193k chars of English"),
        (QWEN, "Qwen3.5-0.8B-Base, fitted on nothing"),
    ):
        text, nats, _ = panels[("Evaluated text", model)]
        finite = [v for v in nats if math.isfinite(v)]
        columns.append(hero_column(name, f"{statistics.mean(finite):.2f} nats/char", text, nats))
    page = Template(HERO).substitute(levels=level_rules(), cols="".join(columns))
    path = OUT_DIR / "hero.html"
    path.write_text(page)
    print(f"wrote {path}")


# --------------------------------------------------------------------------


def main():
    report = sys.argv[1] if len(sys.argv) > 1 else "../anomaly-detection/out/anomaly_report.html"
    panels = read_report(report)

    def build(section, model, title, notes=()):
        text, nats, inserted = panels[(section, model)]
        return panel_payload(title, text, nats, inserted, list(notes))

    # Annotation offsets are character positions in each panel's own text. The
    # clean text is 1,200 characters; both contaminated copies splice at 493.
    write_figure(
        "fig-baseline.html",
        "Two readers on the same clean text",
        "Clean English: the first 1,200 characters of the Wikipedia article on "
        "artificial intelligence, with nothing spliced in.",
        [
            build(
                "Evaluated text",
                "5-gram",
                "5-gram fitted on 193k chars of English",
                [
                    {"at": 547, "label": "5.1 nats on “web search”"},
                    {"at": 578, "label": "5.1 nats on “virtual”"},
                    {"at": 699, "label": "0.7 nats: the earlier “e.g.,” is out of reach"},
                ],
            ),
            build(
                "Evaluated text",
                QWEN,
                "Qwen3.5-0.8B-Base, no fitting",
                [
                    {"at": 0, "label": "cold start: nothing to condition on yet"},
                    {"at": 699, "label": "5.0 nats: the first “e.g.” took a comma"},
                ],
            ),
        ],
        wash=False,
    )

    write_figure(
        "fig-basque.html",
        "A Basque sentence spliced in",
        "The same text with one Basque sentence spliced in after the first sentence.",
        [
            build(
                "Basque sentence inserted",
                "5-gram",
                "5-gram fitted on English",
                [
                    {"at": 571, "label": "5.3 nats/char, start to finish"},
                    {"at": 714, "label": "still 6.4 nats after the splice ends"},
                ],
            ),
            build(
                "Basque sentence inserted",
                QWEN,
                "Qwen3.5-0.8B-Base, no fitting",
                [
                    {"at": 493, "label": "5.6 nats: into Basque"},
                    {"at": 660, "label": "0.4 nats: Basque is the new normal"},
                    {"at": 714, "label": "2.2 nats: back into English"},
                ],
            ),
        ],
    )

    write_figure(
        "fig-french.html",
        "A French sentence spliced in",
        "The same text, same position, with a French sentence instead. Much closer "
        "to English, so much harder to catch.",
        [
            build(
                "French sentence inserted",
                "5-gram",
                "5-gram fitted on English",
                [{"at": 540, "label": "3.7 nats/char, weaker than on Basque"}],
            ),
            build(
                "French sentence inserted",
                QWEN,
                "Qwen3.5-0.8B-Base, no fitting",
                [
                    {"at": 493, "label": "5.6 nats: into French"},
                    {"at": 606, "label": "0.001 nats: French, and a repeat"},
                    {"at": 629, "label": "4.0 nats: back into English"},
                ],
            ),
        ],
    )

    write_figure(
        "fig-mirror.html",
        "Normal is whatever you fitted on",
        "One text, one model order, two fitting corpora. The verdict flips.",
        [
            build(
                "Basque sentence inserted",
                "5-gram",
                "5-gram fitted on English",
                [{"at": 571, "label": "the Basque is the anomaly"}],
            ),
            build(
                "Fitted on another corpus",
                "5-gram (Basque)",
                "5-gram fitted on Basque",
                [{"at": 120, "label": "now the English is the anomaly"}],
            ),
        ],
    )

    write_hero(panels)


if __name__ == "__main__":
    main()
