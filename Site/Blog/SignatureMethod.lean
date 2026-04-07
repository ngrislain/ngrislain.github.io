import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Reading Note: The Signature Method in Machine Learning" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 04, day := 06 }
%%%

A reading note on [A Primer on the Signature Method in Machine Learning](https://arxiv.org/abs/1603.03788) by Ilya Chevyrev and Andrey Kormilitzin.

I have been working on modeling long sequences of events and looking for techniques to build compact and expressive features from such sequences. The signature method caught my attention as a principled mathematical framework that does exactly this: it takes a path (any sequential data embedded in a vector space) and produces a collection of numbers that captures its essential geometric and analytic properties. The theory goes back to K. T. Chen in the 1950s, but it has found new life in machine learning over the past two decades, mostly through the work of Terry Lyons and collaborators in the rough path theory community.

# What is a path?

A path is simply a continuous function from an interval to a vector space: $`X : [a,b] \to \mathbb{R}^d`. This is a natural way to represent many kinds of data:

- A financial time series is a path in $`\mathbb{R}^d` where each coordinate tracks a stock price or index.
- Handwriting is a path in $`\mathbb{R}^2` tracing pen position over time.
- Text can be viewed as a path through an embedding space.
- A sequence of user events (clicks, purchases, page views) can be embedded as a path by associating each event type with a direction in $`\mathbb{R}^d`.

In practice, data comes as discrete points $`X_{t_0}, X_{t_1}, \ldots, X_{t_N}` and we connect them into a continuous path by linear interpolation. This gives a piecewise linear path, which turns out to be the most natural setting for computation.

# The signature of a path

The signature of a path $`X` is the collection of all its _iterated integrals_. For a single index $`i \in \{1, \ldots, d\}`, the first-level term is just the increment:

$$`S(X)^i_{a,b} = \int_{a < t < b} dX^i_t = X^i_b - X^i_a.`

For a pair of indices $`i, j`, the second-level term is a double iterated integral:

$$`S(X)^{i,j}_{a,b} = \int_{a < s < t < b} dX^i_s \, dX^j_t.`

More generally, for any multi-index $`(i_1, \ldots, i_k)` with $`i_j \in \{1, \ldots, d\}`, the $`k`-fold iterated integral is:

$$`S(X)^{i_1, \ldots, i_k}_{a,b} = \int_{a < t_1 < \cdots < t_k < b} dX^{i_1}_{t_1} \cdots dX^{i_k}_{t_k}.`

The *signature* $`S(X)_{a,b}` is the full infinite collection of all these numbers (together with a zeroth term equal to 1 by convention).

In practice, we truncate at some level $`N`. The _truncated signature_ at level $`N` keeps all terms $`S(X)^{i_1, \ldots, i_k}` for $`k \leq N`. In dimension $`d`, the number of terms at level $`k` is $`d^k`, so the truncated signature up to level $`N` has $`\sum_{k=0}^{N} d^k` components. For $`d = 2` and $`N = 3`, that is $`1 + 2 + 4 + 8 = 15` numbers.

## What do the levels mean?

- *Level 1* captures the total displacement of the path along each coordinate. Two paths with the same level-1 signature end at the same point (relative to start).
- *Level 2* captures pairwise correlations between coordinates and, most importantly, the _signed area_ enclosed by the path. The Levy area $`A = \frac{1}{2}(S^{1,2} - S^{2,1})` measures the area enclosed between the path and the chord connecting its endpoints, with sign depending on orientation. This is the key geometric quantity that distinguishes clockwise from counterclockwise loops.
- *Level 3 and beyond* capture increasingly fine-grained shape information: how the areas themselves evolve, and so on.

# Key properties

The signature has four properties that make it well-suited as a feature map:

## Reparametrization invariance

The signature of a path depends only on its image (the shape of the curve), not on the speed at which it is traversed. Formally, if $`\psi : [a,b] \to [a,b]` is a continuous non-decreasing surjection, then $`S(X \circ \psi) = S(X)`. This means the signature automatically ignores irrelevant timing variations and focuses on the geometry of the data.

## Chen's identity

If you concatenate two paths $`X : [a,b] \to \mathbb{R}^d` and $`Y : [b,c] \to \mathbb{R}^d`, the signature of the concatenation is the tensor product of the individual signatures:

$$`S(X * Y)_{a,c} = S(X)_{a,b} \otimes S(Y)_{b,c}`

where the tensor product is defined component-wise as:

$$`(A \otimes B)^{i_1, \ldots, i_k} = \sum_{m=0}^{k} A^{i_1, \ldots, i_m} \cdot B^{i_{m+1}, \ldots, i_k}.`

Chen's identity is essential for computation: it lets you build the signature of a long path by composing the signatures of its pieces.

## Shuffle product

The product of two signature terms can be expressed as a linear combination of higher-order terms:

$$`S(X)^I \cdot S(X)^J = \sum_{K \in I \sqcup\sqcup J} S(X)^K`

where $`I \sqcup\sqcup J` denotes all interleavings (shuffles) of the multi-indices $`I` and $`J`. This generalizes the multiplication of polynomials and implies that the signature terms are not independent: there are algebraic constraints between them. The log-signature removes this redundancy.

## Uniqueness

The signature determines the path up to reparametrization and so-called tree-like equivalence (pieces of the path that go out and come back along the same route). For paths that do not cross themselves, the signature is a complete descriptor of the geometric shape.

# Piecewise linear paths

For computation, piecewise linear paths are the key case. A piecewise linear path is defined by a sequence of points $`X_0, X_1, \ldots, X_m` connected by straight line segments.

For a single linear segment with increment $`\Delta = X_{i+1} - X_i \in \mathbb{R}^d`, the signature takes a particularly simple form: the tensor exponential

$$`S(\text{segment}) = \exp(\Delta) = 1 + \Delta + \frac{\Delta \otimes \Delta}{2!} + \frac{\Delta \otimes \Delta \otimes \Delta}{3!} + \cdots`

where $`\Delta \otimes \Delta` denotes the tensor product. The term at level $`k` is just

$$`S(\text{segment})^{i_1, \ldots, i_k} = \frac{\Delta^{i_1} \cdot \Delta^{i_2} \cdots \Delta^{i_k}}{k!}.`

Then, by Chen's identity, the signature of the full piecewise linear path is:

$$`S(X)_{0,m} = \exp(\Delta_1) \otimes \exp(\Delta_2) \otimes \cdots \otimes \exp(\Delta_m).`

This gives a concrete, finite algorithm: for each segment, compute the tensor exponential (truncated at level $`N`), then compose them one by one using the tensor product. The cost is linear in the number of segments and exponential only in the truncation level, which is typically small (2, 3, or 4).

## A concrete example

Consider a 2D path with three points: $`(0, 0) \to (3, 1) \to (1, 4)`. The two segments have increments $`\Delta_1 = (3, 1)` and $`\Delta_2 = (-2, 3)`.

For $`\Delta_1 = (3, 1)`, the level-1 terms are $`(3, 1)` and the level-2 terms are $`(9/2, 3/2, 3/2, 1/2)` corresponding to $`(S^{xx}, S^{xy}, S^{yx}, S^{yy})`.

For $`\Delta_2 = (-2, 3)`, the level-1 terms are $`(-2, 3)` and the level-2 terms are $`(2, -3, -3, 9/2)`.

After composing via the tensor product, the full path signature at level 2 is:
- Level 1: $`S^x = 3 + (-2) = 1`, $`S^y = 1 + 3 = 4`
- Level 2: $`S^{xx} = 9/2 + 2 + 3 \cdot (-2) = 1/2`, $`S^{xy} = 3/2 + (-3) + 3 \cdot 3 = 15/2`, $`S^{yx} = 3/2 + (-3) + 1 \cdot (-2) = -7/2`, $`S^{yy} = 1/2 + 9/2 + 1 \cdot 3 = 8`

The Levy area is $`\frac{1}{2}(S^{xy} - S^{yx}) = \frac{1}{2}(15/2 - (-7/2)) = 11/2 = 5.5`, which is the signed area enclosed between the path and its chord.

# The ML pipeline

The signature method provides a simple and general pipeline for learning from sequential data:

*data* $`\to` *path* $`\to` *signature* $`\to` *features* $`\to` *learning algorithm*

## Step 1: Embed data as a path

Raw sequential data (a time series, a sequence of events, a stream of sensor readings) is converted into a continuous path in $`\mathbb{R}^d`. The simplest approach is piecewise linear interpolation. Several augmentations can improve the representation:

- *Time augmentation*: add a monotone time coordinate as an extra dimension, so the signature captures temporal patterns.
- *Lead-lag transformation*: duplicate the stream with a time shift, creating a 2D path from a 1D series. The Levy area of this path captures the quadratic variation (related to volatility in finance).
- *Base-point augmentation*: prepend the origin to break translation invariance.
- *Cumulative sum*: take running totals before embedding, so the signature captures aggregate statistics.

## Step 2: Compute the truncated signature

The truncated signature (or log-signature for a more compact representation) gives a fixed-size feature vector. The truncation level $`N` controls the trade-off between expressiveness and dimensionality.

## Step 3: Feed into a learning algorithm

The signature features can be fed directly into any standard model: logistic regression, SVM, random forest, or neural network. The signature acts as a non-parametric feature extractor: it does not require learning, and the resulting features have theoretical guarantees (linear functionals on signatures are universal approximators for continuous functions on paths).

## Why this matters for long event sequences

When you have a long stream of events (clicks, transactions, sensor readings), embedding them as a path and computing the truncated signature gives you a fixed-size feature vector that captures the essential sequential structure: order, correlations, and signed areas. You do not need to train a model to learn these patterns from scratch. The signature provides them for free, and a simple linear model on top can often do surprisingly well.

# Applications

The signature method has been applied across many domains:

- *Finance*: identifying atypical market behavior, non-parametric regression on expected signatures, optimal execution, pricing of exotic derivatives.
- *Healthcare*: early detection of sepsis from multivariate physiological time series, diagnosis of Alzheimer's disease from brain imaging, detecting mood changes in bipolar disorder from self-reported data.
- *Handwriting recognition*: the paper presents a detailed example of digit classification using the signature as a feature map. The level-2 terms (signed areas) are particularly informative for distinguishing digits like 0 and 8, which have similar overall shape but different enclosed areas.
- *Natural language processing*: representing chronological information in medical texts.
- *Computer vision*: human pose estimation, deep signature transforms for learning on sequential image data.

The paper by Chevyrev and Kormilitzin gives a clear and self-contained introduction to both the theory and the practice. The first part covers the mathematical foundations (iterated integrals, Chen's identity, shuffle product, log-signature, uniqueness) at an accessible level. The second part shows how to go from raw data to signature features and applies the method to handwritten digit classification. For a more complete picture, the [DataSig group](https://www.datasig.ac.uk/papers) maintains a list of applications and software.

# Try it yourself

The interactive module below lets you explore path signatures visually. In the first tab, draw a 2D path by clicking on the canvas and see the truncated signature computed in real time at the chosen level. In the second tab, draw a path and click "Reconstruct": a 64-segment chain starts as a straight line and is optimized by gradient descent to match the signature up to the chosen level. The loss combines the signature MSE with two regularizers: a straight-line pull (which dominates at low levels, keeping the chain straight when the signature allows it) and a curvature penalty (which prevents high-frequency curls). Gradients are computed efficiently using the prefix-suffix decomposition. At level 1, only displacement matters, so the chain stays straight. At higher levels, the chain bends progressively to capture signed areas and finer shape details.

:::iframe "static/blog/signature-method/signature-explorer.html"
:::
