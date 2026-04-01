import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Reading Note: Mamba-3 and the State Space Model Renaissance" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 03, day := 29 }
%%%

A reading note on [Mamba-3: Improved Sequence Modeling using State Space Principles](https://arxiv.org/abs/2603.15569) by Aakash Lahoti, Kevin Y. Li, Berlin Chen, Caitlin Wang, Aviv Bick, J. Zico Kolter, Tri Dao, and Albert Gu (ICLR 2026).

# The context

Transformers dominate language modeling, but their quadratic attention cost and linearly growing KV cache make inference expensive, especially in the agentic era, where test-time compute is becoming a first-class concern. State space models (SSMs) and their cousins (linear attention, gated linear recurrences) promise sub-quadratic alternatives with constant memory and linear compute at decode time. Mamba-2 formalized the connection between SSMs and attention through the _Structured State Space Duality_ (SSD) framework, showing that the recurrent and matrix-multiplication views of these models are two faces of the same coin.

Yet despite their theoretical appeal, linear models still lag behind Transformers on quality. They struggle with state tracking, retrieval, and raw language modeling perplexity. Mamba-3 attacks these gaps head-on, not by bolting on attention layers, but by going deeper into the SSM formalism itself.

# Three ideas from one viewpoint

The paper's methodological core is a commitment to the _state space model viewpoint_ as a source of architectural improvements. All three contributions arise naturally from SSM principles but would be unnatural or opaque from the perspective of linear attention or test-time training. This is itself an interesting meta-point: the framework you think in determines the improvements you find.

## Exponential-trapezoidal discretization

The continuous SSM is defined by the ODE $`\dot{h}(t) = A(t) h(t) + B(t) x(t)`, which must be _discretized_ to get a usable recurrence. Mamba-1 and Mamba-2 used a heuristic approximation that the authors now formalize as "exponential-Euler", an exponential integrator combined with Euler's rule for the state-input integral. The key insight is that Euler's rule is only first-order accurate. Replacing it with a _trapezoidal rule_, a data-dependent convex combination of both interval endpoints, yielding a second-order method:

$$`h_t = e^{\Delta_t A_t} h_{t-1} + (1 - \lambda_t) \Delta_t e^{\Delta_t A_t} B_{t-1} x_{t-1} + \lambda_t \Delta_t B_t x_t`

where $`\lambda_t \in [0, 1]` is a learned parameter. Setting $`\lambda_t = 1` recovers Mamba-2's exponential-Euler; setting $`\lambda_t = 1/2` gives the classical trapezoid rule. The beauty is that this three-term recurrence can be rewritten as a width-2 convolution on the state-input _within_ the core recurrence, replacing the external short convolution that was previously thought essential to Mamba's performance.

This is an elegant simplification: by improving the discretization, a separate architectural component (the short causal convolution) becomes redundant.

## Complex-valued state transitions

A well-known limitation of current linear models is their inability to perform _state tracking_ (tasks like computing parity, where the model must maintain a discrete counter modulo some number). The root cause, formalized by Grazzi et al. and Sarrof et al., is that real-valued diagonal state transitions cannot represent rotational dynamics. Computing $`\sum_t x_t \bmod 2` on binary inputs requires a 2D rotation matrix, which has complex eigenvalues.

Mamba-3 reintroduces complex-valued state transitions, a feature of early SSMs like S4 that was dropped in Mamba-1/2 because complex values seemed unhelpful for language modeling. The key contribution is showing that a complex SSM with exponential-Euler discretization is equivalent to a real-valued SSM with _data-dependent rotary embeddings_ (RoPE) applied to the B and C projections. This is a beautiful connection: vanilla RoPE uses fixed, data-independent rotation frequencies; Mamba-3's complex state transitions yield data-dependent rotations that the model learns to use for state tracking.

The practical result is striking: Mamba-3 solves parity and modular arithmetic tasks that Mamba-2 (and Mamba-3 without RoPE) cannot do at all.

## Multi-Input, Multi-Output (MIMO)

The third idea targets inference hardware efficiency. SSM decoding is _memory-bound_: the arithmetic intensity of the state update is only about 2.5 ops per byte, far below the 295 ops/byte that an H100 matmul can sustain. The compute cores sit mostly idle.

The fix is to switch from a single-input, single-output (SISO) recurrence (where each head processes one scalar input) to a multi-input, multi-output (MIMO) formulation where B and C become matrices instead of vectors. This replaces the outer product $`B_t x_t^\top` with a matrix multiplication $`B_t x_t^\top` where $`x_t \in \mathbb{R}^{P \times R}`, increasing FLOPs by a factor of R without proportionally increasing memory traffic. The state update becomes a matmul, which tensor cores can execute efficiently.

The result: MIMO increases decoding FLOPs by up to 4x relative to Mamba-2 at fixed state size, while maintaining _similar wall-clock decode latency_. You get a better model for the same inference cost.

# Results

The experimental validation is thorough. All models are trained on 100B tokens of FineWeb-Edu with a standard protocol, which makes comparisons clean.

*Language modeling.* At the 1.5B scale, Mamba-3 SISO outperforms Transformers, Mamba-2, and Gated DeltaNet (GDN) on average downstream accuracy. The MIMO variant adds another 1.2 points, for a total gain of 1.8 over Mamba-3 SISO. Notably, Mamba-3 achieves _the same perplexity as Mamba-2 with half the state size_, a direct advance of the performance-efficiency Pareto frontier.

*State tracking.* Mamba-3 perfectly solves parity and modular arithmetic (without brackets), and nearly solves modular arithmetic with brackets. Mamba-2 scores below 1% on all three. This is a qualitative capability gain, not just a quantitative one.

*Retrieval.* Linear models fundamentally struggle here because they must compress all context into a fixed-size state, while Transformers can freely revisit the KV cache. Mamba-3 is competitive on associative recall and question-answering tasks but weaker on information extraction from semi-structured data. In hybrid configurations (5:1 ratio of Mamba-3 to attention layers), retrieval performance recovers and even exceeds the pure Transformer baseline on some tasks.

*Inference speed.* Custom Triton and CuTe DSL kernels for Mamba-3 achieve the lowest per-token decode latency among all baselines, including Mamba-2 and GDN. MIMO adds minimal overhead. At 16K tokens, Mamba-3's prefill+decode latency is 140s vs 976s for a Transformer (vLLM with Llama-3.2-1B).

# Why this matters

## The SSM viewpoint pays off

The paper makes a convincing case that thinking in terms of continuous dynamics, discretization, and signal processing leads to improvements that are not obvious from other angles. Exponential-trapezoidal discretization is a natural step for anyone trained in numerical ODEs but has no clear analogue in the linear attention or test-time training frameworks. Similarly, MIMO is a classical concept in signal processing but was absent from modern sequence models. The message is clear: the SSM lens is not just a mathematical curiosity: it is a productive source of architectural ideas.

## The state-tracking gap narrows

The demonstration that complex-valued SSMs solve state-tracking tasks that were thought to be beyond linear models is significant. This has been a persistent theoretical objection to SSMs: if they cannot even compute parity, how can they handle the implicit state tracking required by real language? Mamba-3 does not fully close this gap: the state-tracking improvements are shown on synthetic tasks, and it remains unclear how much they help on natural language, but it removes a categorical limitation.

## Inference efficiency as a design principle

Most sequence models are designed training-first: optimize the parallel computation, then worry about inference later. Mamba-3 inverts this. The MIMO formulation is explicitly motivated by making decode _hardware-efficient_, and the paper shows that you can increase model quality while keeping inference latency flat. In a world of agentic workflows and chain-of-thought reasoning where inference cost dominates, this is the right design orientation.

## What is left open

The retrieval gap between pure SSMs and Transformers remains real. Hybrid architectures help, but the paper is refreshingly honest that "their exact characteristics and dynamics are complex and oftentimes unintuitive." Understanding when and why to interleave attention with linear layers is still an open problem, and perhaps the most important one for practical deployment of efficient models.

Overall, Mamba-3 is a strong iteration on the state space model family. It does not claim to replace Transformers; it claims to advance the Pareto frontier between quality and inference efficiency. The evidence supports this claim convincingly, and the principled methodology suggests there is more to extract from the SSM viewpoint.
