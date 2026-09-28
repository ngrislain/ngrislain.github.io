import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 4: two optimizers, one idea" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 10, day := 21 }
draft := true
%%%

:::hero "Newton-Schulz iterations pushing singular values to one" "static/blog/deepseek-v41/hero-4-optimizers.png"
:::

This is part 4 of a series on DeepSeek-V4.1-Flash. So far: {page_link Site.Blog.DeepSeekV41.Part1}[part 1] framed the model around the cost of the KV cache, {page_link Site.Blog.DeepSeekV41.Part2}[part 2] covered the four-stream residual and its doubly stochastic mixing, and {page_link Site.Blog.DeepSeekV41.Part3}[part 3] the 384 experts per layer and how their load is balanced.

Those posts described the forward pass. This one is about training, and it is the last detour before attention. It matters for two reasons. The optimizer is part of the architecture: a model with 545B parameters of experts and 196B parameters of lookup tables is only practical if the optimizer state fits. And the Sinkhorn algorithm from part 2 comes back here in a completely different role.

V4.1 uses three optimizers, split by the shape of the parameter. Muon for the weight matrices of linear layers. A new Sinkhorn-balanced update for the big tables indexed by token: the input embedding, the prediction head and the Engram tables. AdamW for everything that is not a matrix, such as normalisation weights, biases and gates.

# Muon

