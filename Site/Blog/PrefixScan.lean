import VersoBlog

open Verso Genre Blog

#doc (Post) "Reading Note: Sequential-Parallel Duality in Prefix Scannable Models" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 03, day := 13 }
%%%

A reading note on [Sequential-Parallel Duality in Prefix Scannable Models](https://arxiv.org/abs/2506.10918) by Morris Yau, Sharut Gupta, Valerie Engelmayer, Kazuki Irie, Stefanie Jegelka, and Jacob Andreas (ICLR 2026).

# The problem

Transformers are good at training (parallelizable over the sequence dimension) but expensive at inference (each new token attends to all previous tokens, so cost and memory grow linearly with context). Recurrent models are the opposite: fast at inference (constant state, constant cost per token) but sequential at training. A growing family of architectures — Mamba, GLA, RetNet, mLSTM, and others — claim to offer the best of both worlds. But each one comes with its own formalism, its own state update rule, and its own efficiency analysis.

The paper asks a clean question: *what is the full class of sequence models that admit both near-constant-depth parallel training and linear-time, constant-space sequential inference?* They call this property *Sequential-Parallel Duality (SPD)*.

# The answer: prefix scans

The core observation is that all these models can be expressed as instances of the *Blelloch prefix scan* — a classical parallel algorithm that computes all prefixes of a sequence under a binary operator in $`O(n)` work and $`O(\log n)` depth. The algorithm works in two phases: an *upsweep* that reduces adjacent pairs bottom-up in a binary tree, and a *downsweep* that propagates prefix values top-down.

When the binary operator is *associative*, the parallel scan produces exactly the same result as a left-to-right sequential fold. This is the case for the entire family of modern "linear RNNs": Linear Attention, DeltaNet, RetNet, mLSTM, S4/S6, Mamba, GLA, and others. The paper shows that all of these fit a single *affine state recurrence* template:

$$`s_t = E_t \blacktriangleright s_{t-1} + f_t`

where $`E_t` and $`f_t` are learned functions of the input, and $`\blacktriangleright` is a group action. Each architecture is just a different choice of gating operator. The associated aggregator $`(E_2, f_2) \oplus (E_1, f_1) = (E_2 \circ E_1,\; f_2 + E_2 \blacktriangleright f_1)` is associative, so the Blelloch scan applies directly. This gives SPD-$`(n, 1)`: parallel training in $`O(n)` work, sequential inference with $`O(1)` memory per token.

The unification is satisfying: a table in the paper lays out ten architectures side by side, and the differences reduce to whether the gate is a scalar, a diagonal matrix, or a projector.

# The generalization: non-associative aggregation

The more surprising contribution is extending the framework to *non-associative* operators — in particular, *softmax attention*. When the aggregator is not associative, different parenthesizations of $`x_0 \operatorname{Agg} x_1 \operatorname{Agg} \cdots \operatorname{Agg} x_{t-1}` produce different results. The Blelloch tree fixes a specific parenthesization, and the paper proves that the online streaming version (Algorithm 2, a binary counter that maintains at most $`\lceil \log_2(t+1) \rceil` roots) reproduces exactly the same parenthesization as the static scan.

This yields what they call *Prefix-Scannable Models (PSMs)*: the class SPD-$`(n, \log n)`, with $`O(1)` amortized compute per token and $`O(\log n)` memory. The memory bound is worse than the $`O(1)` of pure RNNs, but the expressiveness can be strictly greater — because the aggregator is no longer constrained to be associative.

# Transformer-PSM

To validate the theory, the authors instantiate a concrete PSM called *Transformer-PSM*. It chunks the input into blocks of size $`c`, uses a bidirectional GPT-2 transformer as the aggregator (to merge two chunk summaries), and a causal GPT-2 transformer as the inference module (to predict tokens within a chunk given the prefix state). The aggregator is softmax attention — non-associative — so this falls in the PSM class rather than the affine-scan class.

The results are striking:

- *State tracking* ($`S_5` task): Transformer-PSM generalizes to sequences 9x longer than training length, far beyond both GPT-2 and Mamba.
- *Associative recall* (MQAR): With chunk size 64, Transformer-PSM matches the full-context transformer perfectly, while Mamba fails.
- *Language modeling* (WikiText-103): Perplexity approaches vanilla GPT-2 (22.45 vs 22.28) as chunk size grows to 256, while maintaining linear-time inference.
- *Inference speed*: GPT-2's per-token latency grows from 0.002s to 0.04s over 40,000 tokens. Transformer-PSM stays flat at around 0.008s.

# Why this matters

The paper provides a clean theoretical framework where previously we had a zoo of competing architectures. The key insights:

1. *Unification*: The entire family of efficient sequence models — from Linear Attention to Mamba — are instances of one construction: prefix scan with an associative affine aggregator.

2. *Generalization*: Relaxing associativity to allow softmax attention yields a strictly larger class (PSMs) that retains $`O(1)` amortized inference with only a logarithmic memory cost.

3. *A design space, not a single model*: The framework separates three modular components — Encoder, Aggregator, Inference module — that can be mixed independently. This turns architecture search into a more structured problem.

4. *The chunk size as a continuous knob*: Varying the chunk size $`c` smoothly interpolates between SSM-like behavior (small chunks, more recurrence) and Transformer-like behavior (large chunks, more attention). This is a cleaner framing than the usual "RNN vs Transformer" dichotomy.

The limitation is clear: the $`O(\log n)` memory bound means the model cannot maintain a truly constant-size state. Whether this matters in practice depends on the application — for most realistic sequence lengths, $`\log n` is small enough to be negligible. The more pressing open question is whether the Blelloch parenthesization (dictated by the binary tree structure) is the *right* parenthesization for natural language, or whether other tree shapes could improve expressiveness.
