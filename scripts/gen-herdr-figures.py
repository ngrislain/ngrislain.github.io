#!/usr/bin/env python3
"""Generate the Herdr post's standalone SVG figures (Python stdlib only).

Run from any directory. Rasterize process-ownership.svg with rsvg-convert
to refresh the listing/social thumbnail.
"""

from html import escape
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "static/blog/herdr"
OUT.mkdir(parents=True, exist_ok=True)
INK = "#213437"
MUTED = "#526366"
TEAL = "#176f68"
PALE = "#e5efeb"
AMBER = "#8e5716"
SAND = "#f3e7cf"
LINE = "#c8d1ca"
BG = "#faf8f1"


class Figure:
    def __init__(self, height, title, description, kicker, heading):
        self.height = height
        self.parts = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="{height}" '
            f'viewBox="0 0 1000 {height}" role="img" aria-labelledby="title desc">',
            f'<title id="title">{escape(title)}</title>',
            f'<desc id="desc">{escape(description)}</desc>',
            '<defs><marker id="arrow" markerWidth="9" markerHeight="9" '
            'refX="7" refY="4" orient="auto-start-reverse">'
            f'<path d="M0,0 L8,4 L0,8" fill="none" stroke="{TEAL}" '
            'stroke-width="1.5"/></marker></defs>',
            f'<rect width="1000" height="{height}" rx="18" fill="{BG}"/>',
            '<g font-family="Arial, Helvetica, sans-serif">',
        ]
        self.text(40, 41, kicker.upper(), 15, TEAL, weight="700", tracking="2")
        self.text(40, 82, heading, 30, INK, weight="700")

    def text(self, x, y, value, size=21, color=INK, weight="400", tracking="0", anchor="start"):
        self.parts.append(
            f'<text x="{x}" y="{y}" font-size="{size}" fill="{color}" '
            f'font-weight="{weight}" letter-spacing="{tracking}" '
            f'text-anchor="{anchor}">{escape(value)}</text>'
        )

    def lines(self, x, y, values, size=20, color=MUTED, gap=29):
        for i, value in enumerate(values):
            self.text(x, y + i * gap, value, size, color)

    def rect(self, x, y, width, height, fill="white", stroke=LINE, radius=12):
        self.parts.append(
            f'<rect x="{x}" y="{y}" width="{width}" height="{height}" '
            f'rx="{radius}" fill="{fill}" stroke="{stroke}" stroke-width="1.5"/>'
        )

    def arrow(self, x1, y1, x2, y2, dashed=False, both=False):
        dash = ' stroke-dasharray="7 6"' if dashed else ""
        start = ' marker-start="url(#arrow)"' if both else ""
        self.parts.append(
            f'<path d="M{x1},{y1} L{x2},{y2}" fill="none" stroke="{TEAL}" '
            f'stroke-width="2" marker-end="url(#arrow)"{start}{dash}/>'
        )

    def footer(self, number, value):
        self.text(40, self.height - 25, f"{number:02d} / {value}", 16, MUTED)

    def save(self, filename):
        (OUT / filename).write_text("\n".join(self.parts + ["</g></svg>"]) + "\n")


f = Figure(
    650,
    "Herdr process ownership",
    "A laptop client attaches over SSH to a remote Herdr server. The server owns "
    "agent and test panes. Each independent change uses its own checkout.",
    "Herdr / the process model",
    "Close the view. Keep the work running.",
)
f.rect(40, 130, 255, 390, PALE)
f.text(62, 169, "LAPTOP", 16, TEAL, "700", "1.5")
f.rect(62, 195, 211, 122)
f.text(82, 235, "Herdr client", 23, INK, "700")
f.lines(82, 269, ["Displays terminals", "Sends your input"], 18, gap=26)
f.lines(62, 378, ["Detach or close", "this client.", "The remote server", "still owns the work."], 20)
f.arrow(304, 255, 412, 255, both=True)
f.text(359, 225, "SSH", 18, TEAL, "700", anchor="middle")
f.text(359, 304, "reconnect", 15, MUTED, anchor="middle")
f.rect(430, 130, 530, 442, "#f0f2ed")
f.text(454, 169, "REMOTE EXECUTION HOST", 16, TEAL, "700", "1.5")
f.rect(454, 195, 482, 92, PALE, TEAL)
f.text(477, 232, "Herdr server", 24, INK, "700")
f.text(477, 263, "Owns terminals and running processes", 20, MUTED)
for x in (568, 822):
    f.arrow(x, 288, x, 332)
