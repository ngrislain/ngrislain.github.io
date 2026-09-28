import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 9: what it adds up to" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 25 }
draft := true
%%%

:::hero "From one attention layer to the whole model" "static/blog/deepseek-v41/hero-9-zoomout.png"
:::

This is the last part of a series on DeepSeek-V4.1-Flash. Over eight posts we took the model apart. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] set the problem: for long, input-heavy work, the KV cache costs more than the arithmetic. {page_link Site.Blog.DeepSeekV41.Part2}[Part 2] widened the residual stream to four streams and kept it stable with doubly stochastic mixing. {page_link Site.Blog.DeepSeekV41.Part3}[Part 3] covered the 384 experts per layer and their load balancing, per modality. {page_link Site.Blog.DeepSeekV41.Part4}[Part 4] was about the optimizers, Muon and a Sinkhorn update for tables. {page_link Site.Blog.DeepSeekV41.Part5}[Part 5] described V4's compressed sparse attention, {page_link Site.Blog.DeepSeekV41.Part6}[part 6] how V4.1 shares its cache across layers and stores it in 4 bits, {page_link Site.Blog.DeepSeekV41.Part7}[part 7] the encoder-decoder split and bounded replay, and {page_link Site.Blog.DeepSeekV41.Part8}[part 8] the modules on the side: Engram, DSpark and vision.

This post puts the pieces back together, then says what I take away from the model.

# Zooming out

The figure below is one drawing at four scales. You can move between them with the four buttons at the top. The transition is a continuous zoom, so you can see where each level sits inside the next.

:::figframe "static/blog/deepseek-v41/widgets.html#zoom" "560"
:::

It opens on *① CSA2 layer*: one attention layer, the first layer of the decoder, in Full mode. Almost every box points back to a post. The green inputs are what the layer computes itself: its queries and its sliding-window keys (part 5), its main entries in FP4 (part 6) and the indexer keys projected from them (part 6). The yellow box at the bottom is where the main entries come from: not this layer's own hidden state, but the encoder's output, which is the CED projection from part 7. The indexer on the right selects the top 512 entries and, because this is the decoder's first indexer, also builds the candidate pool for the four Reindex layers above it (part 6). The dashed arrow at the top leads to the grouped output projection (part 5).

Click *② mHC block*. The layer shrinks into the green "CSA2 attention" box, the lower half of one Transformer block. This is the layout of Figure 2 in the [V4 paper](https://arxiv.org/pdf/2606.19348). Each of the two sublayers, attention and MoE, reads from the four residual streams through pre-block mixing ($`A_{l-1}`, shifted by one block in V4.1, part 2), writes back through post-block mixing ($`C_l`), and the streams are mixed with each other by the doubly stochastic $`B_l`. The top box is the DeepSeekMoE layer from part 3, with its handful of red active experts. You can click the green box to zoom back in.

Click *③ 40-layer stack*. The block becomes the small purple icon next to layer 20, and the whole schedule appears: the encoder on the left, the decoder on the right, every layer labelled with its CSA2 mode and colour. The yellow arcs connect each layer to the Full layer whose entries it reuses, and the dashed red ones to the layer whose top-512 selection it reuses. The brown arrow from the top of the encoder into layer 20 is CED. Only the four green layers write to the global cache, which is the 890 bytes of part 6. Clicking the purple icon next to layer 20 zooms back into the block.

Click *④ full model*. The stack folds into the two frames of the paper's own diagram (Figure 3 of the [V4.1 paper](https://arxiv.org/pdf/2609.19969)), and the outside world appears: text and vision embeddings entering through single-pass mHC, Engram feeding layers 1 and 14, the candidate pool, DSpark at the top. At this level each box is a link: clicking one opens the slide of the [interactive deck](static/blog/deepseek-v41/deck.html) that explains it, in a new tab. The caption under the figure summarises each level as you go.

# What the pieces have in common

Looking at all of it together, most of the changes are about moving bytes, not about doing fewer operations. Single-pass mHC changes an equation so that a kernel reads the residual stream once instead of twice. CSA2 and FP4 shrink what sits in GPU memory. Bounded replay removes a whole class of cache from disk. Engram keeps 196B parameters in host memory and fetches rows before they are needed. Even the load-balancing bias is partly about keeping every GPU equally busy. The one number about compute in the paper confirms it: going from 4K to 1M tokens of context increases the cost of decoding one token by only about a quarter.

The methods repeat too. DeepSeek constrains rather than penalises: the mixing matrix is projected onto a safe set, expert load is steered by a bias outside the gradient. It shares instead of duplicating: one global cache for six layers in the encoder and for all twenty in the decoder, one top-512 selection for four to six layers. And it approximates where it is cheap, then trains for the approximation: 4-bit entries with quantization-aware training, the candidate pool introduced in post-training, the decoder replay simulated in post-training. That last habit is what I would most like to copy. An approximation that the model has seen during training is a different object from one added at inference time.

Very little of this is new in isolation, and the paper is candid about its sources. Sharing layers comes from [YOCO](https://arxiv.org/pdf/2405.05254) and [cross-layer attention](https://arxiv.org/pdf/2405.12981). Index reuse comes from [IndexCache](https://arxiv.org/pdf/2603.12201), hierarchical indexing from [HISA](https://arxiv.org/pdf/2603.28458), Sinkhorn updates from [SinkGD](https://arxiv.org/pdf/2502.06742), the FP4 format from NVIDIA's NVFP4. The contribution is putting all of them in one model, making them work together at 552B parameters, and writing the kernels. That is less exciting to read than a new idea and much harder to do.

# What we do not know

The paper reports end results: the base model is comparable to DeepSeek-V4-Pro-Base with a third of its parameters and a quarter of its active parameters, it is 5 to 10% better on held-out evaluations, and the chat model reaches 74.2% on DeepSWE against 54.4% for V4-Flash. What it does not give is an ablation for each piece. Single-pass mHC, bounded replay and FP4 entries each come with a sentence like "negligible degradation" and no table. So we know what each piece saves, and you can measure most of it in the figures of this series, but not what each one costs in quality. The bounded replay and the CSA2 selection errors are the two the authors themselves flag as risks in untested cases.

There is also a larger question that this series kept brushing against. In my {page_link Site.Blog.Mamba3}[note on Mamba-3] I described the other road to cheap long context: replace attention by a recurrent state of fixed size. V4.1 looks different, but step back and the two are closer than they seem. Its sliding window is a fixed-size local state that every layer keeps and that does not grow with the context. Its global memory does grow, but at 890 bytes per token, and it is read sparsely, 512 entries at a time. The Mamba-3 paper found that mixing in a few attention layers, one for every five recurrent ones, recovers much of the retrieval ability that pure recurrent models lack. V4.1 arrives at something similar from the other side: mostly local processing, with a small, shared, sparsely read global memory.

For my own work on {page_link Site.Blog.AnomalyDetection}[models that read logs], this is the part I keep thinking about. Logs are the extreme case of input-heavy: millions of events read, one score written per event. The question V4.1 answers for agents, how little global memory you can keep per token and still find what matters, is the same question.

Thanks for reading along. All nine posts share the same figures, and the [interactive deck](static/blog/deepseek-v41/deck.html) has them all in one place, with a few slides on textbook components that the series skipped.
