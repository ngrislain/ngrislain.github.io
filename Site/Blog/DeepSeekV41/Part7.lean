import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 7: half a model to read the prompt" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 11 }
draft := true
%%%

:::hero "Which layers run for which tokens during a CED prefill" "static/blog/deepseek-v41/hero-7-ced.png"
:::

This is part 7 of a series on DeepSeek-V4.1-Flash. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] listed three costs for long, input-heavy workloads: prefill compute, the runtime KV cache in GPU memory, and the persistent KV cache on SSD. {page_link Site.Blog.DeepSeekV41.Part5}[Part 5] and {page_link Site.Blog.DeepSeekV41.Part6}[part 6] took care of the second one: the global cache is down to 890 bytes per token, because only four layers out of forty store it and they store it in 4 bits.

This post is about the other two costs. Both are handled by one architectural change and one deployment trick. The change is the _causal encoder-decoder_ (CED), and it is the reason the V4.1 paper can say the model activates 8B parameters per token at prefill but 16B at decode. The trick is _bounded replay_ of the sliding-window cache, which removes that cache from disk entirely.

# The prefill problem

An agent works in a loop. Call a tool, get a result, append it to the context, generate a few lines, call the next tool. Every step sends a prompt that is mostly old context plus a new chunk. When the prefix is cached, only the new chunk needs a forward pass. When it is not cached, or when the chunk is a 50-page document, the whole thing goes through all 40 layers. For this kind of work, prefill is most of the compute.

