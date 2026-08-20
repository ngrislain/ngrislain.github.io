#!/usr/bin/env python3
"""Build the figure explaining where the anomaly score comes from.

Runs Qwen3.5-0.8B-Base over the contaminated text from
https://github.com/ngrislain/anomaly-detection and dumps, at three chosen
positions, the model's real distribution over the next token together with the
token that actually followed. The same distribution answers both questions a
causal language model can be asked: sample from it and you are generating,
look up what really happened and you are scoring.

Needs torch and transformers, so run it with that project's virtualenv:

    cd ../anomaly-detection
    .venv/bin/python ../ngrislain.github.io/scripts/gen-token-figure.py
"""

import json
import math
import re
import sys
from pathlib import Path
from string import Template

OUT = Path(__file__).resolve().parent.parent / "static" / "blog" / "genai-anomaly-detection"
CACHE = Path(__file__).resolve().parent / "token-probe.json"

MODEL = "Qwen/Qwen3.5-0.8B-Base"
TOP_K = 6

# The same ramp the other figures use: 0.73 nats transparent, 7.71 solid.
CLEAR_NATS, SOLID_NATS = 0.73, 7.71

# Positions to probe, as character offsets into the contaminated text.
PROBES = [
    (300, "Ordinary English", "mid-sentence, nothing wrong"),
    (493, "The splice into Basque", "the first token of the inserted sentence"),
    (713, "Back out into English", "the first token after the inserted sentence"),
]


def collect():
    """Probe the model, or reuse the cached probe if it is already on disk."""
    if CACHE.exists():
        return json.loads(CACHE.read_text())

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    from anomaly_detection.text_manipulation import insert_after_sentence
    from anomaly_detection.wikipedia_search import get_wikipedia_article

    tokenizer = AutoTokenizer.from_pretrained(MODEL)
    model = AutoModelForCausalLM.from_pretrained(MODEL, dtype=torch.bfloat16)
    model.eval()

    article = get_wikipedia_article("Euskara", "eu")
    paragraph = next(p for p in article.split("\n") if len(p) >= 400 and "bakartua" in p)
    basque = " " + re.match(r"[^.!?]+[.!?]+", paragraph).group().strip()
    text = insert_after_sentence(get_wikipedia_article("Artificial intelligence", "us")[:1200], 1, basque)

    encoding = tokenizer(text, return_offsets_mapping=True, add_special_tokens=False)
    ids, offsets = encoding["input_ids"], encoding["offset_mapping"]
    bos = tokenizer.convert_tokens_to_ids("<|endoftext|>")

    probes = []
    for position, title, note in PROBES:
        index = next(i for i, (start, _) in enumerate(offsets) if start >= position)
        with torch.inference_mode():
            logits = model(torch.tensor([[bos] + ids[:index]])).logits[0, -1].float()
        log_probs = torch.log_softmax(logits, -1)
        top = log_probs.topk(TOP_K)
        actual = ids[index]
        start, end = offsets[index]
        probes.append(
            {
                "title": title,
                "note": note,
                "prefix": text[max(0, start - 62) : start],
                "actual": tokenizer.decode([actual]),
                "chars": end - start,
                "nats": -log_probs[actual].item(),
                "prob": float(log_probs[actual].exp()),
                "rank": int((log_probs > log_probs[actual]).sum().item()) + 1,
                "vocab": int(log_probs.numel()),
                "top": [
                    {"tok": tokenizer.decode([i]), "p": float(v.exp())}
                    for v, i in zip(top.values, top.indices)
                ],
            }
        )
    CACHE.write_text(json.dumps(probes, ensure_ascii=False, indent=1))
    return probes


def shade(nats):
    return min(1.0, max(0.0, (nats - CLEAR_NATS) / (SOLID_NATS - CLEAR_NATS)))


