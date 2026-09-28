import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "DeepSeek V4.1 piece by piece, part 3: many experts, few at a time" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 10, day := 14 }
draft := true
%%%

:::hero "Expert load with per-modality balancing biases" "static/blog/deepseek-v41/hero-3-moe.png"
:::

This is part 3 of a series on DeepSeek-V4.1-Flash. {page_link Site.Blog.DeepSeekV41.Part1}[Part 1] set the goal (a cheap KV cache for long, input-heavy work) and {page_link Site.Blog.DeepSeekV41.Part2}[part 2] described the residual stream: four parallel copies of each token's state, mixed between blocks by doubly stochastic matrices so that nothing can blow up.

Half of the blocks that read from that stream are attention. The other half are feed-forward blocks, and in V4.1 every one of them is a mixture of experts. They hold almost all the parameters. The model has 552B parameters in its backbone, and about 545B of them are in experts. Yet a token only touches about 16B parameters when it is decoded. This post is about how that works, and how DeepSeek keeps hundreds of experts evenly busy, including when half the input is images.

# One expert

Each expert is a small gated MLP, the [SwiGLU](https://arxiv.org/pdf/2002.05202) block used in most current models:

$$`\operatorname{FFN}(u) = W_2\big(\operatorname{SiLU}(W_1 u) \odot W_3 u\big), \qquad \operatorname{SiLU}(x) = x\,\sigma(x)`

In V4.1 the hidden width is 2304, so each expert has $`3 \times 5120 \times 2304 \approx 35.4`M parameters. Following [gpt-oss](https://arxiv.org/pdf/2508.10925), V4 and V4.1 clamp both branches at 10 before the product. It sounds like a detail, but without it one large activation can overflow the low-precision formats (FP8, FP4) that DeepSeek uses everywhere.

# Many experts, few at a time

[DeepSeekMoE](https://arxiv.org/pdf/2401.06066) made two choices that the later models keep. The experts are small and numerous, so a token can combine several specialised pieces instead of picking one big one. And a few _shared_ experts always run, which frees the routed experts from having to relearn common knowledge. For a token with input $`u_t`:

$$`h'_t = u_t + \sum_{i=1}^{N_s}\operatorname{FFN}^{(s)}_i(u_t) + \sum_{i=1}^{N_r} g_{i,t}\,\operatorname{FFN}^{(r)}_i(u_t)`

The router scores each routed expert with an affinity $`s_{i,t}` computed from the dot product of $`u_t` with a learned vector $`e_i`, keeps the top $`K_r`, and normalises the kept scores into gates $`g_{i,t}`. [DeepSeek-V3](https://arxiv.org/pdf/2412.19437) used a sigmoid for the affinity. V4 switched to $`\sqrt{\operatorname{softplus}(u_t^\top e_i)}`. V4.1 has one shared expert and 384 routed experts per layer, with 6 active, in all 40 layers. V4 used fixed hash routing in its first three layers; V4.1 drops that and uses the standard router everywhere.

:::figframe "static/blog/deepseek-v41/widgets.html#moe" "390"
:::

The buttons at the top pick a token. The grid shows the 384 routed experts of one layer, coloured by affinity (darker is higher), and the six winners are drawn in red. On the right are their gates. They always sum to one, because only the kept scores are normalised. The green box is the shared expert, which runs for every token whatever the router says. Click through the tokens and the red squares jump around. The affinities here are random vectors, so there is no real specialisation to read into them, only the mechanism.

The second toggle switches the affinity function. With these toy scores the gates go from 0.175 to 0.160 under $`\sqrt{\operatorname{softplus}}` and are almost flat (0.169 to 0.165) under the sigmoid. That matches the shapes of the functions. A sigmoid saturates, so two strong matches look alike. The square root of a softplus keeps growing, slowly, so a clearly better expert keeps a larger share. The text on the lower right does the parameter accounting: 13.6B parameters stored per layer, 248M used by a token (six routed experts plus the shared one), and about 545B for the 40 layers.

# Balancing without a loss

A router left alone collapses. A few experts win early, get more gradient, win more, and the rest go idle. Classic mixture-of-experts models add an auxiliary loss that penalises uneven load, as in the [Switch Transformer](https://arxiv.org/pdf/2101.03961). The trouble is that this loss pulls on the same weights as the language modelling loss, so balance is bought with quality.

DeepSeek's [auxiliary-loss-free balancing](https://arxiv.org/pdf/2408.15664) does something simpler. Each expert gets a bias $`b_i`. The bias is added to the affinity only to decide _which_ experts are selected, never to compute the gate:

$$`g'_{i,t} = \begin{cases} s_{i,t} & \text{if } s_{i,t} + b_i \in \operatorname{Topk}(\{s_{j,t} + b_j\}, K_r) \\ 0 & \text{otherwise} \end{cases}`

After each training step, the bias of an overloaded expert goes down by a fixed amount $`\gamma` and the bias of an underloaded one goes up. It is a controller, not a gradient, so it has no effect on what the experts learn. A tiny per-sequence balance loss remains as a guard against extreme cases (weight $`10^{-4}` in V4.1).

V4.1 adds one thing, because it is multimodal. Image tokens and text tokens do not prefer the same experts. A single bias vector balances the _total_ load, which can hide the fact that the image tokens all pile onto a few experts while text tokens fill the rest. So V4.1 keeps two bias vectors, one per modality, each updated from its own modality's load, with $`\gamma = 0.001`.

:::figframe "static/blog/deepseek-v41/widgets.html#balance" "430"
:::

This one is a small simulation that runs by itself: 16 experts, two chosen per token, 400 tokens per step, 30% of them images. In this toy world text prefers the first six experts and images the last six. The stacked bars on the left are the load per expert (grey for text, blue for images), with the dashed line at the ideal mean. Under them are the two bias vectors. The chart on the right plots, for each step, the load of the busiest expert divided by the mean: 1 is perfect, and the curves are shown for text only, images only, and all tokens.

Click *no balancing*. After a few seconds the busiest expert carries more than three times its share, for both modalities. Now click *bias (shared)*, which is the V3 and V4 scheme. The red "all tokens" curve comes down to about 1.4, and if you only watched that number you would call it solved. But the blue image curve stays near 3.5. The shared bias has made the _sum_ even by pushing text onto the experts images do not use, while images are still crowded on a few. Click *bias per modality (V4.1)*: both curves come down, to about 1.4 for text and 1.7 for images in my runs. The *γ* slider sets how fast the biases move. Push it up and the curves settle faster but stay noisier. *Reset* restarts from zero biases.

# In perspective

Part 2 and this post share an idea. In both cases DeepSeek controls a learned system with a side variable that does not fight the main objective. mHC projects the mixing matrix onto a safe set instead of penalising bad matrices. Balancing moves a routing bias instead of adding a loss. The model learns what it wants, and the constraint is enforced by construction.

None of this touches the KV cache yet. The experts matter for the cache story in a different way: they make the model large without making each token expensive, so the budget saved on attention in parts 5 to 7 is not eaten by the rest of the layer. Before getting there, one more question: how do you train 545B parameters of experts at all? Part 4 is about the optimizers.

The matching slides of the [interactive deck](static/blog/deepseek-v41/deck.html#/s-moe) include the full sequence-wise balance loss.
