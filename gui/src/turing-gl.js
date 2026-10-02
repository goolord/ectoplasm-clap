// A 2D Gray-Scott culture for the Play page, simulated on the GPU (WebGL 2), with a small CPU
// fallback where float render targets aren't available. TuringDish.res is the typed wrapper.
//
// The culture runs on the plugin's own F and K, with a pattern-forming diffusion ratio (Dv/Du =
// 0.2, Karl Sims' 9-point Laplacian), inside a disc. At 0.2 the homogeneous state is Turing-
// unstable all along the Play page's Color band, so it forms labyrinths and spots there; at
// 0.5 (the usual choice) it doesn't, and the dish fills with a featureless sheet. The plugin's 128-node ring is drawn as a
// circle through it: where the ring is active, the culture's blobs on that circle light up, and
// the activity is fed into the culture there, so playing reshapes the pattern along the ring.
// A few spots are sprinkled in every few seconds, so a culture that died out (in a regime where
// nothing grows) can come back when the chemistry changes.

const GRID = 300; // GPU culture, cells across
const CPU_GRID = 80; // fallback culture
const DU = 0.6;
const DV = 0.12;
const RING = 0.36; // radius of the resonator ring, as a fraction of the dish (0.5 = rim)
const CELLS = 128;
const THRESHOLD = 0.24; // V above which a point is "culture" (the pattern's ridges)

const hex = (rgb) => rgb.map((c) => c / 255);

const VERTEX = `#version 300 es
in vec2 position;
out vec2 uv;
void main() { uv = position * 0.5 + 0.5; gl_Position = vec4(position, 0.0, 1.0); }`;

const STEP = `#version 300 es
precision highp float;
uniform sampler2D state;
uniform sampler2D activity;
uniform float feed, kill, inject;
uniform vec3 spots[8];
uniform int spotCount;
out vec4 result;

float activityAt(float turn) {
  float x = turn * ${CELLS}.0 - 0.5;
  int i0 = int(floor(x));
  float t = x - floor(x);
  float a = texelFetch(activity, ivec2((i0 + ${CELLS}) % ${CELLS}, 0), 0).r;
  float b = texelFetch(activity, ivec2((i0 + 1 + ${CELLS}) % ${CELLS}, 0), 0).r;
  return mix(a, b, t);
}

void main() {
  ivec2 p = ivec2(gl_FragCoord.xy);
  ivec2 hi = textureSize(state, 0) - 1;
  #define S(dx, dy) texelFetch(state, clamp(p + ivec2(dx, dy), ivec2(0), hi), 0).rg
  vec2 c = S(0, 0);
  vec2 lap = 0.2 * (S(-1, 0) + S(1, 0) + S(0, -1) + S(0, 1))
           + 0.05 * (S(-1, -1) + S(1, -1) + S(-1, 1) + S(1, 1)) - c;
  float u = c.r, v = c.g, uvv = u * v * v;
  u += ${DU} * lap.r - uvv + feed * (1.0 - u);
  v += ${DV} * lap.g + uvv - (feed + kill) * v;

  vec2 d = (vec2(p) + 0.5) / vec2(textureSize(state, 0)) - 0.5;
  float r = length(d);
  // the ring's activity, fed in along its circle
  float turn = fract(atan(d.x, d.y) / 6.2831853);
  float band = exp(-pow((r - ${RING}) / 0.012, 2.0));
  v += inject * activityAt(turn) * band;
  // new spots
  for (int i = 0; i < 8; i++) {
    if (i >= spotCount) break;
    if (distance(d, spots[i].xy) < spots[i].z) { u = 0.5; v = 0.25; }
  }
  if (r > 0.49) { u = 1.0; v = 0.0; }
  result = vec4(clamp(u, 0.0, 1.0), clamp(v, 0.0, 1.0), 0.0, 1.0);
}`;

