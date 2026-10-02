# Ectoplasm

A stereo resonator effect built on a 1D Gray-Scott reaction-diffusion ring of 128 nodes, integrated at audio rate in Cmajor. Incoming audio is injected into chemical V at two points on the ring, and two pickups read V back out as audio. The chemistry rings like a tuned resonator around its homogeneous steady state. It can be pushed into sustained drones, Turing patterns, travelling pulses or chaos.

The GUI is written in ReScript and has two pages:

* **Play** (the default) shows what you'll hear. It has the chemistry as a culture in a dish, lit up along the resonator ring where your sound is ringing. Beside it is a plain-language readout (the note, how long it rings, the regime) and the frequency response the ring puts on a sound, whose peak you can drag. Below are six knobs in two groups: Pitch, Ring and Color shape the resonance; Drive, Mix and Output handle what goes in and out. Pitch moves in semitones, Pitch and Ring hold what you set while the others move, and clicking a knob's value lets you type one.
* **Lab** shows the F×K phase plane, with the analytic Hopf and saddle-node curves and a measured overlay, plus every parameter on a slider.

A preset menu in the header has nine factory presets.

## Files

| Path | What it is |
|---|---|
| `dsp/GrayScottResonator.cmajor` | The DSP processor |
| `plugin.cmajorpatch` | Patch manifest; its `name` names the built plugin, and it points the view at `gui/dist/index.js` |
| `justfile` | Build, install, test and preview recipes (from the nano-clap template) |
| `STABILITY.md` | Stable parameter bounds and why the lattice can't produce NaN/Inf, including notes for a fixed-point port |
| `gui/src/GrayScottApp.res` | App shell: the two pages, header and preset menu, one parameter mirror, scaling, rendering on demand |
| `gui/src/Macro.res` | The macros (Color, Ring, Pitch), the discrete-time focus arithmetic behind the readouts, the solve that holds the pitch and ring targets, and the parsers for typed values |
| `gui/src/Presets.res` | Factory presets |
| `gui/src/Knob.res`, `ResponsePlot.res` | Play page widgets |
| `gui/src/LevelModel.res` | The processor's level model and sub-step rule, for the view: the response plot draws it, and the pitch arithmetic uses its step rule |
| `gui/src/TuringDish.res`, `turing-gl.js` | The Play page's dish: a 2D Gray-Scott culture on the GPU (WebGL 2, with a CPU fallback), and its typed wrapper |
| `gui/src/PhasePlot.res`, `Controls.res` | Lab page widgets |
| `gui/src/LatticeView.res` | Kymograph and V-profile view, with draggable pickups (both pages) |
| `gui/src/CmajorBindings.res` | Typed `PatchConnection` bindings, the `Param` model, and the glitch-free `Bridge` |
| `gui/src/GrayScottTheory.res` | Analytic curves (saddle-node, Hopf) and the region classifier |
| `gui/src/MeasuredMap.res` | Generated: measured ring time of the processor across F×K |
| `gui/src/BrowserChrome.res`, `HostChannel.res`, `HostMenu.res`, `Settings.res` | Web-view and host quirks, adapted from nano-clap |
| `gui/src/GrayScottGui.res`, `Palette.res`, `Web.res` | Entry point, colour tokens, DOM/Canvas bindings |
| `tools/test/stability.mjs` | Stress renders at the parameter extremes and three sample rates; fails on any non-finite sample |
| `tools/test/presets.mjs` | Renders every preset and checks the Play page's claims: pitch, decay or sustain |
| `tools/measure-map.mjs`, `tools/gen-measured-map.mjs` | Measure the F×K map with `cmaj render` and generate `MeasuredMap.res` |
| `tools/patch-source.mjs` | Shared helpers for the render tools |
| `tools/gui-harness.html`, `tools/serve.mjs` | Run the GUI in a browser against a mock host (no audio) |
| `tools/clap-patch.mjs`, `tools/clap/*.h`, `tools/sync-dir.mjs`, `tools/manifest.mjs`, `tools/test/plugin.mjs` | From nano-clap, unchanged |
| `tools/rename.mjs` | Changes the plugin's name and IDs (adapted from nano-clap) |

## Build and run

