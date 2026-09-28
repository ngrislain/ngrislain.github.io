import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 5: attention on a budget" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 10, day := 28 }
draft := true
%%%

:::hero "Compressed sparse attention, as introduced in DeepSeek-V4" "static/blog/deepseek-v41/hero-5-attention.png"
:::

This is part 5 of a series on DeepSeek-V4.1-Flash. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] explained why the KV cache is the thing to optimise. Parts {page_link Site.Blog.DeepSeekV41.Part2}[2], {page_link Site.Blog.DeepSeekV41.Part3}[3] and {page_link Site.Blog.DeepSeekV41.Part4}[4] went through everything around attention: the four-stream residual, the experts and the optimizers. None of it changed the size of the cache.

Now we get to the cache. It helps to split its cost into three factors:

$$`\text{cache per token} = \text{bytes per entry} \times \text{entries per token and per layer} \times \text{layers that store entries}`

Part 1 showed the first factor, with the figure that goes from plain multi-head attention to one 512-dimensional entry per token in 4 bits. This post is about the second factor, as designed in [DeepSeek-V4](https://arxiv.org/pdf/2606.19348). V4.1 keeps most of it. Part 6 covers the third factor, which is where V4.1 is new.

# A sliding window for the local part

Most of what a token needs is nearby. V4 and V4.1 give every attention layer a _sliding window_ branch ([Longformer](https://arxiv.org/pdf/2004.05150) popularised the idea): each token attends to the $`n_{\text{win}} = 128` tokens just before it, with ordinary uncompressed keys and values.

$$`o_i = \sum_{j=i-n_{\text{win}}+1}^{i} \operatorname{softmax}_j\big(q_i^\top k_j / \sqrt{d}\big)\, v_j`

The cache for this branch is 128 entries per layer, whatever the length of the context. For a long context it is a rounding error.

:::figframe "static/blog/deepseek-v41/widgets.html#swa" "390"
:::

The left grid is the attention mask: row $`i` is the query, column $`j` a key, and the coloured band is what each query may read. Hover over a row to pick the query. It is highlighted in blue in the mask. The *window* slider sets $`n_{\text{win}}` and the band gets wider.

The right panel answers a different question: after stacking several such layers, which original tokens can influence the selected one? Each layer extends the reach by $`n_{\text{win}} - 1`, so with window 4 and three layers the token sees 10 positions back. Move the *stacked layers* slider and the staircase grows. With V4.1's numbers, 128 tokens and 40 layers, the theoretical reach is 5,081 tokens. That is still tiny next to a million, which is why a separate global branch is needed. Remember the staircase anyway. In part 7 it turns out to be a problem, and V4.1 has a trick for it.

# Compressing the sequence

The global branch sees the whole context, but not token by token. Every $`m` consecutive tokens are merged into one cache entry. Each token $`j` produces a candidate entry $`C_j = h_j W^{KV}` and a set of weights $`Z_j = h_j W^{Z}`, both of the entry's dimension. Within a block, a softmax over the tokens, computed separately for each channel, decides how much each token contributes:

$$`S = \operatorname{softmax}_{\text{row}}(Z + B), \qquad C^{\text{Comp}}_i = \sum_{j \in \text{block } i} S_j \odot C_j`

V4 has two variants. _CSA_ (compressed sparse attention) uses $`m = 4` and a slightly richer version: each entry pools its own block and the previous one, $`2m` tokens in total, with learned positional biases $`B`. _HCA_ (heavily compressed attention) uses $`m' = 128` with no overlap. V4-Flash interleaves the two.

:::figframe "static/blog/deepseek-v41/widgets.html#compress" "450"
:::

The top row is 24 tokens. The coloured stripes under each token are four channels of its candidate entry. The row of boxes at the bottom are the compressed entries: hover one to select it. The yellow bars in the middle are the weights $`S` (for one channel) that build the selected entry. They sum to one.

In *CSA (V4)* mode with $`m = 2`, hover $`C_3`: four tokens contribute, two from its own block (yellow bars) and two from the previous block (orange bars). Now hover $`C_4`: its orange tokens are exactly the yellow tokens of $`C_3`. Every token feeds two neighbouring entries, which smooths the block boundaries. *HCA (V4)* merges 8 tokens per entry in this toy (128 in the real model) and the $`m` buttons grey out. *CSA2 (V4.1)* is the simplified version from part 6: no overlap, no positional bias. In that mode, click $`m = 1`: every weight is exactly 1.00, and there is nothing left to compress. That is the setting V4.1 uses in its decoder, for reasons part 6 explains.

The formula under the figure changes with the mode, so you can read which terms are dropped.

# Reading only what matters

Compression divides the number of entries by $`m`. At a million tokens and $`m = 4`, that is still 250,000 entries per layer, too many to attend to for every generated token. So CSA does not attend to all of them. A small _lightning indexer_, introduced in [DeepSeek-V3.2](https://arxiv.org/pdf/2512.02556), scores every compressed entry and the real attention reads only the top $`k = 512`.

The indexer is itself a tiny attention. The query token produces a few indexer queries $`q^I_{t,h}` and per-head weights $`w^I_{t,h}`, and each compressed block $`s` has an indexer key $`K^I_s`:

$$`I_{t,s} = \sum_{h} w^I_{t,h}\,\operatorname{ReLU}\big(q^I_{t,h} \cdot K^I_s\big), \qquad \mathcal{C}_t = \{\, C^{\text{Comp}}_s \mid I_{t,s} \in \operatorname{Top\text{-}k}(I_{t,:}) \,\}`

It still looks at every entry, but it is cheap. It has 32 heads of 128 dimensions in V4.1 (64 in V4) against 64 heads of 512 for the main attention, and it runs in FP4.

:::figframe "static/blog/deepseek-v41/widgets.html#indexer" "400"
:::

Each bar is the score $`I_{t,s}` of one compressed block, stacked by indexer head (four heads drawn), so you can see which head voted for which block. The boxes under the bars turn green for the selected top-k. The dashed red line is the causal limit: a query at position $`t` can only use blocks that are complete before it, $`s < \lfloor t/m \rfloor`, since a block still being filled would leak future tokens.

Move the *query position* slider and the red line moves with it. Blocks to its right fade out and can never be selected. Move *top-k* and more green boxes appear, always the tallest bars first. Look at a single bar. Because of the ReLU, a head whose query does not match a block contributes nothing to it, rather than a negative vote. One head that strongly likes a block can be enough to select it, and heads that do not care stay out of the way. (In the real model the head weights $`w^I_{t,h}` come from a linear projection and can be negative. In this toy they are all positive.) The scores here are random, so do not look for meaning in which blocks win.

# The whole CSA layer

Put the pieces together and you get Figure 3 of the V4 paper, which this last figure redraws.

:::figframe "static/blog/deepseek-v41/widgets.html#csa-v4" "580"
:::

Hover any box and the panel below the diagram shows its equation. Follow the left path from the bottom: hidden states, compressor, compressed entries, top-k selector. The dashed box in the middle is the lightning indexer, with its own compressor for keys and its queries coming from the query token on the right. At the top, the selected entries are concatenated with the sliding-window entries and fed to attention.

A few details in the top box are worth a hover. The attention is _shared-key-value multi-query attention_: the 64 heads all read the same entries, and each entry serves as both key and value, which is why the entry from part 1 could be a single vector. Queries and entries are RMS-normalised just before attention, which keeps the logits bounded (this is why V4 did not need the QK-clip trick when training with Muon, as mentioned in part 4). Rotary position embedding is applied only to the last 64 of the 512 dimensions. And since an entry is also a value, its position rotation leaks into the output, so V4 rotates each output back by the query position to keep only relative position. There is also an [attention sink](https://arxiv.org/pdf/2309.17453): a learned logit in the softmax denominator that lets a head give less than full attention to the real tokens. Finally the 64 head outputs, 32,768 numbers, are projected down in 8 groups before the final projection to 5120, because one direct projection would be very large.

HCA is the same layer without the indexer: with 128 tokens per entry there are few enough entries to attend to all of them. According to the V4 paper, this hybrid lets V4-Pro run a million-token context with 27% of the per-token FLOPs and 10% of the KV cache of V3.2.

# In perspective

With these pieces, the cost per generated token no longer depends much on the length of the context: 128 window entries plus 512 selected entries, whatever the length. The indexer still scans everything, but at a small fraction of the cost. The cache, however, still grows with every layer. V4-Flash has 41 layers with a global cache, and each one stores its own entries and its own indexer keys.

That is the starting point for V4.1. The V4.1 paper describes V4 in one sentence that I find very useful: a sliding-window backbone augmented with compressed global context. If the global context is a supplement, does every layer need its own copy? Part 6 answers no, and shows how much that saves.

The [interactive deck](static/blog/deepseek-v41/deck.html#/s-swa) has these figures plus one for the attention sink.