const SHOW = `#version 300 es
precision highp float;
in vec2 uv;
uniform sampler2D state;
uniform sampler2D activity;
uniform float level;
uniform vec3 ground, panel, rim, culture, glowColour;
out vec4 colour;

float activityAt(float turn) {
  float x = turn * ${CELLS}.0 - 0.5;
  int i0 = int(floor(x));
  float t = x - floor(x);
  float a = texelFetch(activity, ivec2((i0 + ${CELLS}) % ${CELLS}, 0), 0).r;
  float b = texelFetch(activity, ivec2((i0 + 1 + ${CELLS}) % ${CELLS}, 0), 0).r;
  return mix(a, b, t);
}

float field(vec2 at) {
  // bilinear by hand, so float textures needn't be filterable
  vec2 size = vec2(textureSize(state, 0));
  vec2 x = at * size - 0.5;
  ivec2 i = ivec2(floor(x));
  vec2 t = x - floor(x);
  ivec2 hi = ivec2(size) - 1;
  float a = texelFetch(state, clamp(i, ivec2(0), hi), 0).g;
  float b = texelFetch(state, clamp(i + ivec2(1, 0), ivec2(0), hi), 0).g;
  float c = texelFetch(state, clamp(i + ivec2(0, 1), ivec2(0), hi), 0).g;
  float e = texelFetch(state, clamp(i + ivec2(1, 1), ivec2(0), hi), 0).g;
  return mix(mix(a, b, t.x), mix(c, e, t.x), t.y);
}

void main() {
  vec2 d = uv - 0.5;
  float r = length(d);
  float edge = fwidth(r);
  float v = field(uv);
  float w = fwidth(v) + 0.002;
  float blob = smoothstep(${THRESHOLD} - w, ${THRESHOLD} + w, v);

  vec3 col = mix(ground, culture * (0.78 + 0.35 * level), blob);
  // where the ring is ringing, its blobs light up, with a faint halo around them
  float a = clamp(activityAt(fract(atan(d.x, d.y) / 6.2831853)), 0.0, 1.0);
  float band = exp(-pow((r - ${RING}) / 0.028, 2.0));
  col = mix(col, glowColour, a * band * blob);
  col += glowColour * a * band * (1.0 - blob) * 0.22;
  // the ring itself, faintly
  col += rim * 0.35 * exp(-pow((r - ${RING}) / (0.0025 + edge), 2.0));

  // dish rim and the panel outside it
  float inside = 1.0 - smoothstep(0.495 - edge, 0.495 + edge, r);
  float rimLine = exp(-pow((r - 0.497) / (0.003 + edge), 2.0));
  col = mix(panel, col, inside) + rim * rimLine * 0.6;
  colour = vec4(col, 1.0);
}`;

function compile(gl, type, source) {
  const shader = gl.createShader(type);
  gl.shaderSource(shader, source);
  gl.compileShader(shader);
  if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(shader));
  return shader;
}

function program(gl, fragment) {
  const p = gl.createProgram();
  gl.attachShader(p, compile(gl, gl.VERTEX_SHADER, VERTEX));
  gl.attachShader(p, compile(gl, gl.FRAGMENT_SHADER, fragment));
  gl.bindAttribLocation(p, 0, "position");
  gl.linkProgram(p);
  if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
  const uniforms = {};
  const count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
  for (let i = 0; i < count; i++) {
    const name = gl.getActiveUniform(p, i).name.replace(/\[0\]$/, "");
    uniforms[name] = gl.getUniformLocation(p, name);
  }
  return { p, uniforms };
}

// Initial culture: the trivial state with spots scattered through the disc, plus a little noise
// everywhere — a Turing instability needs something to grow from, and a perfectly clean field
// (as on the CPU) just fills in uniformly.
function seedState(n, random) {
  const data = new Float32Array(n * n * 4);
  for (let i = 0; i < n * n; i++) { data[i * 4] = 1 - 0.02 * random(); data[i * 4 + 1] = 0.02 * random(); data[i * 4 + 3] = 1; }
  const spots = Math.round(n * n / 700);
  for (let s = 0; s < spots; s++) {
    const a = random() * Math.PI * 2, rr = Math.sqrt(random()) * 0.45;
    const cx = Math.round((0.5 + rr * Math.sin(a)) * n), cy = Math.round((0.5 + rr * Math.cos(a)) * n);
    const size = 1 + Math.round(random() * n / 100);
    for (let y = cy - size; y <= cy + size; y++) for (let x = cx - size; x <= cx + size; x++) {
      if (x < 0 || y < 0 || x >= n || y >= n) continue;
      const i = (y * n + x) * 4;
      data[i] = 0.5; data[i + 1] = 0.25 + 0.05 * random();
    }
  }
  return data;
}

function makeRandom(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}

