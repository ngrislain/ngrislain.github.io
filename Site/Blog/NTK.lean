import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Reading Note: The Neural Tangent Kernel" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 05, day := 07 }
%%%

:::hero "NTK kernel ridge regression demo" "static/blog/ntk/thumbnail.png"
:::

A reading note on [Neural Tangent Kernel: Convergence and Generalization in Neural Networks](https://arxiv.org/abs/1806.07572) by Arthur Jacot, Franck Gabriel, and Clément Hongler (NeurIPS 2018).

# The problem

Training a deep neural network works in practice, but the loss surface is highly non-convex and full of saddle points. Why does gradient descent find good minima at all? And why do strongly over-parametrized networks generalize, even though they could perfectly fit random labels? Most analyses look at parameters, where the geometry is opaque. The Jacot, Gabriel, Hongler paper proposes a different angle: study the dynamics in _function space_, where the cost is convex.

# Setup

Take a fully connected network of depth $`L` with widths $`n_0, \ldots, n_L`. The paper uses a slightly non-standard parametrization. The pre-activations are

$$`\tilde\alpha^{(\ell+1)}(x;\theta) = \frac{1}{\sqrt{n_\ell}}\, W^{(\ell)} \alpha^{(\ell)}(x;\theta) + \beta\, b^{(\ell)},`

with weights and biases initialized as iid $`\mathcal{N}(0,1)`. The factor $`1/\sqrt{n_\ell}` is what makes everything work. It keeps activations $`O(1)` as widths grow, and scales gradients exactly the way the limit theorems below need.

The network defines a _realization map_ $`F^{(L)} : \mathbb{R}^P \to \mathcal{F}`, sending the parameter vector $`\theta` to the function $`f_\theta` it represents. Training optimizes a cost $`C : \mathcal{F} \to \mathbb{R}`. The composite $`C \circ F^{(L)}` is non-convex in $`\theta`, but $`C` itself in function space is typically convex (quadratic for least squares). The whole point is to lift the dynamics from parameter space to function space.

# Kernel gradient descent

For a positive definite kernel $`K`, the kernel gradient of $`C` at a function $`f_0` is

$$`\nabla_K C|_{f_0}(x) = \frac{1}{N} \sum_{j=1}^{N} K(x, x_j)\, d|_{f_0}(x_j),`

where $`d|_{f_0}` is the function-space gradient of the cost at $`f_0`. A path $`f(t)` follows _kernel gradient descent_ when $`\partial_t f = -\nabla_K C|_{f}`. Convergence to a global minimum of a convex $`C` is guaranteed as long as $`K` is positive definite.

The paper's central observation: when you train a neural network with vanilla gradient descent on parameters, the network function $`f_\theta` follows kernel gradient descent in function space, with respect to a specific kernel.

# The Neural Tangent Kernel

The NTK is

$$`\Theta^{(L)}(\theta) = \sum_{p=1}^{P} \partial_{\theta_p} F^{(L)}(\theta) \otimes \partial_{\theta_p} F^{(L)}(\theta),`

a sum of outer products of parameter gradients. By the chain rule, gradient descent on $`\theta` is equivalent to

$$`\partial_t f_{\theta(t)} = -\nabla_{\Theta^{(L)}(\theta(t))} C|_{f_{\theta(t)}}.`

For any finite network this kernel is random at initialization (it depends on the draw of weights) and changes during training. The two main theorems say that in the infinite-width limit, both effects vanish.

# Theorem 1: at initialization, the NTK is deterministic

As the hidden widths $`n_1, \ldots, n_{L-1} \to \infty`, the NTK converges in probability to a deterministic kernel:

$$`\Theta^{(L)} \to \Theta^{(L)}_\infty \otimes \mathrm{Id}_{n_L}.`

The limit $`\Theta^{(L)}_\infty` only depends on the depth, the activation function $`\sigma`, and the initialization variance. It is built by a layerwise recursion. Starting from $`\Theta^{(1)}_\infty(x, x') = \Sigma^{(1)}(x, x') = x^T x'/n_0 + \beta^2`, each new layer adds

$$`\Theta^{(\ell+1)}_\infty(x, x') = \Theta^{(\ell)}_\infty(x, x')\, \dot\Sigma^{(\ell+1)}(x, x') + \Sigma^{(\ell+1)}(x, x'),`

where $`\Sigma^{(\ell)}` is the limit covariance of pre-activations (the well-known Gaussian process limit of a wide net at initialization), and $`\dot\Sigma^{(\ell+1)}(x, x') = \mathbb{E}_{f \sim \mathcal{N}(0, \Sigma^{(\ell)})}[\dot\sigma(f(x))\dot\sigma(f(x'))]`. The two terms have a clear meaning: the rightmost summand is the contribution of the last layer (a linear readout of frozen features), and the first summand is the contribution of all earlier layers.

# Theorem 2: during training, the NTK is frozen

In the same infinite-width limit, the NTK _stays constant during training_, for any time horizon $`T` such that $`\int_0^T \|d_t\|_{p^{in}}\, dt` stays bounded (which holds for least squares). Concretely, $`\Theta^{(L)}(t) \to \Theta^{(L)}_\infty \otimes \mathrm{Id}_{n_L}` uniformly on $`[0, T]`.

The intuition is subtle. The activation of any single neuron in a hidden layer changes by $`O(1/\sqrt{n_\ell})` during training, so each individual neuron barely moves. But there are $`n_\ell` of them, and their _collective_ shift is significant. So the network learns at the level of layers, even though each unit is essentially frozen. This is the precise sense in which infinitely-wide networks are in the "lazy" regime: the features at every layer are locked in by initialization.

The training dynamics of the network function reduce to a single linear differential equation:

$$`\partial_t f_{\theta(t)} = \Phi_{\Theta^{(L)}_\infty \otimes \mathrm{Id}_{n_L}}\!\left(\langle d_t, \cdot \rangle_{p^{in}}\right).`

# Consequences for least squares

Take the regression cost $`C(f) = \frac{1}{2} \|f - f^*\|^2_{p^{in}}`. The dynamics simplify, and the network function evolves as

$$`f_t = f^* + e^{-t\Pi}(f_0 - f^*),`

where $`\Pi` is the integral operator associated to the NTK on the data. Diagonalize $`\Pi` along its kernel principal components $`f^{(i)}` with eigenvalues $`\lambda_i`. Then $`f_t - f^*` decays as $`e^{-t \lambda_i}` along the $`i`-th component. Convergence is fast in directions with large eigenvalues and slow in directions with small eigenvalues. _Early stopping_ falls out for free: stop training before the small-eigenvalue (typically high-frequency, noisy) directions get fit.

At $`t \to \infty`, assuming the NTK Gram matrix on the training set is invertible, the network function converges to

$$`f_\infty(x) = \kappa^T_x \tilde K^{-1} y^* + \big(f_0(x) - \kappa^T_x \tilde K^{-1} y_0\big),`

with $`\kappa_x = (K(x, x_i))_i`, $`y^* = (f^*(x_i))_i`, and $`y_0 = (f_0(x_i))_i`. The first term is the maximum-a-posteriori estimate under a Gaussian prior with covariance $`\Theta^{(L)}_\infty` (equivalently, kernel ridge regression in the zero-regularizer limit). The second term is a centered Gaussian process whose variance vanishes on the training points. So an infinitely wide network trained by gradient descent _is_, in distribution, a Gaussian process posterior, with covariance fixed at the start.

# Try it yourself

The interactive demo below computes the limiting ReLU NTK in closed form via the layerwise recursion above, and uses it to do kernel ridge regression on 1D points you click. The grey band is one standard deviation under the NTK Gaussian process posterior. Toggle "Show NN samples" to overlay finite-width networks at the chosen width and see how they hug the limit. The bottom heatmap is the kernel matrix $`\Theta^{(L)}_\infty(x, x')` over the input grid.

:::iframe "static/blog/ntk/ntk-demo.html"
:::

# Why this matters

A few things to take away.

1. *Training as kernel descent.* In the infinite-width limit the whole training trajectory lives in function space and is driven by a single fixed kernel that depends only on architecture and initialization. The non-convexity of the loss in parameter space is illusory at this scale.

2. *A direct link to Bayesian kernel methods.* The function reached by gradient descent at convergence equals (up to a vanishing Gaussian fluctuation) kernel ridge regression with the NTK. Generalization can then be analyzed with the existing kernel machinery, on a kernel that is computable in closed form from the architecture.

3. *Early stopping has a precise spectral meaning.* It truncates the spectrum at the level beyond which only small-eigenvalue components remain, which are typically the noisy ones.

4. *The limit is a starting point, not the end.* The clean picture relies on the specific NTK scaling and on infinite width. The numerical experiments in the paper already show that for $`n = 500` the kernel does inflate during training, and feature learning, by definition, requires the kernel to move. Subsequent work (mean-field limits, maximal-update parametrization, feature-learning regimes) explores the directions where this picture breaks.

The NTK is not the right model for every regime of deep learning, but it gave the field a clean baseline. A proof that wide enough networks trained by gradient descent are kernel methods in disguise. The papers that came after (mean-field theory, lazy versus rich training, scaling laws) read in some sense as variations on, or departures from, this result.
