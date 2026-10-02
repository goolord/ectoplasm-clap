# Gray-Scott Resonator

A stereo audio effect built on a 1D Gray-Scott reaction-diffusion ring of 128 nodes, integrated at audio rate in Cmajor. Incoming audio is injected into chemical V at two points on the ring, and two pickups read V back out as audio. Depending on where you put the feed and kill rates, the ring acts as a tuned resonator, a self-oscillating drone, a pattern-forming texture machine, or a chaotic noise source.

The GUI is written in ReScript. It has an F×K phase-plane controller and a live view of the lattice.

## Files

| Path | What it is |
|---|---|
| `dsp/GrayScottResonator.cmajor` | The DSP processor |
| `plugin.cmajorpatch` | Patch manifest; its `name` names the built plugin, and it points the view at `gui/dist/index.js` |
| `justfile` | Build, install, test and preview recipes (from the nano-clap template) |
| `STABILITY.md` | Stable parameter bounds and why the lattice can't produce NaN/Inf, including notes for a fixed-point port |
| `gui/src/CmajorBindings.res` | Typed `PatchConnection` bindings, the `Param` model, and the glitch-free `Bridge` |
| `gui/src/PhasePlot.res` | F×K phase-plane controller |
| `gui/src/LatticeView.res` | Kymograph and V-profile visualiser with draggable pickups |
| `gui/src/GrayScottApp.res` | App shell: layout, styles, rAF loop, wiring |
| `gui/src/GrayScottGui.res` | Entry point (`export default createPatchView`) and lifecycle |
| `gui/src/GrayScottTheory.res` | Analytic curves (saddle-node, Hopf), resonance estimate, region classifier |
| `gui/src/MeasuredMap.res` | Generated: measured response of the processor across F×K |
| `gui/src/Controls.res`, `Palette.res`, `Web.res` | Sliders, colour tokens, minimal DOM/Canvas bindings |
| `gui/dist/index.js` | Bundled GUI (built by `just ui`; the patch loads this) |
| `tools/measure-map.mjs` | Renders the processor across the F×K plane with `cmaj render` |
| `tools/gen-measured-map.mjs` | Turns that measurement into `MeasuredMap.res` |
| `tools/gui-harness.html`, `tools/serve.mjs` | Run the GUI in a browser against a mock host (no audio) |
| `tools/test/stability.mjs` | Stress renders at the parameter extremes and three sample rates; fails on any non-finite sample |
| `tools/clap-patch.mjs`, `tools/clap/*.h`, `tools/sync-dir.mjs`, `tools/manifest.mjs`, `tools/test/plugin.mjs` | From nano-clap, unchanged: patches Cmajor's CLAP wrapper, syncs the generated project, reads the manifest, renders the whole plugin |
| `tools/rename.mjs` | Changes the plugin's name and IDs (adapted from nano-clap) |

## Build and run