def visible(token):
    """A token as a quoted literal, with whitespace made legible."""
    shown = (
        token.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    return f"&#39;{shown}&#39;"


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Where the anomaly score comes from</title>
<style>
:root{
  --ink:#23272f; --muted:#6b7280; --rule:#e5e7eb; --bg:#f7f8fa; --panel:#fff;
  --mark:#c81e56; --bar:#c7d2e4;
  --sans:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
}
*{box-sizing:border-box}
body{margin:0;padding:.9rem;background:var(--bg);color:var(--ink);
  font-family:var(--sans);font-size:14px;line-height:1.6}
.caption{font-weight:600;font-size:.92rem;margin:0 0 .75rem}
.schema{display:block;width:100%;max-width:720px;height:auto;margin:0 auto 1.1rem;
  background:var(--panel);border:1px solid var(--rule);border-radius:6px}
.grid{display:grid;gap:.8rem}
figure{margin:0;background:var(--panel);border:1px solid var(--rule);
  border-radius:6px;padding:.7rem .8rem}
figcaption{font-size:.8rem;font-weight:600;margin-bottom:.1rem}
.note{color:var(--muted);font-size:.72rem;margin:0 0 .5rem}
.prefix{font-family:var(--mono);font-size:.72rem;color:var(--muted);
  background:#f7f8fa;border-radius:4px;padding:.25rem .4rem;margin-bottom:.5rem;
  overflow-wrap:break-word}
table{border-collapse:collapse;width:100%;font-size:.75rem}
td{padding:.1rem .3rem;vertical-align:middle}
td.tok{font-family:var(--mono);width:1%;white-space:nowrap;text-align:right}
td.pct{width:1%;white-space:nowrap;font-variant-numeric:tabular-nums;
  color:var(--muted);text-align:right}
.track{background:#eef1f6;border-radius:2px;height:.62rem;min-width:1px}
.fill{background:var(--bar);border-radius:2px;height:100%}
tr.gap td{color:var(--muted);text-align:center;padding:.05rem;font-size:.7rem}
tr.actual td{padding-top:.4rem}
tr.actual{border-top:1px solid var(--rule)}
tr.actual td.tok{color:var(--mark);font-weight:600}
tr.actual .fill{background:var(--mark)}
.score{display:inline-block;font-variant-numeric:tabular-nums;font-weight:600;
  border:1px solid #f0adc2;border-radius:3px;padding:0 .3rem;white-space:nowrap}
.foot{margin-top:.8rem;padding-top:.6rem;border-top:1px solid var(--rule);
  color:var(--muted);font-size:.75rem}
</style>
</head>
<body>
<p class="caption">$caption</p>
$schema
<div class="grid">$panels</div>
<p class="foot">$foot</p>
<script>
const report = () => parent !== window &&
  parent.postMessage({figHeight: document.body.scrollHeight + 2}, "*");
new ResizeObserver(report).observe(document.body);
addEventListener("load", report);
report();
</script>
</body>
</html>
"""

SCHEMA = """<svg class="schema" viewBox="0 0 720 196" role="img"
  aria-label="A prefix goes into the model, the model returns a distribution over the
  next token, and that one distribution serves both generation and scoring.">
<defs>
  <marker id="tip" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6"
    orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="#9aa3af"/></marker>
  <style>
    .bx{fill:#fff;stroke:#c8cdd6}
    .lb{font:600 11px var(--sans);fill:#23272f}
    .sb{font:10px var(--sans);fill:#6b7280}
    .mn{font:10px var(--mono);fill:#23272f}
    .ar{stroke:#9aa3af;stroke-width:1.2;fill:none;marker-end:url(#tip)}
    .hi{font:600 11px var(--sans);fill:#c81e56}
  </style>
</defs>

<rect class="bx" x="8" y="70" width="132" height="56" rx="5"/>
<text class="sb" x="74" y="88" text-anchor="middle">everything so far</text>
<text class="mn" x="74" y="104" text-anchor="middle">...defined goals.</text>
<text class="sb" x="74" y="118" text-anchor="middle">(the prefix)</text>
<path class="ar" d="M144,98 L176,98"/>

<rect class="bx" x="180" y="70" width="86" height="56" rx="5"/>
<text class="lb" x="223" y="94" text-anchor="middle">model</text>
<text class="sb" x="223" y="110" text-anchor="middle">one forward pass</text>
<path class="ar" d="M270,98 L302,98"/>

<rect class="bx" x="306" y="36" width="124" height="110" rx="5"/>
<text class="lb" x="368" y="54" text-anchor="middle">P(next token)</text>
<g fill="#c7d2e4">
  <rect x="332" y="62" width="72" height="7" rx="2"/>
  <rect x="332" y="74" width="72" height="7" rx="2"/>
  <rect x="332" y="86" width="39" height="7" rx="2"/>
  <rect x="332" y="98" width="17" height="7" rx="2"/>
  <rect x="332" y="110" width="14" height="7" rx="2"/>
</g>
<rect x="332" y="122" width="2" height="7" rx="1" fill="#c81e56"/>
<text class="sb" x="340" y="129" font-size="9">actual</text>
<text class="sb" x="368" y="174" text-anchor="middle">every token in the vocabulary</text>

<path class="ar" d="M434,70 L470,52"/>
<path class="ar" d="M434,116 L470,144"/>

<rect class="bx" x="474" y="24" width="238" height="52" rx="5"/>
<text class="lb" x="486" y="43">To generate</text>
<text class="sb" x="486" y="60">sample a token from it, append, repeat</text>

<rect class="bx" x="474" y="120" width="238" height="60" rx="5"/>
<text class="hi" x="486" y="139">To score</text>
<text class="sb" x="486" y="155">find the token that actually came next,</text>
<text class="sb" x="486" y="170">and take &#8722;log of its probability</text>
</svg>"""


def rows(probe):
    biggest = max(probe["top"][0]["p"], probe["prob"])
    out = []
    for item in probe["top"]:
        width = 100 * item["p"] / biggest
        out.append(
            f'<tr><td class="tok">{visible(item["tok"])}</td>'
            f'<td><div class="track"><div class="fill" style="width:{width:.1f}%"></div></div></td>'
            f'<td class="pct">{100 * item["p"]:.1f}%</td></tr>'
        )
    if probe["rank"] > TOP_K:
        out.append('<tr class="gap"><td></td><td>&#8942;</td><td></td></tr>')
    width = 100 * probe["prob"] / biggest
    percent = f"{100 * probe['prob']:.1f}%" if probe["prob"] >= 0.001 else f"{100 * probe['prob']:.3f}%"
    alpha = shade(probe["nats"])
    out.append(
        f'<tr class="actual"><td class="tok">{visible(probe["actual"])}</td>'
        f'<td><div class="track"><div class="fill" style="width:{max(width, 0.3):.2f}%"></div></div></td>'
        f'<td class="pct">{percent}</td></tr>'
        f'<tr class="gap"><td colspan="3" style="text-align:left;padding-top:.3rem">'
        f'actually came next &mdash; rank {probe["rank"]:,} of {probe["vocab"]:,} '
        f'&nbsp;<span class="score" style="background:rgba(255,80,120,{alpha:.3f})">'
        f'{probe["nats"]:.2f} nats</span></td></tr>'
    )
    return "".join(out)


def main():
    probes = collect()
    panels = []
    for probe in probes:
        panels.append(
            f'<figure><figcaption>{probe["title"]}</figcaption>'
            f'<p class="note">{probe["note"]}</p>'
            f'<div class="prefix">&hellip;{probe["prefix"].replace(chr(10), " ")}</div>'
            f"<table><tbody>{rows(probe)}</tbody></table></figure>"
        )
    splice = next(p for p in probes if "splice" in p["title"].lower())
    page = Template(PAGE).substitute(
        caption="One distribution, two uses: real output from Qwen3.5-0.8B-Base at three "
        "points in the contaminated text.",
        schema=SCHEMA,
        panels="".join(panels),
        foot=(
            "The bars are the model's six most likely continuations. The row under the rule "
            f"is what the text really did next. Scores are per token, so the splice costs "
            f"{splice['nats']:.2f} nats spread over {splice['chars']} characters, which is the "
            f"{splice['nats'] / splice['chars']:.2f} nats per character the other figures show."
        ),
    )
    (OUT / "fig-tokens.html").write_text(page)
    print(f"wrote {OUT / 'fig-tokens.html'} ({len(page) / 1024:.0f} KB)")


if __name__ == "__main__":
    sys.exit(main())
