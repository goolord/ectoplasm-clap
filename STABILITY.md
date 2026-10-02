# Stable parameter bounds for the Gray-Scott lattice

This note covers why the processor in `dsp/GrayScottResonator.cmajor` cannot produce NaN or ±Inf in float32, which parameter combinations would break that, and how to carry the same guarantees into a fixed-point port.

## The discrete system

Each of the 128 ring nodes holds concentrations $u_i, v_i$. One explicit-Euler step of size $\Delta t$ is

$$
\begin{aligned}
u_i' &= u_i + \Delta t\,\big[D_u L u_i - u_i v_i^2 + F(1-u_i)\big] \\
v_i' &= v_i + \Delta t\,\big[D_v L v_i + u_i v_i^2 - (F+K)\,v_i\big] + s_i
\end{aligned}
\qquad
L x_i = \tfrac12(x_{i-1} + x_{i+1}) - x_i
$$

where $s_i$ is the audio injection (input plus feedback, spread over four nodes by a cubic B-spline). After every step, each value passes through `softClamp`.

## 1. Diffusion: the hard limit

On the ring, $L$ has eigenvalues $\lambda(\theta) = \cos\theta - 1 \in [-2, 0]$. On its own, the diffusion part multiplies each spatial mode by

$$g(\theta) = 1 + D\,\Delta t\,\lambda(\theta) \in [\,1 - 2D\Delta t,\ 1\,].$$

| Condition | Consequence |
|---|---|
| $D\Delta t > 1$ | $\lvert g(\pi)\rvert > 1$. The checkerboard mode grows geometrically and reaches Inf in a few hundred samples. **This is the one true explosion.** |
| $\tfrac12 < D\Delta t \le 1$ | Stable, but $g(\pi) < 0$: the Nyquist mode flips sign every step and rings. You hear it as an aliased whine, and it can drive concentrations negative. |
| $D\Delta t \le \tfrac12$ | Monotone: every $g \ge 0$, so diffusion is a convex average of neighbours and can't create new extrema. |

The processor enforces the monotone case by construction:

* $D_u \in [0.05, 0.50]$ and $D_v = D_u \cdot \text{ratio}$ with ratio $\in [0.1, 1.0]$, so $D_v \le D_u \le 0.5$.
* Speed is split into $n = \lceil \text{speed} \cdot 48000/f_s \rceil$ sub-steps, capped at 8, with $\Delta t = \min(1, \text{speed}\cdot 48000/f_s / n) \le 1$.

So $D\Delta t \le 0.5$ always holds. If you raise the Diffusion ceiling, you must also shrink $\Delta t$ (more sub-steps) to keep $D\Delta t \le 0.5$.

## 2. Reaction: F and K are about behaviour, not safety

The Jacobian at the trivial state $(1, 0)$ has eigenvalues $-F$ and $-(F+K)$. Euler is stable for $\Delta t\,(F+K) < 2$. The largest value here is $0.16$, so there is a margin of more than 10×.

At the homogeneous state $(U^*, V^*)$, which exists below the saddle-node curve $K = \sqrt F/2 - F$:

$$\operatorname{tr} J = K - V^{*2}, \qquad \det J = (F+K)(V^{*2} - F)$$

Across the whole box $F \in [0.010, 0.090]$, $K \in [0.045, 0.070]$, $\lvert\lambda\rvert \le \sqrt{\det J} < 0.1$. Euler's per-step error is $O(\lambda^2\Delta t^2) \approx 10^{-2}$ relative. That shifts the resonant frequency by about 1% but never destabilises the scheme. The Hopf curve $F + K = \sqrt F\,K^{1/4}$ is a genuine bifurcation of the PDE, not a numerical artefact. Crossing it is supposed to make the ring self-oscillate.

**Invariant region.** Without injection, and with $D\Delta t \le \tfrac12$ and $\Delta t \le 1$:

* $v' \ge v\,[1 - \Delta t(D_v + F + K)] \ge 0.34\,v$, so **V stays non-negative**.
* $u' \le u\,[1 - \Delta t(D_u + F)] + \Delta t(D_u \bar u + F)$ is a convex combination of values $\le 1$, so **U stays at or below 1**.
* $u' \ge 0$ needs $\Delta t\,(D_u + v^2 + F) \le 1$, which holds while $v \lesssim 0.64$.
* For the homogeneous mode, $w = u + v$ obeys $\dot w = F(1-u) - (F+K)v \le F(1-w)$, so $w$ stays at or below 1.

So the unforced dynamics live in $[0,1]^2$. The cubic term $u v^2$ is bounded by 1 there, and nothing can overflow. Only the forcing term $s_i$ can push a node outside the box: the input adds at most 0.003 × Drive (×16 at +24 dB) ≈ 0.05 per sample. `softClamp` handles that case:

* $[10^{-12}, 0.9]$ maps to itself.
* Above 0.9 is a C¹ tanh knee with an asymptote at 1.25, which caps $u v^2 \le 1.95$.
* Anything below $10^{-12}$ becomes 0. That covers negatives, denormal-range values, and NaN, because NaN fails both comparisons.
* $+\infty$ becomes 1.25.

So no lattice value can be non-finite after any step, whatever the input. As a final layer, an output watchdog re-seeds the lattice if $\lvert\text{wet}\rvert \ge 10^6$ or NaN, and fades the wet path back in over 60 ms.