Requirements: [just](https://github.com/casey/just), `cmaj`, node and npm, git, cmake ≥ 3.16 and a C++17 compiler (on Windows, Visual Studio 2022 with the C++ workload).

```bash
just
```

That builds `dist/Ectoplasm.clap`. The steps are: install npm packages if they're missing, build the GUI, fetch the CLAP headers (once), generate the CLAP project with `cmaj generate`, patch its wrapper (`tools/clap-patch.mjs`), then compile with CMake.

| Recipe | What it does |
|---|---|
| `just install` | Build, then copy into the CLAP folder. On Windows that's the system folder, which raises a UAC prompt |
| `just uninstall` | Remove it again |
| `just play` | Run the patch in Cmajor's player |
| `just preview` | Serve the GUI against a mock host at `http://127.0.0.1:5178/tools/gui-harness.html` (no audio) |
| `just test` | Stress-render the lattice (`just test chaos` filters cases by name), check every preset, render the whole plugin |
| `just measure` | Re-measure the F×K map after changing the DSP and rebuild the phase plane's overlay |
| `just ui` | Rebuild only the GUI bundle |
| `just rename "Name" com.you.id` | Change the plugin's name, ID and four-letter codes |
| `just clean` | Delete `build/`, `dist/` and the compiled GUI |

`CONFIG=Debug just` builds a debug plugin, and `CMAJ_PLUGIN_PERF=1` in a host's environment logs per-instance CPU time (see `tools/clap-patch.mjs`). Cmajor names the CMake target after the manifest name with non-alphanumerics removed; the justfile copies it to `dist/` under the display name.

## The Play page

**The dish** is the chemistry the way people picture reaction-diffusion: a 2D Gray-Scott culture of labyrinths and spots, grown on the GPU from the plugin's own F and K. The sound comes from the 1D ring, and the ring is drawn as a circle through the culture. Where the ring is ringing, the culture's blobs along that circle light up. The ring's activity is also fed into the culture there, so playing reshapes the pattern along the ring.

* **Colour changes the culture.** Turning Color moves the dish through Gray-Scott's textures: labyrinths along the resonant band, self-replicating spots above the saddle-node curve, nothing at all where nothing grows.
* **The culture is shown with a pattern-forming diffusion ratio**, Dv/Du = 0.2, whatever the plugin's own setting. At 0.2 the homogeneous state is Turing-unstable all along the Color band, so labyrinths form. At 0.5, the usual choice, the dish fills with a featureless sheet there. The plugin's ring runs at Dv/Du = 1 by default, where it rings cleanly instead of patterning. So the dish shows the chemistry's character; the readout and response curve show the sound.
* **What lights up.** Each node's highlight is its deviation from the ring's median (local activity) plus the output level (the ring's uniform swing, most of what you hear). Highlights rise fast and fade gently.
* **Cost.** It runs 600 culture steps a second on a 300×300 grid, only while the Play page is showing. Where WebGL 2 float render targets aren't available, an 80×80 CPU version runs the same chemistry. In the harness, `?cpu` forces it and `?timer-raf` keeps it animating in panes that only paint on demand.

| Knob | Sets | Shows | Type |
|---|---|---|---|
| Pitch | Speed | The note, with its offset in cents when it's more than a cent out (D4 −13 ¢), and the frequency. It moves in equal-tempered semitones (A4 = 440 Hz): drags land on the nearest, the wheel and arrow keys step one, Page Up/Down an octave. Hold Shift for free, fine movement | A note (`A3`, `a#3`, `Bb2`, `C♯4`, `D4 −13 ¢`) or a frequency (`440`, `440 Hz`, `1.2k`, `1.2 kHz`) |
| Ring | Resonance | Decay time to −60 dB, or *Sustains*. The first 85% of the turn is decay time, 30 ms to 8 s on a log scale; the last 15% sustains, Resonance 1.05 up | `1.2 s`, `300 ms`, `sustain` (or `inf`, `∞`). A bare number is milliseconds above 20 and seconds up to 20, so `300` is 300 ms and `1.5` is 1.5 s |
| Color | Feed and Kill | Where along the resonant band: K from 0.047 (near the chaotic corner) to 0.061 (towards the saddle-node apex), with F a fixed 0.004 right of the Hopf curve | |
| Drive, Mix, Output | The parameters of those names | dB and % | dB (`-6`, `+3 dB`); Mix a percentage (`50`, `50 %`) |

**Typing a value.** Click the value under a knob, or press Enter on a focused knob, and it becomes a text field. Enter applies, as one automation gesture; Escape cancels, and so does leaving it unchanged. Something it can't read shakes and the value stays as it was. Out-of-range values are clamped. Double-clicking the dial still resets it.

**Pitch and Ring are targets.** The page keeps the note and the ring time you asked for. Turning Color re-solves Speed and Resonance so both stay put, turning Pitch keeps the ring time, and turning Ring keeps the note. Decay time goes roughly as 1/Speed, so Resonance (which the solve keeps between 0 and 0.97) can't make every ring at every pitch: a 4 s ring at 1 kHz is out of reach. Then you hear the nearest it can do, the knob and readout show that with *longest here* or *shortest here* (*highest here* or *lowest here* for a note Speed can't reach), and the target is kept, so turning back brings it back. When something else moves F, K, Speed or Resonance (the Lab page, a preset, the phase plane, host automation), the targets become whatever that gives. The host's echo of a value the page just sent doesn't count.

The response plot draws what the plugin does to a sound, in dB relative to your input. It uses the processor's own level model: the ring's linear response, made up by the level match the processor puts on it, mixed with the dry signal, through Output. So it shows the peak at the note, as narrow as the ring is long; the shelf below it; the low-pass the pickups' distance and Diffusion put above it; and, with Mix below 100%, the dips where wet and dry cancel. When it sustains, the note is also marked with a bright line. It's the linear ring, so it's what quiet input hears; loud input lowers and widens the peak. Its peak is a handle: drag it sideways for the pitch (in semitones, free with Shift) and up and down for the ring (up rings longer, so the peak narrows); scroll over the plot to change the ring. A drag is relative, so it can start anywhere on the plot, and it only changes the way it has moved, so a sideways drag leaves the ring alone. Under the Hz axis, the Cs (C1 to C9) mark the octaves. The numbers come from the processor's discrete-time dynamics, not just the continuous eigenvalue: explicit Euler multiplies a mode by z = 1 + λ·dt per step, which adds about ω²·dt/2 of growth on its own. `tools/test/presets.mjs` holds the display to its word. The tuned presets ring within 0–8% of the pitch shown, and sustain exactly when the Ring knob says so. The tuned presets are written as a note and a ring time (or a sustain at a given Resonance), solved the same way the knobs are.

The pitch is marked "≈" where it's only a guide. With Dv/Du below 1, Turing patterns form and move the sound. With Drive above 9 dB, the ring's upper spatial modes come forward.

When the Lab page puts F and K off the band, Color greys out until you turn it, and the readouts still describe what you'll hear.

## Parameters

| Parameter | Range | Default | What it does |
|---|---|---|---|
| Feed F | 0.010–0.090 | 0.0446 | Gray-Scott feed rate |
| Kill K | 0.045–0.070 | 0.0585 | Gray-Scott kill rate |
| Diffusion | 0.05–0.50 | 0.40 | $D_u$. Higher couples nodes more strongly and carries signal further |
| Dv / Du | 0.10–1.00 | 1.00 | Diffusion ratio. At 1 the ring is a clean resonator; below ~0.7 Turing patterns can form |
| Speed | 0.05–4× (log) | 1.00 | Lattice time per sample. Scales every frequency the ring produces |
| Drive | 0–24 dB | 0 dB | How hard the input pushes the chemistry: at 0 dB it stays a linear resonator, by 24 dB (×16) it's well into nonlinear, pattern-breaking territory |
| Pickup distance | 0–100% | 30% | 0–12 nodes from each injector. Further away is darker |
| Resonance | 0–1.5 | 0.93 | Anti-damping, normalised so 1 is exactly the edge of self-oscillation |
| Mix | 0–100% | 100% | Dry/wet |
| Output | −36 to +12 dB | −6 dB | Output gain |

`reseed` is a non-host event endpoint (the Lab page's *Reseed lattice* button, also sent when a preset loads) that puts the ring back at rest for the current F/K.

## How it works

**Integration.** The processor uses explicit Euler on a 3-point ring Laplacian, in two passes per step: the Laplacians first, then each node's update. Each sample's lattice time is split into as few sub-steps (up to 8) as keep $D_u \cdot dt \le 0.5$, which makes the diffusion step monotone, with dt ≤ 1.25. At the default Diffusion that's one step up to Speed 1.25, so a 44.1 kHz host doesn't need two steps where 48 kHz needs one. Time runs on a fixed 48 kHz base, so pitch doesn't change with the host sample rate. `STABILITY.md` has the full derivation.

**Offsets, not concentrations.** Each node stores U and V as offsets from the steady state the ring rings around. It's the same Euler step, rearranged. Stored as concentrations (around 0.3), every step rounded at about 3e-8, and a high-Q focus kept that rounding ringing as a steady tone after the sound had gone. As offsets, the numbers near rest are tiny, and a ring decays to true silence. When F or K moves the steady state, the offsets move with it.

**Why it resonates.** Below the saddle-node curve $K = \sqrt F/2 - F$, the reaction has a homogeneous state $(U^*, V^*)$. Between the Hopf curve $F + K = \sqrt F K^{1/4}$ and the saddle-node curve, that state is a stable focus, and perturbations ring around it. The ring sits exactly on that state when it exists, and on the trivial state (U=1, V=0) when it doesn't, with no seed noise or dither. Both are equilibria, so with no input there is nothing to hear. If the ring collapses to the trivial state while there is input, it is re-seeded with a fade.

**Input.** Audio is soft-saturated (tanh), scaled by Drive, and splatted into V with a cubic B-spline kernel at a peak of 0.003 V per sample. That keeps the ring a small perturbation of its focus, so it rings at the focus's pitch. Larger injections kick it out of the focus's basin into nonlinear motion or collapse.

**Resonance** is anti-damping inside the chemistry, not an audio feedback loop. Each step adds g·A·d/(A + |d|) to V, where d = V − V*. That raises the Jacobian's trace by g, so the focus rings longer at nearly the same pitch. g is normalised so Resonance 1 is exactly the discrete edge, |1 + λ·dt| = 1:

$$g_\text{edge} = -\frac{\operatorname{tr} J + \det J \cdot dt}{1 - (V^{*2} + F)\,dt}$$

The saturation at A = 0.004 matters. Gray-Scott's Hopf bifurcation is subcritical, so a growing ring would otherwise swing out of the focus's basin and collapse. With it, the ring settles into a small, stable limit cycle instead.

An earlier version fed the pickups back as audio. It couldn't hold the pitch: the lattice has a lot of gain near DC, so the loop found a lower mode of its own (106 Hz where the focus was at 345 Hz). The cross-coupled L→R routing also went through the resonator twice, which made the loop negative right at the focus.

**Output.** Pickups read V through the same B-spline kernel. It sums to 1, is C² and acts as a spatial low-pass, so moving a pickup is click-free. The wet path is DC-blocked (8 Hz), low-passed (Butterworth, 16 kHz), then level-matched to the input. How loudly the lattice answers varies by ~40 dB across the settings (about 35 dB below the input at the defaults), and the match has two parts:

* **A prediction, as soon as a setting moves.** Around its steady state, the ring is a linear system. In spatial modes it's 64 independent 2×2 systems, so its response to a mono input is a sum of second-order sections. The processor works out that response's RMS gain for pink noise (20 Hz – 20 kHz, with the DC blocker and the low-pass) and divides the wet path by it. It recomputes only when a setting has moved, one mode or one frequency per sample, about 130 samples of work. While settings stay put it costs nothing, and even during a continuous sweep the whole plugin costs less than before it had the model. On the Play page's band it lands within about 2 dB of renders of pink noise. It takes Resonance as no more than 0.7, because louder input saturates the anti-damping and the full linear gain would overstate what you hear.
* **A trim learned from the input** over about half a second, within ±18 dB, for what the model leaves out: the input's spectrum, and how far loud input or Drive pushes the ring out of its linear range. It carries over from one setting to the next and only moves while there is input, so it can't lift noise, stretch tails or pump.

The total is at most +50 dB, and at least −12 dB. Before the prediction, the match was only the learned part. After a change, the level took a second or more to come back, and at the default settings it hit its +30 dB ceiling and stayed several dB low. An even earlier version used an AGC inside the feedback loop, and that clicked on its own clock. `gui/src/LevelModel.res` is the same model for the view.

**Parameter transport.** `Bridge.set` clamps to the declared range, then coalesces writes to one message per endpoint per animation frame. Drags are bracketed with `sendParameterGestureStart/End`; the Play page's Color knob brackets Feed, Kill, Speed and Resonance together. On the DSP side, every parameter glides over about 25 ms.

## GUI host quirks

These come from nano-clap's view shell (`ui/core/Shell.res`, `BrowserChrome.res`, `HostMenu.res`, `Settings.res`):

* **Isolated styles.** The view renders into a shadow root. Its `:host` rule overrides the inline size Cmajor puts on the view.
* **Scaling.** The 880×560 stage is scaled to fit the window with CSS `zoom`, so text and lines stay on whole device pixels at any size. Canvases keep a fixed 2× backing store. Pointer positions are mapped back to design pixels.
* **User settings.** In the CLAP plugin, a **Size** control (75–200%) resizes the window and is remembered, along with the page you were on. This goes through the `bridge:settings` channel that `tools/clap-patch.mjs` adds to the wrapper. Elsewhere nothing answers, and the control stays hidden.
* **No browser chrome.** The web view's own context menu, its shortcuts (Ctrl+R, Ctrl+P, F5, Ctrl+F…) and Ctrl+wheel zoom are blocked.
* **Host parameter menu.** A double right-click on a slider, or on a knob that is one parameter, opens the host's menu for it (in FL Studio: Create automation clip, Link to controller…).
* **Fast startup and no idle repaint.** Parameters load in one `requestFullStoredState` round trip. The GUI repaints only when something changed, and only the page on show is drawn.

## What the measurements showed

* **Seeding matters.** Seeded on the trivial state with spots, the ring freezes into static patterns or dies almost everywhere. Seeding on the homogeneous state makes the resonance available.
* **Diffusion is a short transmission line at audio rates.** The skin depth is $\sqrt{2D/\omega}$ ≈ 3–4 nodes, so Pickup distance spans 0–12 nodes, and the level match makes up the lost gain.
* **The resonance lives in a band.** Long rings and self-oscillation hug the Hopf curve; elsewhere the ring stops within ~50 ms of the input ending. Color keeps you on that band, and Ring and Resonance supply the decay that F and K alone only give in a sliver of the plane.
* **Dv/Du = 1 for a clean resonator.** Below it, a kick from the input settles the ring into a static Turing pattern, and static patterns are silent.

CPU: about 2.5% of one core at the defaults, at 44.1 or 48 kHz, and about 8% at Speed 4. That's the processor as the plugin compiles it (MSVC), in 64-frame blocks. Each extra sub-step adds one lattice pass. Parameter glides land exactly on their targets. A glide towards 0 would otherwise end in denormals, and with Resonance at 0 that doubled the cost.

## Known limitations

* Decay times are accurate to within the presets test's resolution (×3), and best between ~0.2 and 3 s. Near the edge of oscillation, effects the arithmetic leaves out (spatial modes, the anti-damping's saturation) decide the exact length. That's why Ring skips the sliver between Resonance 0.97 and 1.05.
* Near the saddle-node curve, the steady state is a node (real eigenvalues) rather than a focus, and Resonance's normalisation, which assumes a focus, doesn't hold: the ring can self-oscillate from Resonance ~0.5.
* The response plot and the level prediction are the linearised ring. Loud input lowers and widens the peak, and the learned trim covers the difference in level.
* Regions above the saddle-node curve ("Spots", "Solitons", "Silent") have no focus: no pitch, and short-lived responses. The Play page says so.
* The phase-plane overlay was measured at the default Diffusion, Dv/Du and Speed; other settings shift the boundaries somewhat.
* `cmaj render` drops roughly the first 0.4 s of an input file, so the render tools lead with one second of silence.