[YOCO](https://arxiv.org/pdf/2405.05254) ("you only cache once") proposed a way out: let the top half of the layers use keys and values produced by the bottom half. Then a prompt only needs to go through the bottom half. The top half is needed only for the tokens you generate.

# The causal encoder-decoder

V4.1 applies this to the global branch of attention. The bottom 20 layers form the _encoder_ and the top 20 the _decoder_. The decoder's global entries are not computed from the decoder's own hidden states but projected from the encoder's output:

$$`C_l = H_{L/2}\,W^{KV}_l, \qquad Z_l = H_{L/2}\,W^{Z}_l, \qquad l > L/2`

Here $`C_l` and $`Z_l` are the entries and compression weights from part 5, and $`H_{L/2}` is the hidden state after layer 20. Combined with part 6, it is even simpler: only one decoder layer runs in Full mode (layer 20), so a single projection of the encoder output produces the entire global cache of the decoder. Its Reindex and Reuse layers work as before.

There is one difference from YOCO. The sliding-window branch stays _layer-local_: every layer, decoder included, computes its window keys from its own hidden states. The paper argues this keeps more depth in the local processing. It also creates a problem, which the replay section below solves.

:::figframe "static/blog/deepseek-v41/widgets.html#ced" "440"
:::

The grid is a toy model with 8 layers (4 encoder, 4 decoder, from bottom to top) and 22 positions: 19 prompt tokens and 3 to be generated. The dashed line between the halves is $`H_{L/2}`. Green cells run the full layer. White cells with a yellow dot only get their global entries from $`H_{L/2}` by a projection. Orange cells are the decoder's sliding-window replay, explained below. Pale cells are already in the cache.

Click *decoder-only prefill*: every layer runs for every prompt token, the usual picture. Click *CED prefill*: the encoder rows are fully green, but in the decoder only the last few prompt tokens run (orange). All the other decoder cells just receive their global entries. (The toy puts a dot in every decoder layer, as in the general CED formula. In V4.1 only layer 20 does the projection and the others reuse it.) Click *CED decode step*: the new token, in the first "gen" column, runs through all 8 layers, and the decoder layers read the cached entries built from the encoder.

The line at the bottom counts layer passes over the prompt. Move the *prompt* slider: at 100K tokens CED needs 50.1% of the passes of a decoder-only model, at a million 50.0%. The formula is

$$`\mathcal{O}(NL) \;\longrightarrow\; \mathcal{O}\big(NL/2 + n_{\text{win}}\,L/2\big) \approx \mathcal{O}(NL/2)`

That is where the 8B and 16B come from. At prefill a token only goes through the encoder, half the layers, so about half the active parameters. At decode it goes through all 40.

# Replaying the sliding window

Now the problem. To generate its first token, the decoder needs its own sliding-window cache: in each decoder layer, the window keys of the last 128 prompt tokens. Those come from the decoder's hidden states, which CED just skipped computing.

Recall the staircase from part 5. To get the exact window state of the top layer, you need the window of the layer below, which needs a longer window below it, and so on. Exact reconstruction of $`L` layers needs the last $`L \times n_{\text{win}}` tokens. For the 20 decoder layers that is 2,560 tokens, a real cost when the new chunk is short.

V4.1 does not reconstruct exactly. _Bounded replay_ runs only the last $`n_{\text{win}}` tokens and truncates the window at the start of the replay. For a replay starting at position $`s`, query $`i` sees the window keys in

$$`\big[\max(s,\; i - n_{\text{win}} + 1),\; i\big]`

instead of $`[i - n_{\text{win}} + 1, i]`. The first replayed tokens see a shorter window than they should, so the state is approximate. The paper cites [PowerAttention](https://arxiv.org/pdf/2503.03588), which found that the effective reach of stacked window attention is much shorter than the theoretical one, and reports that the approximation has "negligible" impact. For safety, the same replay is simulated during post-training so the model gets used to it.

:::figframe "static/blog/deepseek-v41/widgets.html#replay" "410"
:::

Five layers, 24 cached prompt tokens and 4 new ones. Pale yellow cells are cached (their global entries are kept, their window keys are gone), green cells are the new suffix, and orange cells are tokens that must be replayed to rebuild the window state.

With *exact reconstruction* selected, you see the staircase: the bottom layer has to replay much further back than the top one, because every layer's window depends on a longer window below it. Switch to *bounded replay (V4.1)*: every layer replays the same few tokens. The small mask underneath shows the replayed segment. Blue cells are the keys each query actually attends to, and pink cells are keys the exact computation would have used but the truncation cuts off. Move the window slider and both pictures scale. The real numbers are on the right: about 2,560 tokens replayed exactly against 128 bounded.

# Deleting a cache from disk

The same trick is also used in the encoder, and there it changes the storage bill.

The V4 deployment kept two kinds of persistent cache on SSD: global entries, reused across requests for days, and window keys at a few positions so that a conversation could resume. According to the V4.1 paper, the window keys took nearly half of the persistent cache. They were also a poor fit for it. Global entries have long-tail reuse, but window keys are only useful for a few minutes, inside an active session.

With encoder bounded replay, V4.1 stops persisting them. Window keys now live in a small memory pool in host RAM (10% of each machine's DRAM) with a lifetime of minutes. Global entries stay on SSD for at least 72 hours. When a request hits the global cache but the window keys have expired, the server replays the last $`n_{\text{win}}` cached tokens together with the new suffix to rebuild them, instead of a full pass over $`L \times n_{\text{win}}` tokens. V4 had tried exact recomputation, and the paper says its cost "proved prohibitive" in production.

The persistent cache is then:

$$`\underbrace{\tfrac{1}{2}}_{\text{no window keys}} \times \underbrace{\tfrac{1}{4}}_{\text{smaller global cache, part 6}} \approx \tfrac{1}{8} \text{ of V4-Flash}`

# In perspective

This is the post where the three costs from part 1 are all addressed. The runtime cache shrank in part 6. Prefill compute is halved by CED. The persistent cache is an eighth of V4's, thanks to a smaller global cache and no window keys on disk.

It is also where V4.1 accepts approximation most openly. Bounded replay does not compute the same states as the full model, and the suffix computed after a cache hit depends on where the hit happened. DeepSeek measured the impact and simulated it in training, but the conclusion of the paper lists "approximate state reconstruction in SWA Bounded Replay" among the things that could still fail in untested cases, right next to the CSA2 selection errors from part 6. The approximations in earlier parts, like 4-bit entries or the candidate pool, are part of the model being trained. Bounded replay is different in kind: at inference the model computes states it never computed when the cache was written, and the gap is closed only by measuring it and by simulating it in post-training. It trades exactness for storage, knowingly.

What is left are the two modules on the side of the map, Engram and DSpark, and the way images get in. That is part 8.

The [interactive deck](static/blog/deepseek-v41/deck.html#/s-ced) has the same two figures.
