import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 6: four layers keep the cache" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 04 }
draft := true
%%%

:::hero "The 40 layers of DeepSeek-V4.1-Flash and the cache they share" "static/blog/deepseek-v41/hero-6-csa2.png"
:::

This is part 6 of a series on DeepSeek-V4.1-Flash. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] introduced the three factors of the KV cache: bytes per entry, entries per layer, and layers that store entries. {page_link Site.Blog.DeepSeekV41.Part5}[Part 5] covered the second factor as DeepSeek-V4 designed it: a sliding window for local context, compressed entries for the global context, and a lightning indexer that picks 512 of them for each query. Parts {page_link Site.Blog.DeepSeekV41.Part2}[2], {page_link Site.Blog.DeepSeekV41.Part3}[3] and {page_link Site.Blog.DeepSeekV41.Part4}[4] described the rest of each layer.

This post is about the third factor, which is where [V4.1](https://arxiv.org/pdf/2609.19969) is new. In V4-Flash, 41 layers each keep their own global cache. In V4.1, four do. Together with 4-bit storage, that brings the global cache down to 890 bytes per token. By the end of the post you can check that number yourself.

# Sharing across layers

Reusing another layer's cache is not a new idea. [Cross-layer attention](https://arxiv.org/pdf/2405.12981) shares keys and values between adjacent layers. [IndexCache](https://arxiv.org/pdf/2603.12201) reuses sparse attention indices across layers to save indexer work. [YOIO](https://arxiv.org/pdf/2606.06467) computes one sparse selection and shares it across the whole network. [HySparse](https://arxiv.org/pdf/2602.03560) lets sparse layers read the cache of a few full-attention layers. The V4.1 paper points out what each leaves on the table: sharing indices saves no storage, one selection for the whole network costs quality, and hybrids keep full-attention layers. Its own design, CSA2, shares the cache and the selection _separately_, and combines that with the compression from part 5.

Each CSA2 layer is given one of three modes when the model is designed:

: Full

  The layer computes its own global entries, projects indexer keys from them, runs its indexer and picks its own top 512. This is a complete CSA layer from part 5.

: Reindex

  The layer reuses the most recent global entries and indexer keys, but computes its own indexer queries, scores the shared keys again and picks its own top 512.

: Reuse

  The layer reuses the entries and the latest top-512 selection as they are, and goes straight to attention. No indexer at all.

In all three modes the layer keeps its own attention queries and its own sliding-window cache, so each layer still computes something different. CSA2 also simplifies CSA: the compressor loses its overlap and positional bias (you saw this in the compressor figure of part 5), and the indexer keys are now a projection of the main entries instead of a separate compression path.

:::figframe "static/blog/deepseek-v41/widgets.html#csa2-modes" "490"
:::

The buttons switch between the three modes. The diagram is Figure 4 of the paper, redrawn. The colours tell where each input comes from. Green is computed in this layer. Yellow means main entries and indexer keys borrowed from the last Full layer. Pink means a top-512 selection borrowed from the last layer that ran an indexer. The column on the right lists, row by row, what the layer computes and what it borrows.

Click *Reindex*: the indexer is still there, but its keys have turned yellow. Click *Reuse*: the indexer disappears and the selection itself arrives from outside, in pink. Main Q and SWA KV stay green in every mode.

The strip at the bottom is the actual layer schedule of V4.1, layers 0 to 39, with the encoder on the left of the vertical bar and the decoder on the right. The layers drawn with a dark outline are the ones in the selected mode. In the encoder, after two layers with a sliding window only, there are three groups of six layers: one Full followed by five Reuse, with compression $`m = 2`. The decoder has five groups of four: the first starts with a Full layer, the other four with a Reindex layer, each followed by three Reuse layers, with $`m = 1` (no compression). Click *Full*: only four layers light up.

Why no compression in the decoder? The paper does not say. My reading is that it can afford it: with a single Full layer in the whole decoder, even one entry per token is cheap, and those are the entries the model reads when it writes. Part 7 explains where that decoder Full layer gets its input from.

# A hierarchy of indexers

Reuse layers skip the indexer, but Full and Reindex layers still score every visible entry. In the decoder, at $`m = 1` and a million tokens, that is a million scores per query for each of the five indexers. V4.1 adds a _hierarchical sparse indexer_, only in the decoder. The Full layer scores everything, as before. It also takes the maximum score within each block of 8 positions and keeps the best 2,048 blocks, a pool of 16,384 candidates. The four Reindex layers then score only that pool. A related idea appeared in [HISA](https://arxiv.org/pdf/2603.28458).

:::figframe "static/blog/deepseek-v41/widgets.html#hsi" "420"
:::

The three panels go left to right, like the data. On the left, the Full layer's scores for 24 blocks of 8 positions (darker is higher, green is its top 12). In the middle, the candidate pool: the blocks with the highest maximum score. On the right, a Reindex layer's scores, drawn only inside the pool (blue outline). Its green cells are its own top 12, chosen from the pool.

A deeper layer does not want the same entries as the first one, otherwise it could simply reuse them. The *layer correlation* slider sets how similar the two layers' scores are, and the text on the right reports how many of the Reindex layer's picks would have been the same without the pool restriction. With 6 blocks kept, a correlation of 0.75 gives 75% overlap. Drop the correlation to 0.3 and it falls to about 40%: the deeper layer wants things the first layer did not rank. Raise *blocks kept* to 12 and it climbs back to about 67%, at the cost of scoring more. The trade-off is between the size of the pool and how much the layers disagree.

The lower right does the arithmetic for the real configuration. At about a million tokens, each Reindex layer scores 16,384 positions instead of a million, 64 times fewer. DeepSeek applies the same restriction during training (it is added in post-training), so the deeper indexers learn to work inside the pool rather than being cut off at inference time.

# Four bits per value

The third lever is the size of each entry. V4 stored the 448 non-positional dimensions of an entry in FP8 and the 64 positional ones in BF16, 576 bytes. V4.1 stores all 512 dimensions in a 4-bit float format, E2M1, with one 8-bit scale (E4M3) for every 16 values. That is 256 bytes of values plus 32 bytes of scales: 288 bytes. The model is trained for it with quantization-aware training during post-training ([Jacob et al.](https://arxiv.org/pdf/1712.05877) is the classic reference for the technique). Values are dequantised before attention, so the format does not need hardware support for 4-bit matrix products.

:::figframe "static/blog/deepseek-v41/widgets.html#fp4" "410"
:::

The figure shows one group of 16 channels. Grey bars are the original values, blue bars what survives quantisation, and the faint horizontal lines are the values the format can represent once scaled. E2M1 has only 15 of them: plus or minus 0, 0.5, 1, 1.5, 2, 3, 4 and 6. *Resample* draws a new group, usually with one outlier. The scale is set so that the largest value maps to 6, and everything else snaps to the nearest grid line.

The other button switches to MXFP4, the [OCP microscaling format](https://arxiv.org/pdf/2310.10537) that V4 already used for indexer queries and keys: same E2M1 values, but one scale per 32 values, and the scale must be a power of two. On the default group the error goes from 7.2% to 12.6%. A power-of-two scale cannot match the group's maximum exactly, so either the largest values get clipped at 6 or part of the grid is never used, and one scale for 32 values follows the data less closely than one for 16. That is why the main entries get the finer format.

NVIDIA's NVFP4 format adds a second, global scale on top. DeepSeek drops it with a neat argument: entries are RMS-normalised before attention, so a 512-dimensional entry has norm at most about $`\sqrt{512} \approx 22.6`, and rotary embedding does not change the norm. The format can represent values up to $`448 \times 6 = 2688`. There is no range problem to solve. The sliding-window cache stays in FP8: the paper found it more sensitive to quantisation.

# Where 890 bytes come from

The paper gives the total and the configuration, but not the sum. Here is my reconstruction, and it lands exactly on the paper's number:

$$`\underbrace{\left(3 \times \tfrac{1}{2} + 1\right)}_{\text{entries per token}} \times \big(\underbrace{288}_{\text{main entry}} + \underbrace{68}_{\text{indexer key}}\big) = 2.5 \times 356 = 890 \text{ bytes}`

Three Full layers in the encoder, at one entry per two tokens, and one in the decoder at one entry per token. The indexer key has 128 dimensions in MXFP4: 64 bytes of values and 4 bytes of scales.

:::figframe "static/blog/deepseek-v41/widgets.html#kv-budget" "410"
:::

The top bar is V4.1, split into its four parts. The second bar is V4-Flash, from my own estimate based on its published configuration: 21 CSA layers at $`m = 4`, 20 HCA layers at $`m' = 128`, 576-byte entries. It comes out at 3,471 bytes, so V4.1 is at 0.26 of it, consistent with the "roughly one quarter" in the paper. The lower chart multiplies by the context length, on a log scale, next to a plain BF16 grouped-query baseline with 43 layers.

Now take it apart with the checkboxes. Untick *cross-layer KV sharing*: every CSA2 layer keeps its own entries, and the cost jumps to 10,324 bytes per token, almost 12 times more. Tick it again and untick *FP4 main KV*: 1,610 bytes. Sharing is by far the bigger lever. FP4 is worth a bit less than 2 on top. Move the *context* slider: at a million tokens, V4.1's global cache is under a gigabyte, while the grouped-query baseline is 185 GB.

# In perspective

With this post the three factors are complete. Part 1 covered the size of an entry, part 5 the number of entries per layer, and this post the number of layers, plus 4 bits for the entries themselves. The general idea is to treat the global context as a shared resource: computed a few times, stored once, read by many layers through their own queries.

There is a cost, and the paper says so in its conclusion: "Potential selection errors in CSA2 and approximate state reconstruction in SWA Bounded Replay may still cause capability degradation in untested boundary cases." A Reuse layer reads the entries a previous layer thought were relevant, and the candidate pool limits what later indexers can find. On the benchmarks reported that does not show, but the risk is real and the authors name it.

The second half of that sentence, bounded replay, is the subject of part 7, together with the other big change in V4.1: the encoder-decoder split, which decides where the decoder's Full layer gets its keys from.

The slides for this post start [here in the interactive deck](static/blog/deepseek-v41/deck.html#/s-csa2).
