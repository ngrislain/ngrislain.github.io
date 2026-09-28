import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 8: a lookup table and a draft" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 11, day := 18 }
draft := true
%%%

:::hero "Engram: hashed n-gram lookups with a context-aware gate" "static/blog/deepseek-v41/hero-8-engram.png"
:::

This is part 8 of a series on DeepSeek-V4.1-Flash. The first seven parts built the backbone: the {page_link Site.Blog.DeepSeekV41.Part2}[four-stream residual], the {page_link Site.Blog.DeepSeekV41.Part3}[experts], the {page_link Site.Blog.DeepSeekV41.Part4}[optimizers], the {page_link Site.Blog.DeepSeekV41.Part5}[compressed sparse attention] inherited from V4, the {page_link Site.Blog.DeepSeekV41.Part6}[cache shared across layers] and the {page_link Site.Blog.DeepSeekV41.Part7}[encoder-decoder split]. With those, the three costs from {page_link Site.Blog.DeepSeekV41.Part1}[part 1] are handled.

Three boxes on the map are still unexplained, and they sit at the edges: Engram on the left, DSpark at the top, and the vision encoder at the bottom. None of them touches the KV cache. They are here because they make the model better or faster at almost no cost to the budget the previous posts fought for. They come from two recent DeepSeek papers and from V4.1 itself.

# Engram: memory as a lookup

