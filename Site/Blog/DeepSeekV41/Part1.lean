import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 1: the cache is the bottleneck" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 09, day := 30 }
draft := true
%%%

:::hero "The architecture of DeepSeek-V4.1-Flash, redrawn" "static/blog/deepseek-v41/hero-1-map.png"
:::

On September 17, DeepSeek published [DeepSeek-V4.1-Flash: Pushing the Limits of KV Cache Compression](https://arxiv.org/pdf/2609.19969). The model has 552B parameters in its backbone, 196B more in lookup tables, reads text and images, and handles contexts of one million tokens. The number I keep coming back to is not a benchmark score. It is this one: the model keeps *890 bytes of global KV cache per token*. That is about a quarter of what DeepSeek-V4-Flash needs, even though V4.1 is about twice as large.

This is the first post of a short series where I take the model apart, one component at a time. Each post covers one or two pieces, with the equations, the reason the piece is there, and an interactive figure you can play with. At the end, we put everything back together.

# Why this model

I work on security detection. The model I build, described in {page_link Site.Blog.AnomalyDetection}[an earlier post], reads long streams of audit logs and writes almost nothing: a score per event. Long input, short output. Agents have the same shape. Every tool call appends a file, a page or a screenshot to the context and asks for a few hundred tokens back. The expensive part is reading, not writing.

For this kind of work, two costs dominate. The first is compute at _prefill_, the pass over the prompt, which you pay again every time the cache misses. The second is memory: the keys and values of every past token, kept so that the model does not recompute them. DeepSeek splits the second cost in two. The _runtime_ KV cache lives in GPU memory (HBM) during a request. The _persistent_ KV cache lives on SSD or in host memory, so that a long shared prefix can be reused across requests and across days.

There are two broad answers to the memory problem. In my {page_link Site.Blog.Mamba3}[note on Mamba-3] I described the first: replace attention by a recurrent state of fixed size, so memory stops growing with the context. DeepSeek takes the other road. It keeps attention and makes each remembered token cheaper, until a million of them fit in less than a gigabyte. This series is about how.

# What a KV cache costs

During decoding, each new token attends to all previous ones. The previous tokens' keys and values do not change, so the model caches them. The figure below compares how much each attention design caches per token and per layer.

:::figframe "static/blog/deepseek-v41/widgets.html#kvcache" "400"
:::

The buttons at the top select a design. The row of blue boxes stands for the 64 query heads (16 are drawn). Under them is what is cached for one token, and the arrows show which heads read which cached vectors. The bar chart at the bottom lists all designs on a log scale, so each step to the right is a multiplication, not an addition.

Start with *MHA*, plain multi-head attention from [the original Transformer](https://arxiv.org/pdf/1706.03762): every head caches its own key (red) and value (green). With 64 heads of 128 dimensions in BF16, that is 32 KB per token and per layer. Click *GQA-8* ([grouped-query attention](https://arxiv.org/pdf/2305.13245)): eight groups of heads share one key and one value each, and the arrows fan out. *MQA* ([multi-query attention](https://arxiv.org/pdf/1911.02150)) pushes this to a single shared pair, 512 bytes. *MLA* is what DeepSeek used in [V2](https://arxiv.org/pdf/2405.04434) and [V3](https://arxiv.org/pdf/2412.19437): the cache holds a 512-dimensional latent vector plus a small 64-dimensional key for positions, and the per-head keys and values are rebuilt from it by matrices that can be folded into the query and output projections.

The last two buttons are the V4 family. In *Shared-KV MQA* a single 512-dimensional entry is used both as the key and as the value of every head, stored in FP8 except for the 64 position dimensions. The final button stores the same entry in 4-bit floats, 288 bytes, which is what V4.1 does. Read the formula under the chart when you switch: it states exactly what is stored.

Now scale it up. Plain MHA over 43 layers and one million tokens would take about 1.4 TB. V4.1's global cache for the same million tokens is about 890 MB. The entry size explains only part of that gap. The rest comes from storing fewer entries per layer, and fewer layers that store anything at all. Those are the next posts.

# The map

Here is the full model, redrawn from Figure 3 of the paper. Clicking a box opens the matching slide of a longer [interactive deck](static/blog/deepseek-v41/deck.html) I made while reading, which has one slide per component.

:::figframe "static/blog/deepseek-v41/widgets.html#map" "400"
:::

It reads bottom to top. Text and image embeddings enter a 20-layer _causal encoder_ on the left. Its output feeds a 20-layer _decoder_ on the right through the arrow labelled CED. Every layer pairs an attention block with a mixture-of-experts block (the boxes labelled MoE). The colours tell you what each attention layer does with the cache. Orange is sliding-window attention only. Green layers compute and store new global keys and values. Yellow layers store nothing and reuse the cache of the last green layer. Blue layers also reuse it, but pick their own entries to read from it. Count the green boxes with their repetition factors and you get four layers, out of forty, that write to the global cache. The teal box on the left, Engram, is a lookup table of n-gram embeddings. DSpark at the top drafts tokens for speculative decoding.

Every one of these boxes comes from an earlier paper, often an earlier DeepSeek paper. What is new in V4.1 is mostly in how they are combined and in a few small changes that make them cheaper to run.

# The plan

The series follows the order in which the pieces depend on each other.

Part 2 is about the residual stream, which V4 widened to four parallel streams, with a constraint that keeps them from blowing up. Part 3 covers the experts, where almost all the parameters are, and how DeepSeek keeps them busy without an auxiliary loss. Part 4 is about training: Muon for most matrices, and a new Sinkhorn-based update for the huge embedding tables.

Parts 5 and 6 are about attention. Part 5 describes V4's version: a sliding window for local context, and a compressed global cache read through a small, fast indexer. Part 6 shows how V4.1 shares that cache across layers and stores it in 4 bits, and rebuilds the 890 bytes from the configuration. Part 7 explains the encoder-decoder split, which halves prefill, and the trick that removes a whole category of cache from disk. Part 8 covers the two modules on the side, Engram and DSpark, plus the vision input. Part 9 steps back and puts it all together.

A word on the figures. The equations and configuration numbers come from the papers. The data inside the widgets (attention scores, routing, hash values) is synthetic, chosen to show the mechanism.

Primary sources for the whole series: the [DeepSeek-V4.1-Flash paper](https://arxiv.org/pdf/2609.19969), the [DeepSeek-V4 paper](https://arxiv.org/pdf/2606.19348) it builds on, [mHC](https://arxiv.org/pdf/2512.24880), and the [DeepSeek-V3 report](https://arxiv.org/pdf/2412.19437).
