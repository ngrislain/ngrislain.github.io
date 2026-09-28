import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 2: a wider residual stream" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 10, day := 07 }
draft := true
%%%

:::hero "Sinkhorn iterations and the gain of sixty stacked mixing matrices" "static/blog/deepseek-v41/hero-2-mhc.png"
:::

This is part 2 of a series on DeepSeek-V4.1-Flash. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] argued that for long-context agents the KV cache, not compute, is the real cost, and showed a map of the whole model.

It would be natural to start with attention, since that is where the cache lives. I start one level below instead, with the residual stream, because every other component in the map reads from it and writes into it. It is also where V4 made its least visible change, and where V4.1 made a change that only makes sense once you think about memory traffic. That theme comes back in every part of the series.

# The plain residual

In a standard pre-norm Transformer, each block reads the stream, computes something, and adds it back:

$$`x_{l+1} = x_l + \mathcal{F}_l(\operatorname{RMSNorm}(x_l))`

Unroll it and the last layer sees the embedding plus the sum of every block's contribution. The derivative of the output with respect to an early layer contains an identity term, which is why very deep networks train at all. [He et al.](https://arxiv.org/pdf/1603.05027) called this the identity mapping. In V4.1 there are 80 such blocks: an attention block and an MoE block in each of the 40 layers.

# Hyper-connections