function createGpu(canvas, colours) {
  const gl = canvas.getContext("webgl2", { antialias: false, premultipliedAlpha: false, preserveDrawingBuffer: false });
  if (!gl || !gl.getExtension("EXT_color_buffer_float")) return null;

  const step = program(gl, STEP);
  const show = program(gl, SHOW);
  const quad = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

  const random = makeRandom(7);
  const texture = (w, h, format, internal, data) => {
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, internal, w, h, 0, format, gl.FLOAT, data);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.NEAREST], [gl.TEXTURE_MAG_FILTER, gl.NEAREST],
                          [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]])
      gl.texParameteri(gl.TEXTURE_2D, k, v);
    return t;
  };
  const seed = seedState(GRID, random);
  const states = [texture(GRID, GRID, gl.RGBA, gl.RGBA32F, seed), texture(GRID, GRID, gl.RGBA, gl.RGBA32F, seed)];
  const frames = states.map((t) => {
    const f = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, f);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, t, 0);
    return f;
  });
  if (gl.checkFramebufferStatus(gl.FRAMEBUFFER) !== gl.FRAMEBUFFER_COMPLETE) return null;
  const activityTexture = texture(CELLS, 1, gl.RED, gl.R32F, new Float32Array(CELLS));
  let current = 0;
  let pendingSpots = [];

  return {
    gpu: true,
    setActivity(values) {
      gl.bindTexture(gl.TEXTURE_2D, activityTexture);
      gl.texSubImage2D(gl.TEXTURE_2D, 0, 0, 0, CELLS, 1, gl.RED, gl.FLOAT, values);
    },
    sprinkle(count) {
      for (let i = 0; i < count; i++) {
        const a = random() * Math.PI * 2, rr = Math.sqrt(random()) * 0.44;
        pendingSpots.push([rr * Math.sin(a), rr * Math.cos(a), 0.006 + random() * 0.01]);
      }
    },
    step(steps, feed, kill, inject) {
      gl.useProgram(step.p);
      gl.viewport(0, 0, GRID, GRID);
      gl.uniform1f(step.uniforms.feed, feed);
      gl.uniform1f(step.uniforms.kill, kill);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, activityTexture);
      gl.uniform1i(step.uniforms.activity, 1);
      gl.uniform1i(step.uniforms.state, 0);
      for (let s = 0; s < steps; s++) {
        const spots = s === 0 ? pendingSpots.splice(0, 8) : [];
        gl.uniform1i(step.uniforms.spotCount, spots.length);
        if (spots.length) gl.uniform3fv(step.uniforms.spots, new Float32Array(spots.flat().concat(new Array((8 - spots.length) * 3).fill(0))));
        gl.uniform1f(step.uniforms.inject, s === 0 ? inject : 0);
        gl.activeTexture(gl.TEXTURE0);
        gl.bindTexture(gl.TEXTURE_2D, states[current]);
        gl.bindFramebuffer(gl.FRAMEBUFFER, frames[1 - current]);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        current = 1 - current;
      }
    },
    render(level) {
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
      gl.viewport(0, 0, canvas.width, canvas.height);
      gl.useProgram(show.p);
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, states[current]);
      gl.uniform1i(show.uniforms.state, 0);
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, activityTexture);
      gl.uniform1i(show.uniforms.activity, 1);
      gl.uniform1f(show.uniforms.level, level);
      for (const name of ["ground", "panel", "rim", "culture", "glowColour"]) gl.uniform3fv(show.uniforms[name], hex(colours[name]));
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    },
    dispose() {
      for (const t of [...states, activityTexture]) gl.deleteTexture(t);
      for (const f of frames) gl.deleteFramebuffer(f);
      gl.deleteBuffer(quad);
      gl.deleteProgram(step.p);
      gl.deleteProgram(show.p);
      gl.getExtension("WEBGL_lose_context")?.loseContext();
    },
  };
}