### What would blow up if you removed the guards

| Removed guard | Failure |
|---|---|
| $D\Delta t \le 1$ (e.g. Speed > 1 without sub-steps, or $D_u$ = 1 at $\Delta t$ = 1) | Checkerboard growth, then Inf, then NaN within ~100 ms |
| Lower clamp at 0 | A negative $v$ makes $u v^2 > 0$ in the U equation while $-(F+K)v$ adds to V. Under strong drive, overshoot can compound until it overflows. |
| Upper clamp | With $\Delta t = 1$ and $v \gtrsim 1.5$ the cubic term overshoots: $v' \approx v^3$, which overflows float32 in about 6 steps. |
| Denormal flush | Not a correctness bug, but decaying regimes spend thousands of samples in subnormal arithmetic. On x86 without FTZ/DAZ that is a 10–100× CPU spike. |

### Resonance (anti-damping)

Resonance adds $\Delta t\, g\, A\,d/(A + \lvert d\rvert)$ to $v$ each step, where $d = v - V^*$ and $A = 0.004$. Here $g = r\,g_\text{edge}$, where $g_\text{edge}$ is the discrete edge of the homogeneous focus (README, *Resonance*) and $r \le 1.5$. Over the whole F×K box $g_\text{edge} \le 0.242$ (computed on a grid; the maximum is at F = 0.0895, K = 0.045, dt = 1), so the term is at most $1.5 \times 0.242 \times A \approx 1.5\times10^{-3}$ per step, whatever $d$ is. It can't overflow anything, and it leaves the invariant-region argument above intact up to that small forcing. Past $r = 1$ the focus grows. The saturation turns that into a limit cycle of amplitude about $A$, instead of the subcritical swing out of the focus's basin and collapse to the trivial state that Gray-Scott does by itself.

## 3. Float32 specifics

* **Precision.** Diffusive increments near steady state are around $D\Delta t\cdot\delta \approx 10^{-6}$, well above float32's relative epsilon ($1.2\times10^{-7}$) times $\lvert v\rvert \le 1$. Resonances therefore don't stall from round-off. There is no dither: the ring sits exactly on an equilibrium until the input moves it.
* **Cancellation.** $F(1-u)$ near $u = 1$ loses a few bits, but that term is O(F) and the error is far below anything audible.
* **Accumulation.** The ring's total mass is summed in float32 every step for collapse detection only. It never feeds back into the dynamics.

## 4. Fixed-point port

All state is bounded in $[0, 1.25]$ and products in $[0, 1.95]$, so:

* State in **Q2.29** (signed 32-bit, range ±4) leaves 2× headroom over the clamp ceiling.
* Do $u v^2$ as two Q2.29 × Q2.29 → Q4.58 multiplies in 64-bit, then round back to Q2.29. Don't truncate the intermediate to 32 bits. $v^2$ alone can need the full range.
* Implement the clamp with integer compares. The tanh knee can be a 64-entry table. A hard clamp at 1.25 is also acceptable, because the knee only matters for transient overshoot.
* Store $D\Delta t \le 0.5$ as an exact power-of-two-friendly constant, or use Q1.30. The monotonicity argument above depends on it being at most 0.5, so round **down**.
* With 29 fractional bits, a value decays to 0 after about $29/\log_2(1/0.84)$ ≈ 115 steps at the slowest rate, with no denormals. You don't need the flush.

## 5. Verified behaviour

These checks were run with `cmaj render` (LLVM JIT, float32):

* **693-cell F×K grid** (step 0.0025 × 0.00125, `tools/measure-map.mjs`): 0 non-finite samples.
* **Corner stress tests:** F, K at all four corners × Speed {0.05, 4} × Drive 24 dB × Resonance 1.5 × $D_u$ 0.5 × ratio 0.1 × pickup at the injector, at 44.1 / 48 / 96 kHz. 0 non-finite samples, and output peak ≤ 0.5 at the default −6 dB output gain (`just test` reruns these).
* **Sample-rate invariance:** the resonant focus at F = 0.045, K = 0.0575 measured 445 / 449 / 478 Hz at 44.1 / 48 / 96 kHz. Linear theory predicts 426 Hz.

## 6. Where to put F and K

The phase plane in the GUI shows these regions. Numbers are for the default $D_u = 0.4$, ratio 0.6, Speed 1:

| Region | Rough location | What you hear |
|---|---|---|
| Chaos | left of the Hopf curve, F ≲ 0.025, K ≲ 0.0525 | Self-oscillating, broadband, never settles |
| Drones | a 0.01-wide strip just right of the Hopf curve | Tuned resonator; Resonance lengthens the ring and sustains past 1. The Play page's Color knob keeps F 0.004 right of the Hopf curve, inside this strip; the default is here (302 Hz, ~0.5 s). |
| Stripes | just below the saddle-node curve | Turing patterns (if ratio < 1); strong, gritty resonance |
| Damped | low K, high F | Uniform state; short plucky rings |
| Spots / Solitons | just above the saddle-node curve | Input triggers localised spots or pulses; quieter |
| Silent | well above the saddle-node curve | The trivial state wins; everything decays |

None of these regions is numerically dangerous. "Silent" only means the chemistry has no non-trivial attractor.