Adam scales each coordinate of the update by its own running statistics. [Muon](https://kellerjordan.github.io/posts/muon/) (Keller Jordan, 2024) treats a weight matrix as a matrix. It takes the momentum $`M`, with singular value decomposition $`M = U\Sigma V^\top`, and replaces it by $`UV^\top`: same directions, but every singular value set to one. No direction of the update is allowed to dominate just because its gradient happened to be large.

An exact SVD is too slow, so Muon uses a Newton-Schulz iteration, an odd polynomial applied to the matrix:

$$`M_k = aM_{k-1} + b\,(M_{k-1}M_{k-1}^\top)M_{k-1} + c\,(M_{k-1}M_{k-1}^\top)^2M_{k-1}`

Because only odd powers of $`M` appear, the singular vectors are untouched and each singular value goes through the scalar map $`\sigma \mapsto a\sigma + b\sigma^3 + c\sigma^5`. Repeat that map and all values end up near one. [Moonlight](https://arxiv.org/pdf/2502.16982) showed it scales to large language models with weight decay and an update rescaled to match Adam's size. [DeepSeek-V4](https://arxiv.org/pdf/2606.19348) adopted it with a hybrid schedule: eight iterations with aggressive coefficients $`(3.4445, -4.7750, 2.0315)`, then two with $`(2, -1.5, 0.5)`.

:::figframe "static/blog/deepseek-v41/widgets.html#muon" "420"
:::

The left chart plots the two scalar maps. The blue curve (steps 1 to 8) rises very steeply near zero, overshoots above one and dips back. The red curve (steps 9 and 10) is gentle and has a flat, stable point at exactly one. The right chart shows 28 singular values, spread on a log scale from 0.001 to 1, after the number of iterations chosen by the slider.

Move the *NS iteration* slider one step at a time. At $`k = 2` the largest values already overshoot to about 1.2 while the smallest are still around 0.01. By $`k = 6` everything sits between 0.68 and 1.2, scattered around one. This is the aggressive map doing its job, fast but not precise. Steps 7 and 8 do not tighten it much. Then the two final steps with the gentle map collapse the whole range to $`[0.978, 1.018]` and finally to exactly one. Fast then accurate: that is the whole reason for the hybrid.

The update applied to the weights is then

$$`W_t = W_{t-1}(1 - \eta\lambda) - \eta\,\gamma\sqrt{\max(n, m)}\;\operatorname{NS}_{10}(\mu M_t + G_t)`

where the $`\sqrt{\max(n,m)}` and $`\gamma = 0.18` factors bring the update back to the size an AdamW update would have, so the learning rate schedule can be reused.

# Head-wise Muon

V4.1 makes one change: for the query and key projections, it splits the weight matrix by attention head and orthogonalises each head's block separately.

The paper's argument is short. Viewed as preconditioned gradient descent, plain Muon uses one preconditioner for the whole matrix, so all 64 heads share it. But heads are not alike: some attend locally, some globally, some almost never fire. [Zhang et al.](https://arxiv.org/pdf/2402.16788) documented this kind of block heterogeneity in the Hessian of Transformers, and a [recent paper on optimizer principles](https://arxiv.org/pdf/2608.16760) develops the argument. Giving each head its own preconditioner lets the update adapt to each. DeepSeek reports that head-wise Muon beats plain Muon, and notes that [Kimi K3](https://arxiv.org/pdf/2607.24653) and GLM 5 found the same.

In the figure, the toggle at the top right switches the purple bar under the chart. *Vanilla Muon* draws the query up-projection $`W^{UQ}` (1280 by 64 heads of 512) as one block. *Head-wise Muon* cuts it into per-head blocks (16 of the 64 are drawn), each orthogonalised on its own. Nothing else changes in the figure, because nothing else changes in the algorithm.

# Sinkhorn-balanced updates for tables

Some parameters are not linear maps in the usual sense. The embedding table and the prediction head are matrices with one row per token of the vocabulary (about 128K rows, 5120 columns). Engram, which part 8 covers, adds 196B parameters of tables whose rows are hashed n-grams. Their gradients have a very particular shape: a frequent token gets a large gradient in its row every step, a rare token gets nothing for thousands of steps.

AdamW handles this, but it keeps two state buffers per parameter, which is a lot on 196B parameters. Muon keeps one buffer, but orthogonalising a matrix with 128K rows is expensive and ignores the row structure. V4.1 keeps Muon's recipe and replaces Newton-Schulz with Sinkhorn normalisation, the same alternating row and column scaling that mHC uses on its mixing matrices:

$$`\Delta_t = \sqrt{n}\,D_r\,\widehat{G}_t\,D_c, \qquad \tfrac{1}{n}\textstyle\sum_j (\Delta_t)_{ij}^2 \approx 1, \qquad \tfrac{1}{m}\textstyle\sum_i (\Delta_t)_{ij}^2 \approx 1`

$`\widehat{G}_t` is the Nesterov momentum. The diagonal scalings $`D_r` and $`D_c` are what the alternating normalisation converges to: every row (token) and every column (feature) of the update ends up with the same root mean square. Rows whose gradient norm is below $`10^{-3}` times the average are set to zero first, so a token that barely appeared is not blown up to full size.

:::figframe "static/blog/deepseek-v41/widgets.html#sinkgd" "380"
:::

The heatmap is a toy momentum matrix with 14 token rows and 10 feature columns. The rows follow a Zipf-like pattern: "tok 1" is frequent and its gradient is large, later rows are smaller, and the row labelled "rare" has an almost zero gradient. The blue bars on the right give each row's RMS and the red bars under the grid each column's RMS.

At $`k = 0` the row RMS goes from 2.65 down to 0.16. Step the slider. Odd steps normalise the rows, and the blue bars snap to one. Even steps normalise the columns, which disturbs the rows a little. As $`k` grows the disturbance shrinks, so both sides settle. The number of steps is odd ($`K = 11` in V4.1), so the last step is a row step and every row ends at exactly one. The "rare" row stays at zero the whole time: that is the mask.

The paper reports that this update beats Adam on these parameters while keeping a single momentum buffer. It is closely related to [SinkGD](https://arxiv.org/pdf/2502.06742), which applied the same normalisation to ordinary weight matrices, and to older ideas like [Adafactor](https://arxiv.org/pdf/1804.04235) and [Adam-mini](https://arxiv.org/pdf/2406.16793) that also use row and column structure.

# In perspective

Put the three optimizers side by side and a single idea shows. Adam normalises the update per coordinate. Muon normalises its spectrum. The Sinkhorn update normalises its rows and columns. Each fixes the scale of the update along the axes that mean something for that parameter: arbitrary directions for a generic linear map, heads for attention projections, tokens and features for a table. The choice follows the shape of the parameter.

It is also the second time Sinkhorn shows up. In part 2 it made a mixing matrix doubly stochastic so the forward pass stays stable. Here it balances an update so that no token or feature dominates. Different jobs, same algorithm.

That closes the part of the model that is not attention. The next two posts are about the KV cache itself, starting with the attention design V4.1 inherits from V4. The [interactive deck](static/blog/deepseek-v41/deck.html#/s-muon) has the same figures full screen.