[Hyper-connections](https://arxiv.org/pdf/2409.19606) (Zhu et al., 2024) replace the single stream by $`n` parallel streams, stacked into a matrix $`X_l \in \mathbb{R}^{n \times d}`. Three small learned maps then decide how a block reads, writes and shuffles:

$$`X_{l+1} = B_l X_l + C_l \, \mathcal{F}_l(A_l X_l)`

$`A_l` is a row of $`n` weights that mixes the streams into the one $`d`-dimensional input the block expects. $`C_l` is a column of $`n` weights that writes the block's output back into each stream. $`B_l` is an $`n \times n` matrix that mixes the streams with each other. The block itself does not change, and since $`n = 4` is tiny next to $`d = 5120`, the extra cost is small. The coefficients are not fixed: a small projection computes them for every token from the streams themselves.

:::figframe "static/blog/deepseek-v41/widgets.html#hc" "400"
:::

The figure shows one token going through one block, left to right. The first heatmap is $`X_l`, four streams of eight dimensions (blue is negative, red positive). Next to it, the row $`A_l` and the mixed input $`\hat{x} = A_l X_l`, then the block $`\mathcal{F}_l`, drawn as a yellow box, and its output. Further right come $`B_l`, the column $`C_l`, and the new state $`X_{l+1}`. The panel below lists properties of $`B_l`.

Click *HC (unconstrained)* and then *new token* a few times, to draw new coefficients. You will see negative entries in $`B_l` and a spectral norm $`\|B_l\|_2` that is usually between 2 and 4, printed in red. A matrix with norm 3 can triple a signal. One block doing that is harmless. Eighty blocks in a row, each allowed to do it in its own direction, is how you get loss spikes. The [mHC paper](https://arxiv.org/pdf/2512.24880) reports that unconstrained hyper-connections cause training instability and limit how far they scale.

# Manifold-constrained hyper-connections

The mHC fix is to force $`B_l` to be _doubly stochastic_: non-negative, with every row and every column summing to one.

$$`B_l \in \mathcal{M} = \{ M \ge 0,\; M\mathbf{1} = \mathbf{1},\; \mathbf{1}^\top M = \mathbf{1}^\top \}`

Three things follow. The spectral norm of such a matrix is at most one, so no block can amplify the stream. The product of doubly stochastic matrices is again doubly stochastic, so the guarantee holds for the whole stack, not only for each block. And the set is the convex hull of permutation matrices, so $`B_l` is literally a soft reshuffling of the streams. With $`n = 1` it reduces to the plain residual.

To land in that set, mHC takes the raw matrix $`\tilde{B}_l`, exponentiates it to make it positive, and runs the Sinkhorn-Knopp algorithm: alternately normalise the columns and the rows.

$$`M^{(0)} = \exp(\tilde{B}_l), \qquad M^{(t)} = \mathcal{T}_r(\mathcal{T}_c(M^{(t-1)})), \qquad B_l = M^{(20)}`

The input and output maps get a softer treatment: $`A_l = \sigma(\tilde{A}_l)` and $`C_l = 2\sigma(\tilde{C}_l)`, positive and bounded, so streams cannot cancel each other.

:::figframe "static/blog/deepseek-v41/widgets.html#sinkhorn" "440"
:::

The left part shows the Sinkhorn iterations on one random $`4 \times 4` matrix. The bars on the right of the grid are the row sums, the bars below it the column sums. They turn green when they reach one. Move the *Sinkhorn iterations* slider from 0 to 20. At zero the row sums are somewhere between 5 and 15. After a single iteration the rows are exact, since the row step comes last, while the columns are still off. A few more iterations and both sides settle. DeepSeek uses 20, which is plenty for a $`4 \times 4` matrix.

The right chart is the reason for all this. It multiplies 60 random mixing matrices, as if they were 60 consecutive blocks, and plots the largest total gain of the product (the maximum over rows of the sum of absolute values) on a log scale. The red line uses unconstrained matrices, the green line projected ones. At the default noise level the red line ends near 200 while the green line stays at exactly 1.000. Lower the *noise* slider to 0.1: the red product still drifts to about 3, because small excesses compound. *Resample* draws new matrices. The shape changes, the conclusion does not. The green line cannot move by construction.

V4 adopted mHC with $`n = 4` streams and 20 Sinkhorn iterations. The coefficients come from an RMS-normalised copy of all four streams flattened together, times three small projection matrices, plus static biases and small learned gates. The [V4 paper](https://arxiv.org/pdf/2606.19348) describes it in section 2.2.

# Single-pass mHC

That is V4. V4.1 changes one index.

Each mHC block in V4 runs as three dependent steps. First, update the streams with the previous block's output. Second, compute the coefficients of this block, which needs a reduction over all $`nd` values of the new streams. Third, mix the streams into this block's input with the coefficient $`A_l` just computed. The third step cannot start until the second is fully finished, so the streams are read from memory twice. Counting the pre-norm, the activation traffic is $`(4n+4)d` values per token, twice the minimum.

V4.1 feeds each block with the _previous_ block's input weights:

$$`X_{l+1} = B_l X_l + C_l \, \mathcal{F}_l(A_{l-1} X_l), \qquad (A_l, B_l, C_l) = \mathcal{H}(X_l)`

Now the mixing does not wait for the reduction. A single kernel, which the paper calls Mega-mHC, streams through $`X_l` tile by tile: update the tile, mix it into the block input, accumulate what the next block needs for its coefficients. Each value is read once and written once.

:::figframe "static/blog/deepseek-v41/widgets.html#singlepass" "390"
:::

The bars at the top count reads plus writes per token, in units of $`d`. Move the *streams* slider: V4's multi-pass version costs $`(4n+4)d`, a fused two-pass version $`(3n+2)d`, and single-pass $`(2n+2)d`, the lower bound for any map from (old streams, block output) to (new streams, next input). At $`n = 4` that is 20 against 10. The two timelines below show why. In V4, the box that mixes the input has to wait for the red arrow, the full reduction that produces $`A_l`. In V4.1 the tiles go through one after another and the coefficients for the next block fall out at the end.

The paper says the shift causes "negligible performance degradation". It gives no ablation table for it, which is a pattern in this paper. What I like about the change is its honesty about priorities. The math of mHC is untouched except for one index, chosen only because it lets the kernel read the stream once. Memory traffic, not FLOPs, decided the equation.

# Where this leaves us

After this post the stream is in place: four copies of a 5120-dimensional vector per token, mixed by doubly stochastic matrices between blocks. Everything else in the model is a block that reads from it through $`A` and writes to it through $`C`. The next post looks at the blocks that hold almost all the parameters, the experts.

The same slides are in the [interactive deck](static/blog/deepseek-v41/deck.html#/s-hc), with a slide on the coefficient parameterisation that I skipped here.