Requirements: [just](https://github.com/casey/just), `cmaj`, node and npm, git, cmake ≥ 3.16 and a C++17 compiler (on Windows, Visual Studio 2022 with the C++ workload).

```bash
just
```

That builds `dist/Gray-Scott Resonator.clap`. The steps are: install npm packages if they're missing, build the GUI, fetch the CLAP headers (once), generate the CLAP project with `cmaj generate`, patch its wrapper (`tools/clap-patch.mjs`), then compile with CMake.

| Recipe | What it does |
|---|---|
| `just install` | Build, then copy into the CLAP folder. On Windows that's the system folder, which raises a UAC prompt |
| `just uninstall` | Remove it again |
| `just play` | Run the patch in Cmajor's player |
| `just preview` | Serve the GUI against a mock host at `http://127.0.0.1:5178/tools/gui-harness.html` (no audio) |
| `just test` | Stress-render the lattice (`just test chaos` filters cases by name), then render the whole plugin |
| `just measure` | Re-measure the F×K map after changing the DSP and rebuild the phase plane's dot field |
| `just ui` | Rebuild only the GUI bundle |
| `just rename "Name" com.you.id` | Change the plugin's name, ID and four-letter codes |
| `just clean` | Delete `build/`, `dist/` and the compiled GUI |

`CONFIG=Debug just` builds a debug plugin, and `CMAJ_PLUGIN_PERF=1` in a host's environment logs per-instance CPU time (see `tools/clap-patch.mjs`).

The built binary is `build/out/GrayScottResonator.clap`. Cmajor names the CMake target after the manifest name with non-alphanumerics removed, so the justfile copies it to `dist/` under the display name. nano-clap's justfile assumed the two match, which only holds for names like `NanoClap`.

## Parameters

| Parameter | Range | What it does |
|---|---|---|
| Feed F | 0.010–0.090 | Gray-Scott feed rate |
| Kill K | 0.045–0.070 | Gray-Scott kill rate |
| Diffusion | 0.05–0.50 | $D_u$. Higher couples nodes more strongly and carries signal further |
| Dv / Du | 0.10–1.00 | Diffusion ratio. Below about 0.7, Turing patterns (stripes and spots) can form; at 1.0 the ring behaves as a pure resonator |
| Speed | 0.05–4× (log) | Lattice time per sample. Scales every frequency the ring produces |
| Drive | 0–24 dB | Input gain before the tanh saturator that feeds the injectors |
| Pickup distance | 0–100% | 0–12 nodes from each injector. Further away is darker and more of the lattice's own motion |
| Resonance | 0–1.5 | Cross-coupled feedback, L pickup to R injector and vice versa. Like a resonant filter: about 1 is where the default focus starts sustaining itself; below that it rings and decays (default 0.5) |
| Mix | 0–100% | Dry/wet (default 100%) |
| Output | −36 to +12 dB | Output gain |

`reseed` is a non-host event endpoint (the GUI's *Reseed lattice* button) that reinitialises the ring for the current F/K.

## How it works

**Integration.** The processor uses explicit Euler on a 3-point ring Laplacian, updated in place with one register for the left neighbour. Speed is split into ⌈speed⌉ sub-steps (up to 8), each with dt ≤ 1, and time runs on a fixed 48 kHz base, so pitch doesn't change with the host sample rate. With $D_u$ ≤ 0.5 and dt ≤ 1, the diffusion step is monotone. `STABILITY.md` has the full derivation.

**Why it resonates.** Below the saddle-node curve $K = \sqrt F/2 - F$ the reaction has a homogeneous state $(U^*, V^*)$. Between the Hopf curve $F + K = \sqrt F K^{1/4}$ and the saddle-node curve, that state is a stable focus. Perturbations ring at $\omega = \sqrt{\det J - (\operatorname{tr} J)^2/4}$, around 300–700 Hz at Speed 1, with Q going to infinity at the Hopf curve. The processor puts the ring exactly on that state when it exists (on the trivial state U=1, V=0 when it doesn't), with no seed noise or dither. Both are equilibria, so with no input there is nothing to hear: every sound starts from the input. If the ring collapses to the trivial state while there is input, it is re-seeded with a fade. Left of the Hopf curve, and at Resonance ≳ 1, it keeps oscillating once disturbed. The GUI phase plane draws both curves and shows the predicted ring frequency and Q for the current point.

**I/O.** Audio is soft-saturated (tanh) and splatted into V with a cubic B-spline kernel. Pickups read V through the same kernel. It sums to 1, is C² and acts as a spatial low-pass, so moving a pickup is click-free and the lattice's Nyquist mode is attenuated. The wet path is DC-blocked (8 Hz), low-passed (Butterworth, 16 kHz) and given a fixed gain. That signal, tanh-limited, is what Resonance feeds back. The output takes it through a level match first: how loudly the lattice answers varies by ~40 dB across the F×K plane, so the wet level is compared with the input's over about half a second and boosted (never cut, at most +30 dB) to match. The match only moves while there is input, so it can't lift noise, stretch tails or pump.

An earlier version used an AGC here, inside the feedback loop, and it pumped. It raised the loop gain whenever things went quiet, which turned the ring into a relaxation oscillator that clicked on its own clock (every 0.25–0.3 s, with or without input), and it lifted the dither into a hum when nothing was playing. Keeping the loop gain fixed and the level match outside the loop removes both.

**Parameter transport.** `Bridge.set` clamps to the declared range, then coalesces writes to one message per endpoint per animation frame. Drags are bracketed with `sendParameterGestureStart/End`, and host echoes for a parameter mid-gesture are ignored. On the DSP side, every parameter glides over about 25 ms.

## GUI host quirks

These come from nano-clap's view shell (`ui/core/Shell.res`, `BrowserChrome.res`, `HostMenu.res`, `Settings.res`):

* **Isolated styles.** The view renders into a shadow root. Its `:host` rule overrides the inline size Cmajor puts on the view, so the stage can scale with the window.
* **Scaling.** The 880×560 stage is scaled to fit the window and centred. It uses CSS `zoom`, which re-lays out text and lines on whole device pixels, so nothing blurs at 125% or 150%. Canvases keep a fixed 2× backing store, so they stay sharp at any DPI. Pointer positions are mapped back to design pixels, so drags land where you click at any size.
* **Interface size.** In the CLAP plugin a **Size** control (75–200%) asks the host to resize the window, and new windows open at that size. It goes through the `bridge:settings` channel that `tools/clap-patch.mjs` adds to the wrapper. In `cmaj play` and the harness nothing answers, so the control stays hidden.
* **No browser chrome.** The web view's own context menu (back, reload, print), its shortcuts (Ctrl+R, Ctrl+P, F5, Ctrl+F…) and Ctrl+wheel page zoom are blocked.
* **Host parameter menu.** A double right-click on a slider opens the host's own menu for that parameter, for example FL Studio's "Create automation clip" or "Link to controller". The next press or Escape in the view closes it, which Windows needs.
* **Fast startup.** Parameters load in one `requestFullStoredState` round trip instead of one request per parameter.
* **No idle repaint.** The GUI repaints only when something changed (a lattice snapshot at 30 Hz, a moved control), never on a free-running animation loop.

## What the measurements showed

Before tuning, the processor was rendered offline across the F×K plane (`tools/measure-map.mjs`). Findings that shaped the design:

* **Seeding matters.** Seeded on the trivial state (U=1, V=0) with spots, the ring freezes into static Turing patterns or dies almost everywhere, and is silent after the DC blocker. The trivial state is linearly stable for every F and K. Seeding on the homogeneous state is what makes the resonance available.
* **Diffusion is a short transmission line at audio rates.** The skin depth is $\sqrt{2D/\omega}$ ≈ 3–4 nodes. A pickup 16 nodes from its injector hears about e⁻⁶ of the signal, so Pickup distance spans 0–12 nodes, and the level match makes up the lost gain.
* **The measured map matches the theory.** Long rings and self-oscillation hug the Hopf curve, with pockets along the saddle-node curve; everywhere else stops dead within ~50 ms of the input ending. That is why the interesting settings are narrow bands. The GUI overlays the measured ring time (dot size, with rings for self-oscillation) on the analytic regions.

CPU: about 2% of one core at Speed 1 (measured on the built .clap, 64-frame blocks at 48 kHz, worst block under 0.1 ms of its 1.33 ms budget). Each extra Speed step adds one lattice pass.

Verification: 693 F×K cells plus corner stress tests (Speed 0.05/4, Drive 24 dB, Resonance 1.5, Dv/Du 0.1) at 44.1, 48 and 96 kHz produced 0 non-finite samples. The resonant focus measured 445 / 449 / 478 Hz at 44.1 / 48 / 96 kHz against a predicted 426 Hz.

## Known limitations

* Regions above the saddle-node curve ("Spots", "Solitons", "Silent") are quiet. There is no resonant state there, and the input mostly triggers short-lived localised structures. That is the chemistry, not a bug, and the phase plane shows it.
* The region names follow Pearson's 2D taxonomy as a guide. In a 1D ring, "Spots" and "Stripes" both show up as stationary bands in the kymograph.
* The phase-plane dot overlay was measured at the default Diffusion, Dv/Du and Speed. Other settings shift the boundaries somewhat.
* `cmaj render` drops roughly the first 0.4 s of an input file, so the measurement and stability tools lead with one second of silence.