A lot of what a language model knows is static. "Eiffel Tower" is followed by "Paris" in every context. Yet a Transformer has to recompute that association with attention and MLPs every time. [Engram](https://arxiv.org/pdf/2601.07372) (Cheng et al., 2026) gives the model a place to store such patterns directly: a huge table of embeddings, addressed by the last few tokens.

The lookup has three steps. First, _tokenizer compression_: token ids are mapped to canonical ids by normalising text (Unicode NFKC, lower case), so that "Paris" and "paris" land in the same place. Second, for each order $`n \in \{2, 3, 4\}` the model forms the suffix n-gram $`g_{t,n}` ending at the current token and hashes it with several independent hash functions into tables of prime size:

$$`z_{t,n,k} = \phi_{n,k}(g_{t,n}), \qquad e_t = \big\Vert_{n}\,\big\Vert_{k}\; E_{n,k}[z_{t,n,k}]`

Several hash heads reduce the damage of collisions: two n-grams are unlikely to collide in all heads. Third, a _gate_ decides how much to trust what came back. The current hidden state, which has already seen the context through attention, plays the role of a query, and the memory the role of a key:

$$`\alpha_t = \sigma\!\left(\frac{\operatorname{RMSNorm}(h_t)^\top \operatorname{RMSNorm}(W_K e_t)}{\sqrt{d}}\right), \qquad h_t \leftarrow h_t + \alpha_t\, W_V e_t`

If the retrieved memory does not fit the context (a hash collision, or a word used in another sense), $`\alpha_t` goes to zero. With the four-stream residual from part 2, Engram shares one value projection across the streams and uses one key projection per stream, so each stream can gate on its own.

:::figframe "static/blog/deepseek-v41/widgets.html#engram" "400"
:::

Type any text in the box. Each word becomes a token (in this toy, one word is one token) and the grey line under it is its canonical form. Hover a token to make it the current position. The three rows show its suffix n-grams of order 2, 3 and 4, and for each the 8 hash indices, one per head: a row number in a table with about 16.7 million rows (the table sizes are distinct primes just below $`2^{24}`). The hash here is a simple multiply-and-xor, like the one the Engram paper describes, but it is not DeepSeek's. The numbers only show the mechanism.

Two things to try. Change "Paris" to "paris": the indices do not move, because the canonical ids are the same. Now change "Eiffel" to "Eifel": every n-gram that contains it gets completely different indices, since a hash has no notion of similar spelling. Then move the *cos* slider, which stands for the agreement between the hidden state and the memory key. At 0.6 the gate is 0.92 and the memory is used. At zero it is one half. Near $`-1` it falls to about 0.02 and the green bar at the bottom empties: the memory is ignored.

In V4.1 there are two Engram modules, at layers 1 and 14, with 196B parameters in total: orders 2 to 4, 8 heads each, about 16 million rows per head, stored in FP8. V4.1 drops the short convolution of the original design, which did not pay for its complexity in their inference stack, and trains the tables with the Sinkhorn-balanced update from part 4. The best detail is on the systems side. The addresses depend only on token ids, not on any hidden state, so they are known before the forward pass starts. The tables can stay in host memory and the rows are prefetched over RDMA while the first layers run. That is how the model carries 196B extra parameters without holding them on the GPU.

# DSpark: drafting and checking

Speculative decoding ([Leviathan et al.](https://arxiv.org/pdf/2211.17192)) makes decoding faster without changing its output. A small drafter guesses several tokens ahead, the big model checks all of them in one pass, and keeps the longest prefix it agrees with. The probability that a draft token survives is exactly $`1 - \tfrac{1}{2}\|p^d - p^t\|_1`, one minus the total variation distance between the draft and target distributions.

V3 and V4 trained [multi-token prediction](https://arxiv.org/pdf/2404.19737) modules with the backbone and could reuse them as drafters. V4.1 drops them and uses [DSpark](https://arxiv.org/pdf/2607.05147), trained after pre-training on the frozen backbone and then kept in sync during post-training without sending gradients back.

DSpark makes two choices. The drafter is _semi-autoregressive_: three Transformer blocks with a 128-token window compute base logits for 5 draft positions in one parallel pass (the backbone comes from [DFlash](https://arxiv.org/pdf/2602.06036)). A purely parallel drafter can produce incoherent mixes, like "of problem" when both "of course" and "no problem" were plausible. So a tiny _Markov head_ adds a bias from the previously drafted token, through a rank-256 factorisation of a vocabulary-by-vocabulary matrix:

$$`p_k(v \mid x_0, x_{<k}) \propto \exp\big(U_k(v) + (W_1[x_{k-1}]\,W_2)(v)\big)`

The second choice is about what to verify. A _confidence head_ predicts, for each draft position, the probability $`c_k` that it survives given that all previous ones did, trained on the exact acceptance rate above. The probability that the first $`j` tokens all survive is $`a_j = \prod_{i \le j} c_i`. Verifying a token costs batch capacity on the big model, and how much that capacity is worth depends on how busy the server is. So a scheduler picks, across all active requests, the set of draft tokens that maximises the expected throughput

$$`\Theta = \tau \cdot \mathrm{SPS}(B)`

where $`\tau` is the expected number of accepted tokens, $`B` the verification batch size and $`\mathrm{SPS}(B)` the engine's steps per second at that batch size, measured once when the engine starts.

:::figframe "static/blog/deepseek-v41/widgets.html#dspark" "450"
:::

Each row on the left is one request: an anchor token (the last verified one) followed by 5 drafted tokens. The number in each cell is its survival probability $`a_j`, which can only decrease along a row, and darker green means more likely to survive. Cells with a black outline are the ones the scheduler sends for verification.

The chart on the right follows the scheduler. It sorts all draft tokens of all requests by survival probability and adds them one by one, and each step moves the curve to the right: a bigger batch, a few more expected tokens, a different engine speed. The green dot marks the best throughput, and the scheduler stops as soon as the curve goes down. (Stopping at the first drop, instead of searching the whole curve, is needed to keep the output distribution exact. The DSpark paper explains why.)

Move the *engine saturation* slider, which sets the batch size where the toy engine stops getting faster. At 128, an idle server, all 40 draft tokens are verified, since extra checks are free. At 8, a server already full with the 8 anchor tokens, not a single draft is verified: every extra token would slow down everyone else. The default, 32, verifies 24 of the 40. *Active requests* changes the number of rows and *new drafts* draws new confidences. The same drafter, with the same drafts, is used very differently depending on load.

# Images in

Last, the bottom of the map. V4.1 reads images, and it is multimodal from the start of pre-training rather than through an adapter added later.

The vision encoder, DeepSeek-ViT, is a [Vision Transformer](https://arxiv.org/pdf/2010.11929) trained from scratch with LLM-style parts: 2D rotary embeddings so it accepts any resolution, RMSNorm, SwiGLU, and a linear patch embedding instead of a convolution, so that Muon from part 4 applies. It was first trained contrastively on about 47 billion image-text pairs with the [SigLIP](https://arxiv.org/pdf/2303.15343) loss, then fine-tuned with next-token prediction attached to a small 4B MoE language model, which was thrown away afterwards.

:::figframe "static/blog/deepseek-v41/widgets.html#vision" "390"
:::

The image on the left is cut into 14-pixel patches (thin grid) and each patch becomes a 1024-dimensional feature. The bold grid groups patches by 3 by 3. Hover the image to move the red square. The right side shows what happens to one group: the nine features are concatenated into one 9216-dimensional vector (pixel-unshuffle), and a two-layer MLP projects it to the model's 5120 dimensions. Nine patches become one token.

Move the *image side* slider. At 1344 pixels, the maximum, the encoder sees 96 by 96 = 9,216 patches and the language model gets 32 by 32 = 1,024 tokens. At 672 pixels it gets 256. The image tokens are placed where the image appears in the text and go through the same layers as text, with their own load-balancing bias in the experts (part 3). Every image costs cache like any other tokens, so reducing them by nine is also a cache decision.

# In perspective

Engram and DSpark have something in common with the rest of the series. Both are about moving work to where it is cheap. Engram moves static knowledge out of GPU compute into a lookup in host memory. DSpark moves decoding work into a small drafter and spends verification only where the numbers say it pays. Neither adds anything to the 890 bytes per token.

That completes the map. The last part puts all the pieces back together, zooming out from one attention layer to the whole model, and asks what V4.1 says about where language models are going.

The [interactive deck](static/blog/deepseek-v41/deck.html#/s-engram) has these three figures.
