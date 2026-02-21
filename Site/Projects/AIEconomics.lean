import VersoBlog

open Verso Genre Blog

#doc (Post) "How to Die Optimally — AI meets Economics" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 02, day := 20 }
%%%

It started over lunch with two economist friends. We were having one of those long conversations about AI and economics — what happens to labor income when machines get good enough, whether capital saves you or dooms you, the usual cheerful lunchtime topics. By dessert, we had talked ourselves into a challenge: write an interactive research paper about it, in the style of the AER, with Yannick's idea as the starting point.

The result is here: [How to Die Optimally — A Theory of Consumption When AI Takes Your Job](static/projects/ai-economics/ai-economics.html).

It is an interactive paper with sliders and live plots — go play with it.

# What it is about

Imagine your labor income is being eaten away by AI — exponentially. You can save, you can invest, but eventually the math catches up: your lifetime earnings cannot fund subsistence forever. The question is not *whether* you die (economically), but *when* — and whether you do so with dignity or surprise.

We set up a classical optimal control problem — a consumer maximizing log-utility over an endogenous horizon — and solve it with Hamiltonian methods. The punchline: if you plan ahead, you live significantly longer and better than if you just spend your paycheck as it comes. Above a critical rate of return on capital, you can even live forever. Below it, at least you die *optimally*.

The paper features what we call an immortality frontier — a boundary in parameter space between finite and infinite life:

![Immortality Frontier — the boundary between finite life (orange) and infinite life (green)](static/projects/ai-economics/immortality-frontier.png)

The green zone is where capital returns grow fast enough to sustain you indefinitely. The orange zone is everyone else. Reassuringly, which zone you're in is just a function of the parameters.

The paper is short, somewhat irreverent, and comes with interactive visualizations so you can drag sliders and watch the optimal death date move in real time.

# How it was made

This was my first application of frontier LLMs to economics research. Starting from Yannick's idea and a few days of pen-and-paper scribbling to sharpen intuitions, get a clear formulation of the optimization problem, and understand the shape of the solution, we delegated most of the execution to AI. After a few back-and-forth prompting rounds — mainly with Claude and GPT — to get proper visualization, polish the text, and explore extensions, voila, we got the paper.

The whole process took a few hours of work here and there over a few days, on top of our regular full-time jobs. This is truly amazing, but as the paper itself suggests, there may be some big downsides to it.

[Read the paper here.](static/projects/ai-economics/ai-economics.html)
