import VersoBlog
import Site.Embed

open Verso Genre Blog

#doc (Post) "Reading Note: A Theory of Deep Learning" =>

%%%
authors := ["Nicolas Grislain"]
date := { year := 2026, month := 05, day := 07 }
%%%

:::hero "eNTK eigenvalue spectrum: signal channel and reservoir" "static/blog/reservoir/thumbnail.png"
:::

A reading note on [A Theory of Deep Learning](https://elonlit.com/scrivings/a-theory-of-deep-learning/) by Elon Litman (May 2026, preprint forthcoming).

The post is dense and the central derivations are sketched rather than written out. I want to fill the gaps for myself, so this note rebuilds the framework step by step and works out the algebra explicitly. The picture that emerges is a single mechanism behind four very different phenomena.

# Four phenomena classical theory cannot explain

The four behaviors the theory tries to unify:

1. *Benign overfitting.* A network reaches zero training loss, fits even noisy labels exactly, and still generalizes. Classical statistics says exact interpolation of noise should be fatal.

2. *Double descent.* As model capacity grows past the interpolation threshold, test error first goes up (the classical U-curve), then comes back down. The bias-variance trade-off is non-monotonic.

3. *Implicit bias.* Among all parameter vectors that interpolate the training set, gradient descent picks ones with small norm and approximately low rank, with no explicit regularizer.

4. *Grokking.* On a structured task without an aligned inductive bias, the network first memorizes (training loss zero, test loss flat) and then, after many more steps, suddenly generalizes.

Different theoretical frameworks (uniform convergence, NTK, PAC-Bayes, mean-field, stability) explain different phenomena under incompatible assumptions. Litman's claim is that all four follow from a single operator: the integrated empirical neural tangent kernel.

# The output-space view

Setup. Parameters $`w \in \mathbb{R}^P`. Training inputs $`\{x_i\}_{i=1}^n` and stacked output vector $`U_S(w) \in \mathbb{R}^{np}`. Loss $`\mathcal{L}(w) = \Phi_S(U_S(w))`, where $`\Phi_S` is convex in the outputs (squared loss, cross-entropy). The Jacobian is $`J_S(w) = \partial U_S / \partial w \in \mathbb{R}^{np \times P}`.

The empirical neural tangent kernel on the training set is

$$`K_{SS}(w) = J_S(w)\, J_S(w)^T \in \mathbb{R}^{np \times np}.`

Block $`(i, j)` measures how a gradient step at $`x_j` perturbs the prediction at $`x_i`. Note that this is finite-width: nothing requires $`P \to \infty`.

Gradient flow on parameters is $`\partial_t w = -\nabla_w \mathcal{L} = -J_S^T g`, with $`g = \nabla_u \Phi_S(U_S)`. Applying the chain rule, training outputs evolve as

$$`\partial_t u = J_S\, \partial_t w = -J_S J_S^T g = -K_{SS}\, g.`

The output gradient itself satisfies

$$`\partial_t g = \nabla^2_u \Phi_S(u) \cdot \partial_t u = -B\, K_{SS}\, g, \qquad B = \nabla^2 \Phi_S(u).`

For test inputs $`\{q_a\}_{a=1}^m` with stacked outputs $`U_Q(w)` and Jacobian $`J_Q`, the same chain rule gives

$$`\partial_t U_Q = -K_{QS}\, g, \qquad K_{QS} = J_Q\, J_S^T.`

Test outputs are driven by the cross-kernel $`K_{QS}` against the same training gradient $`g`. This is the bridge between training and generalization.

The instantaneous loss decrease is

$$`\frac{d}{dt} \Phi_S(u) = \langle g, \partial_t u \rangle = -g^T K_{SS}\, g = -\|J_S^T g\|_2^2.`

This is non-negative and vanishes only on directions of $`g` that lie in the kernel of $`K_{SS}`.

# Spectral picture under squared loss

Take $`\Phi_S(u) = \tfrac{1}{2n}\|u - y\|^2`, so $`g = r/n` with residual $`r = u - y`, and $`B = I/n`. The residual obeys

$$`\partial_t r = \partial_t u = -\tfrac{1}{n}\, K_{SS}(t)\, r = -M(t)\, r.`

If $`K_{SS}` were frozen (the NTK regime), with eigendecomposition $`K_{SS} = \sum_i \lambda_i v_i v_i^T`, the residual decomposes as $`r(t) = \sum_i c_i(t) v_i` and each component decays independently:

$$`c_i(t) = c_i(0)\, e^{-\lambda_i t / n}.`

A mode of eigenvalue $`10\lambda` is learned ten times faster than a mode of eigenvalue $`\lambda`. On any finite training horizon $`T`, modes below a threshold $`\lambda_\star \sim n/T` have barely moved. That is the precise spectral content of early stopping.

In the _feature learning_ regime, $`K_{SS}` is not frozen. As $`w` moves, eigenvectors rotate and eigenvalues shift, so the snapshot at any single time tells only a partial story. To capture what training _actually_ does, we need to integrate $`K_{SS}` along the path.

# The integrated eNTK

Let $`P_g(\tau, s)` be the time-ordered solution operator of the gradient ODE $`\partial_t g = -B K_{SS}\, g`, so that $`g(\tau) = P_g(\tau, s)\, g(s)`. Define the _integrated eNTK_

$$`\mathcal{W}_S(s, T) = \int_s^T P_g(\tau, s)^T\, K_{SS}(\tau)\, P_g(\tau, s)\, d\tau.`

Its quadratic form is

$$`\xi^T \mathcal{W}_S\, \xi = \int_s^T \big\|J_S(\tau)^T\, P_g(\tau, s)\, \xi\big\|_2^2\, d\tau,`

a non-negative integral of squared norms, so $`\mathcal{W}_S \succeq 0`.

Why this object? Integrate the loss-decay rate from $`s` to $`T`. Substituting $`g(\tau) = P_g(\tau, s)\, g(s)` gives

$$`\Phi_S(u(s)) - \Phi_S(u(T)) = \int_s^T g(\tau)^T K_{SS}(\tau)\, g(\tau)\, d\tau = g(s)^T\, \mathcal{W}_S(s, T)\, g(s).`

So $`\mathcal{W}_S` is exactly the operator that turns the initial output gradient $`g(s)` into the cumulative loss reduction over the training window. Decompose $`g(s)` along eigenvectors $`\psi_j` of $`\mathcal{W}_S` with eigenvalues $`\lambda_j(\mathcal{W}_S)`. Each direction contributes $`\lambda_j(\mathcal{W}_S)\, |\langle \psi_j, g(s) \rangle|^2` to the total dissipation.

Two regions appear naturally in output-gradient space:

- *Signal channel*: $`\mathrm{range}(\mathcal{W}_S)`, the directions where the integrated dissipation is strictly positive. Training does work here.

- *Reservoir*: $`\ker(\mathcal{W}_S)`, the directions where the integrated dissipation is zero. Components of $`g(s)` in the reservoir flow through the dynamics without affecting the loss.

In real networks the boundary is soft: $`\ker(\mathcal{W}_S)` is approximated by the directions of near-zero eigenvalue. Treating it as a strict null space is the right idealization.

# Test predictions only see the signal channel

Define the _test transfer operator_

$$`G_Q(T, s) = \int_s^T K_{QS}(\tau)\, P_g(\tau, s)\, d\tau.`

Integrating $`\partial_t U_Q = -K_{QS}\, g` along the trajectory gives

$$`U_Q(T) - U_Q(s) = -\int_s^T K_{QS}(\tau)\, g(\tau)\, d\tau = -G_Q(T, s)\, g(s).`

So $`G_Q` is the linear map from the initial output gradient to the change in test predictions. The central claim of the theory is

$$`\ker \mathcal{W}_S \;\subseteq\; \ker G_Q.`

The proof is one line. Take $`\xi \in \ker \mathcal{W}_S`. Then

$$`0 = \xi^T \mathcal{W}_S\, \xi = \int_s^T \big\|J_S(\tau)^T P_g(\tau, s)\, \xi\big\|_2^2\, d\tau,`

which forces $`J_S(\tau)^T P_g(\tau, s)\, \xi = 0` for almost every $`\tau`. Plugging in,

$$`G_Q(T, s)\, \xi = \int_s^T K_{QS}(\tau)\, P_g(\tau, s)\, \xi\, d\tau = \int_s^T J_Q(\tau)\, \big(J_S(\tau)^T P_g(\tau, s)\, \xi\big)\, d\tau = 0.`

Components of $`g(s)` in the reservoir produce no loss decrease _and_ no change in test predictions. They are invisible at test time. The signal-versus-noise allocation between the channel and the reservoir is what controls generalization.

# Reading off the four phenomena

*Benign overfitting.* At interpolation, $`g(T) \to 0` even when the labels include noise. The components of $`g(s)` that carry the network through label noise sit in (or close to) the reservoir, so $`G_Q` cancels them exactly. The network can fit noise on the training set without paying for it on the test set.

*Double descent.* As capacity grows past the interpolation threshold, the kernel spectrum is sharply distorted. Small eigenvalues collapse, and noise that used to sit in the soft reservoir briefly enters the signal channel. Test error spikes. Past the threshold, increased capacity restores a wider reservoir and the noise is reabsorbed. Double descent is a spectral migration of noise modes between channel and reservoir.

*Implicit bias.* Gradient flow learns directions in order of $`\mathcal{W}_S` eigenvalue: highest-mobility modes equilibrate first, lowest-mobility modes last. The accumulated signal channel grows monotonically and test predictions are confined to it. The network behaves like a Moore-Penrose pseudo-inverse over the _realized feature path_, not over static parameter space, which is why the solution looks like a minimum-norm interpolant in the right metric.

*Grokking.* The kernel rotates slowly, and on a structured task the generalizing mode initially sits in the reservoir. Fast directions are the ones that fit individual examples, so memorization comes first. Only after enough kernel rotation does the structured mode enter the signal channel, at which point the test loss drops abruptly. The delay is the time the eigenstructure needs to align.

# The same operators give a training rule

The argument behind the per-parameter update rule is short. For a minibatch of size $`b`, treat each sample as a one-point held-out set against the other $`b-1`. For parameter $`k`, let

$$`\mu_k = \frac{1}{b}\sum_{i=1}^b \partial_k \mathcal{L}_i, \qquad \sigma_k^2 = \frac{1}{b-1}\sum_{i=1}^b (\partial_k \mathcal{L}_i - \mu_k)^2`

be the batch mean and unbiased sample variance of the per-example gradient on parameter $`k`. The variance of the leave-one-out mean (over the $`b-1` other samples) is $`\sigma_k^2/(b-1)`. The update rule is

$$`\mu_k^2 \;>\; \frac{\sigma_k^2}{b-1}.`

If satisfied, take the gradient step on $`k`. If not, skip the update on $`k` for this batch. In words: only update a parameter when the squared batch signal exceeds the variance of the leave-one-out mean. It is a per-parameter signal-to-noise gate.

The reported empirical effects are striking: 5x faster grokking, suppressed memorization in PINNs, better DPO fine-tuning, and no need for a held-out validation set. The last one is a direct corollary: gating on within-batch SNR is already approximating leave-one-out generalization, so the validation set is redundant by construction.

# Try it yourself

The interactive demo below trains a small ReLU MLP on noisy 1D regression by gradient descent, computes the empirical NTK $`K_{SS} = J_S J_S^T` on the training set at the current parameters, and shows its eigenspectrum in real time. The top bars are eigenvalues; the bottom bars are $`|\langle v_i, r \rangle|^2`, the projection of the residual $`r = f(x) - y` onto each eigenvector. The story you should see: as training proceeds, the residual concentrates in the small-eigenvalue (reservoir) directions. Memorized noise sits in directions that the test transfer operator cancels.

:::iframe "static/blog/reservoir/reservoir-demo.html"
:::

# What I take away

Three things stick with me.

1. The output-space picture works at finite width and finite depth, with no infinite-width limit. The eNTK depends on $`w` and rotates during training. The framework accommodates feature learning rather than denying it, which was the main shortcoming of the original NTK story.

2. The reservoir argument is short and clean. Once you have $`\mathcal{W}_S` and $`G_Q`, the inclusion $`\ker \mathcal{W}_S \subseteq \ker G_Q` reduces to "an integrated squared norm vanishes only when its integrand does", but the consequence is sweeping. The network is structurally incapable of leaking memorized noise to test time, in directions where the kernel did no integrated work.

3. The fact that the same operators give a practical training rule is the real test. If the theory were a post-hoc story, you would not expect a clean per-parameter SNR test to fall out of it and accelerate grokking by 5x. Whether the gains transfer to large-scale pretraining is the obvious next question.

The post leaves several things implicit. The soft reservoir of near-zero eigenvalues, in particular, deserves a quantitative treatment: how the gap between the lowest signal-channel eigenvalue and the highest reservoir eigenvalue scales with width, depth, and training length is what controls the size of the test error from imperfect cancellation. The preprint is announced as forthcoming, so presumably it works this out.