f.rect(454, 344, 228, 139)
f.text(472, 378, "Implementation", 21, INK, "700")
f.lines(472, 410, ["Agent + shell", "worktree: feature"], 18, gap=29)
f.rect(708, 344, 228, 139)
f.text(726, 378, "Review / tests", 21, INK, "700")
f.lines(726, 410, ["Agent or command", "worktree: review"], 18, gap=29)
f.text(454, 535, "The host must remain awake and available.", 20, MUTED)
f.footer(1, "Client lifetime and process lifetime are separate.")
f.save("process-ownership.svg")

f = Figure(
    660,
    "Persistence is not the same as recovery",
    "Detaching keeps processes alive. Sleeping pauses work on the laptop but "
    "not on an awake remote host. A server restart loses original processes; "
    "restored layout and supported conversation resume are different.",
    "Herdr / interruption boundaries",
    "What actually survives?",
)
f.text(64, 139, "EVENT", 15, MUTED, "700", "1.5")
f.text(330, 139, "ORIGINAL PROCESSES", 15, MUTED, "700", "1.5")
f.text(650, 139, "WHEN YOU RETURN", 15, MUTED, "700", "1.5")
rows = [
    (164, "Detach the client", ["Keep running", "on the execution host"], ["Attach to the same", "live terminals"], PALE, TEAL),
    (304, "Sleep the laptop", ["Remote host: continues", "Laptop host: pauses"], ["Location determines", "whether work progressed"], "#eef0ec", INK),
    (444, "Restart the server", ["Original processes stop", "New processes required"], ["Saved layout returns", "Agent resume if supported"], SAND, AMBER),
]
for y, event, live, result, fill, color in rows:
    f.rect(40, y, 920, 118, fill, fill)
    f.text(64, y + 47, event, 22, INK, "700")
    f.lines(330, y + 42, live, 20, color, gap=31)
    f.lines(650, y + 42, result, 20, INK, gap=31)
f.footer(2, "A recovered conversation is not an uninterrupted test run.")
f.save("persistence-boundaries.svg")

f = Figure(
    660,
    "Choose a tool by the responsibility you want to hand over",
    "Four overlapping choices: tmux and Zellij for persistent terminal sessions, "
    "Herdr for agent-aware runtime on your machines, cmux for a native Mac terminal "
    "and browser, Conductor for managed cloud agent sandboxes. This is not a ranking.",
    "Choosing the working environment",
    "Start with the responsibility.",
)
cards = [
    (40, 128, "Keep terminals alive", "tmux / Zellij", ["Persistent sessions", "Layouts and scripting", "Bring your own agent workflow"], "white", INK),
    (520, 128, "See which agent needs you", "Herdr", ["Agent state and control", "Persistent terminal runtime", "Run it on your machines"], PALE, TEAL),
    (40, 366, "Work in a native Mac terminal", "cmux", ["Tabs and attention signals", "A programmable browser", "SSH / tmux for remote work"], "white", INK),
    (520, 366, "Hand over cloud environments", "Conductor", ["Managed agent sandboxes", "Desktop, mobile and API", "Less host setup to maintain"], SAND, AMBER),
]
for x, y, question, name, lines, fill, accent in cards:
    f.rect(x, y, 440, 210, fill)
    f.text(x + 22, y + 33, question, 19, MUTED)
    f.text(x + 22, y + 75, name, 29, accent, "700")
    f.lines(x + 22, y + 113, lines, 20, INK, gap=30)
f.footer(3, "Overlapping tools. Different defaults. No universal winner.")
f.save("alternatives.svg")
print(f"Generated three SVG figures in {OUT}")