// The same culture on the CPU, coarser, for web views without float render targets.
function createCpu(canvas, colours) {
  const ctx = canvas.getContext("2d");
  const n = CPU_GRID;
  const random = makeRandom(7);
  const seed = seedState(n, random);
  let u = new Float32Array(n * n), v = new Float32Array(n * n);
  for (let i = 0; i < n * n; i++) { u[i] = seed[i * 4]; v[i] = seed[i * 4 + 1]; }
  let u2 = new Float32Array(n * n), v2 = new Float32Array(n * n);
  let activity = new Float32Array(CELLS);
  const small = document.createElement("canvas");
  small.width = small.height = n;
  const smallCtx = small.getContext("2d");
  const image = smallCtx.createImageData(n, n);
  const radius = new Float32Array(n * n), turn = new Float32Array(n * n);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const dx = (x + 0.5) / n - 0.5, dy = 0.5 - (y + 0.5) / n;
    radius[y * n + x] = Math.hypot(dx, dy);
    turn[y * n + x] = ((Math.atan2(dx, dy) / (2 * Math.PI)) + 1) % 1;
  }
  const activityAt = (t) => {
    const x = t * CELLS - 0.5, i0 = Math.floor(x), f = x - i0;
    return activity[(i0 + CELLS) % CELLS] * (1 - f) + activity[(i0 + 1) % CELLS] * f;
  };
  let pendingSpots = [];
  const mixc = (a, b, t) => a + (b - a) * t;
  return {
    gpu: false,
    setActivity(values) { activity = values; },
    sprinkle(count) {
      for (let i = 0; i < count; i++) {
        const a = random() * Math.PI * 2, rr = Math.sqrt(random()) * 0.44;
        pendingSpots.push([rr * Math.sin(a), rr * Math.cos(a), 0.02]);
      }
    },
    step(steps, feed, kill, inject) {
      // the same chemistry and 9-point stencil as the GPU, on a coarser grid (chunkier pattern)
      const at = (x, y) => Math.min(n - 1, Math.max(0, y)) * n + Math.min(n - 1, Math.max(0, x));
      for (let s = 0; s < Math.max(1, Math.round(steps / 2)); s++) {
        for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
          const i = y * n + x;
          if (radius[i] > 0.49) { u2[i] = 1; v2[i] = 0; continue; }
          const edges = [at(x - 1, y), at(x + 1, y), at(x, y - 1), at(x, y + 1)];
          const corners = [at(x - 1, y - 1), at(x + 1, y - 1), at(x - 1, y + 1), at(x + 1, y + 1)];
          let lu = -u[i], lv = -v[i];
          for (const j of edges) { lu += 0.2 * u[j]; lv += 0.2 * v[j]; }
          for (const j of corners) { lu += 0.05 * u[j]; lv += 0.05 * v[j]; }
          const uvv = u[i] * v[i] * v[i];
          const nu = u[i] + DU * lu - uvv + feed * (1 - u[i]);
          let nv = v[i] + DV * lv + uvv - (feed + kill) * v[i];
          if (s === 0) nv += inject * activityAt(turn[i]) * Math.exp(-(((radius[i] - RING) / 0.02) ** 2));
          u2[i] = Math.min(1, Math.max(0, nu)); v2[i] = Math.min(1, Math.max(0, nv));
        }
        [u, u2] = [u2, u]; [v, v2] = [v2, v];
      }
      for (const [sx, sy, sr] of pendingSpots.splice(0)) for (let i = 0; i < n * n; i++) {
        const dx = (i % n + 0.5) / n - 0.5 - sx, dy = 0.5 - (Math.floor(i / n) + 0.5) / n - sy;
        if (dx * dx + dy * dy < sr * sr) { u[i] = 0.5; v[i] = 0.25; }
      }
    },
    render(level) {
      const g = colours.ground, c = colours.culture, l = colours.glowColour, p = colours.panel;
      for (let i = 0; i < n * n; i++) {
        const blob = Math.min(1, Math.max(0, (v[i] - THRESHOLD + 0.03) / 0.06));
        const a = Math.min(1, activityAt(turn[i])) * Math.exp(-(((radius[i] - RING) / 0.035) ** 2));
        const outside = radius[i] > 0.495;
        for (let ch = 0; ch < 3; ch++) {
          let x = mixc(g[ch], c[ch] * (0.78 + 0.35 * level), blob);
          x = mixc(x, l[ch], a * blob);
          image.data[i * 4 + ch] = outside ? p[ch] : x;
        }
        image.data[i * 4 + 3] = 255;
      }
      smallCtx.putImageData(image, 0, 0);
      ctx.imageSmoothingEnabled = true;
      ctx.drawImage(small, 0, 0, canvas.width, canvas.height);
    },
    dispose() {},
  };
}

export function createCulture(canvas, colours) {
  try {
    const gpu = createGpu(canvas, colours);
    if (gpu) return gpu;
  } catch (e) {
    console.warn("Ectoplasm: the GPU culture didn't start, using the CPU one", e);
  }
  // a canvas that had a WebGL context can't give a 2D one, so the fallback gets a fresh canvas
  const fresh = document.createElement("canvas");
  fresh.width = canvas.width;
  fresh.height = canvas.height;
  fresh.className = canvas.className;
  fresh.style.cssText = canvas.style.cssText;
  canvas.replaceWith?.(fresh);
  const culture = createCpu(fresh, colours);
  culture.canvas = fresh;
  return culture;
}
