# Ectoplasm

A stereo resonator CLAP plugin built on a 1D Gray-Scott reaction-diffusion ring of 128 nodes, integrated at audio rate in Cmajor, with a ReScript GUI.

## Overview

* **DSP.** Explicit Euler on a 3-point ring Laplacian, sub-stepped (up to 8) so $D_u \cdot dt \le 0.5$, on a fixed 48 kHz time base. Nodes store U and V as offsets from the homogeneous steady state, so a ring decays to true silence. Between the Hopf and saddle-node curves that state is a stable focus, and the ring rings at its pitch.
* **Input/output.** Audio is tanh-saturated, scaled by Drive and splatted into V with a cubic B-spline kernel. Two pickups read V back through the same kernel. The wet path is DC-blocked, low-passed and level-matched: a linear-model prediction (recomputed only when a setting moves) plus a slow learned trim.
* **Resonance** is anti-damping inside the chemistry, g·A·d/(A + |d|) added to V, normalised so 1 is the discrete edge of self-oscillation. The saturation turns Gray-Scott's subcritical Hopf into a small stable limit cycle.
* **GUI.** *Play* page: macros (Pitch, Ring, Color) that solve for Speed and Resonance to hold a note and decay time, a response plot from the same level model, and a 2D Gray-Scott culture on WebGL 2. *Lab* page: the F×K phase plane and every parameter.
* **Build.** `just` builds `dist/Ectoplasm.clap` (needs just, `cmaj`, node, cmake ≥ 3.16, a C++17 compiler). `just test` runs the stability, preset and plugin tests; `just preview` serves the GUI against a mock host.

`STABILITY.md` has the parameter bounds and the derivation of why the lattice can't produce NaN/Inf.

## Files

| Path | What it is |
|---|---|
| `dsp/GrayScottResonator.cmajor` | The DSP processor |
| `plugin.cmajorpatch` | Patch manifest |
| `justfile` | Build, install, test and preview recipes |
| `gui/src/GrayScottApp.res` | App shell: pages, header, presets menu, parameter mirror |
| `gui/src/Macro.res` | Macros, focus arithmetic, pitch/ring solve, value parsers |
| `gui/src/LevelModel.res` | The processor's level model and sub-step rule, for the view |
| `gui/src/Presets.res` | Factory presets |
| `gui/src/Knob.res`, `ResponsePlot.res`, `TuringDish.res`, `turing-gl.js` | Play page widgets |
| `gui/src/PhasePlot.res`, `Controls.res`, `GrayScottTheory.res` | Lab page widgets and analytic curves |
| `gui/src/MeasuredMap.res` | Generated measured F×K map |
| `gui/src/LatticeView.res` | Kymograph and V-profile view with draggable pickups |
| `gui/src/CmajorBindings.res` | `PatchConnection` bindings, `Param` model, coalescing `Bridge` |
| `gui/src/BrowserChrome.res`, `HostChannel.res`, `HostMenu.res`, `Settings.res` | Web-view and host quirks (from nano-clap) |
| `gui/src/GrayScottGui.res`, `Palette.res`, `Web.res` | Entry point, colour tokens, DOM/Canvas bindings |
| `tools/test/*.mjs` | Stability, preset and plugin tests |
| `tools/measure-map.mjs`, `tools/gen-measured-map.mjs`, `tools/patch-source.mjs` | Measure the F×K map and generate `MeasuredMap.res` |
| `tools/gui-harness.html`, `tools/serve.mjs` | GUI in a browser against a mock host |
| `tools/clap-patch.mjs`, `tools/clap/*.h`, `tools/sync-dir.mjs`, `tools/manifest.mjs`, `tools/rename.mjs` | CLAP wrapper patching and packaging (from nano-clap) |

## Known limitations

* Decay times are accurate to within ×3, best between ~0.2 and 3 s. Ring skips Resonance 0.97–1.05, where effects the arithmetic leaves out decide the length.
* Near the saddle-node curve the steady state is a node, not a focus, and the ring can self-oscillate from Resonance ~0.5.
* The response plot and level prediction are the linearised ring; loud input lowers and widens the peak.
* Above the saddle-node curve there is no focus: no pitch, and short-lived responses.
* The phase-plane overlay was measured at default Diffusion, Dv/Du and Speed.
* Pitch is only a guide with Dv/Du below 1 (Turing patterns) or Drive above 9 dB (upper spatial modes).
* `cmaj render` drops roughly the first 0.4 s of input, so the render tools lead with a second of silence.
