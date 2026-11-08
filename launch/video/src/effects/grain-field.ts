import {createEffect, type InteractivitySchema} from 'remotion';

/**
 * A procedural "light sweep" background: a diagonal beam of blue and white
 * light with a warm under-glow, finished with an ordered-dither grain. It is the
 * Steadfast take on the grainy aurora plates used in Apple-style launch films.
 * It ignores its source and paints the full target, so put it on a <Solid>.
 */
type GrainFieldParams = {
  readonly time?: number; // seconds, drives the drift
  readonly seed?: number;
  readonly warm?: number; // 0…1, amount of orange under-glow
  readonly exposure?: number; // 0…2, overall brightness
  readonly angle?: number; // beam angle in radians
  readonly offset?: number; // beam position across the frame, -1…1
  readonly grain?: number; // 0…1
  readonly dot?: number; // dither cell size in px
};

type State = {
  readonly gl: WebGL2RenderingContext;
  readonly program: WebGLProgram;
  readonly vao: WebGLVertexArrayObject;
  readonly vbo: WebGLBuffer;
  readonly u: Record<string, WebGLUniformLocation | null>;
};

const schema = {
  time: {type: 'number', min: 0, max: 600, step: 0.01, default: 0, description: 'Time', hiddenFromList: false},
  seed: {type: 'number', min: 0, max: 100, step: 0.1, default: 0, description: 'Seed', hiddenFromList: false},
  warm: {type: 'number', min: 0, max: 1, step: 0.01, default: 0.6, description: 'Warm glow', hiddenFromList: false},
  exposure: {type: 'number', min: 0, max: 2, step: 0.01, default: 1, description: 'Exposure', hiddenFromList: false},
  angle: {type: 'number', min: -3.2, max: 3.2, step: 0.01, default: -0.42, description: 'Beam angle', hiddenFromList: false},
  offset: {type: 'number', min: -1, max: 1, step: 0.01, default: 0, description: 'Beam offset', hiddenFromList: false},
  grain: {type: 'number', min: 0, max: 1, step: 0.01, default: 0.5, description: 'Grain', hiddenFromList: false},
  dot: {type: 'number', min: 1, max: 8, step: 0.5, default: 2.5, description: 'Dither cell', hiddenFromList: false},
} as const satisfies InteractivitySchema;

const resolve = (p: GrainFieldParams) => ({
  time: p.time ?? 0,
  seed: p.seed ?? 0,
  warm: p.warm ?? 0.6,
  exposure: p.exposure ?? 1,
  angle: p.angle ?? -0.42,
  offset: p.offset ?? 0,
  grain: p.grain ?? 0.5,
  dot: p.dot ?? 2.5,
});

const VERT = `#version 300 es
in vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }`;

const FRAG = `#version 300 es
precision highp float;
uniform vec2 uRes;
uniform float uTime, uSeed, uWarm, uExposure, uAngle, uOffset, uGrain, uDot;
out vec4 outColor;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
  return v;
}
float bayer4(vec2 p) {
  int x = int(mod(p.x, 4.0)), y = int(mod(p.y, 4.0));
  int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return float(m[y * 4 + x]) / 16.0;
}
void main() {
  vec2 uv = gl_FragCoord.xy / uRes;
  vec2 p = (gl_FragCoord.xy - 0.5 * uRes) / uRes.y;
  float t = uTime;
  float c = cos(uAngle), s = sin(uAngle);
  vec2 q = mat2(c, -s, s, c) * p;
  q.y -= uOffset * 0.5;

  // domain-warped streaks running along the beam
  vec2 w = vec2(fbm(q * vec2(0.9, 2.6) + vec2(t * 0.07, 0.0) + uSeed),
                fbm(q * vec2(0.9, 2.6) - vec2(0.0, t * 0.05) + uSeed + 3.7));
  float streak = fbm(vec2(q.x * 0.7 + w.x * 0.9 - t * 0.12, q.y * 5.2 + w.y * 1.6) + uSeed * 1.3);
  float bend = 0.10 * sin(q.x * 1.7 + t * 0.35 + uSeed) + 0.18 * (w.y - 0.5);
  float beam = exp(-pow((q.y - bend) * 3.1, 2.0));
  float core = exp(-pow((q.y - bend * 0.8) * 9.0, 2.0)) * smoothstep(-1.1, 0.5, q.x);
  float lum = clamp(beam * 0.78 + core * 0.45 + (streak - 0.5) * 1.25 * (0.35 + beam), 0.0, 1.2) * uExposure;

  vec3 night = vec3(0.004, 0.010, 0.045);
  vec3 deep  = vec3(0.004, 0.050, 0.420);
  vec3 blue  = vec3(0.039, 0.212, 0.992);
  vec3 sky   = vec3(0.520, 0.700, 1.000);
  vec3 white = vec3(0.985, 0.985, 1.000);
  vec3 warm  = vec3(1.000, 0.430, 0.130);
  vec3 ember = vec3(0.900, 0.160, 0.060);

  vec3 col = mix(night, deep, smoothstep(0.02, 0.28, lum));
  col = mix(col, blue, smoothstep(0.22, 0.55, lum));
  col = mix(col, sky, smoothstep(0.55, 0.82, lum));
  col = mix(col, white, smoothstep(0.80, 1.05, lum));

  float wf = fbm(q * 1.3 + vec2(-t * 0.06, t * 0.04) + uSeed * 2.0);
  float warmMask = smoothstep(0.48, 0.80, wf) * smoothstep(-0.05, 0.35, -q.y + 0.25) * uWarm;
  col = mix(col, mix(ember, warm, smoothstep(0.3, 0.8, lum)), warmMask * smoothstep(0.08, 0.55, lum) * 0.95);

  // vignette
  col *= mix(0.55, 1.0, smoothstep(1.25, 0.25, length(p * vec2(0.9, 1.15))));

  // ordered dither + film grain, quantised to a coarse cell like a halftone screen
  vec2 cell = floor(gl_FragCoord.xy / uDot);
  float frameSeed = floor(t * 24.0);
  float g = hash(cell + frameSeed * 17.31) - 0.5;
  float d = bayer4(cell) - 0.5;
  col += (d * 0.10 + g * 0.08) * uGrain * (0.35 + 0.65 * smoothstep(0.0, 0.6, lum));

  outColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}`;

const compile = (gl: WebGL2RenderingContext, kind: number, src: string) => {
  const sh = gl.createShader(kind);
  if (!sh) throw new Error('grainField: could not create shader');
  gl.shaderSource(sh, src);
  gl.compileShader(sh);
  if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) {
    throw new Error(`grainField shader: ${gl.getShaderInfoLog(sh)}`);
  }
  return sh;
};

export const grainField = createEffect<GrainFieldParams, State>({
  type: 'app.steadfast.grainField',
  label: 'grainField()',
  documentationLink: null,
  backend: 'webgl2',
  calculateKey: (params) => {
    const r = resolve(params);
    return `grain-${r.time.toFixed(4)}-${r.seed}-${r.warm}-${r.exposure}-${r.angle}-${r.offset}-${r.grain}-${r.dot}`;
  },
  setup: (target) => {
    const gl = target.getContext('webgl2', {premultipliedAlpha: true, alpha: true, preserveDrawingBuffer: true});
    if (!gl) throw new Error('Could not get a WebGL2 context for grainField().');
    const program = gl.createProgram();
    if (!program) throw new Error('grainField: no program');
    gl.attachShader(program, compile(gl, gl.VERTEX_SHADER, VERT));
    gl.attachShader(program, compile(gl, gl.FRAGMENT_SHADER, FRAG));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
      throw new Error(`grainField link: ${gl.getProgramInfoLog(program)}`);
    }
    const vao = gl.createVertexArray();
    const vbo = gl.createBuffer();
    if (!vao || !vbo) throw new Error('grainField: buffers');
    gl.bindVertexArray(vao);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
    const loc = gl.getAttribLocation(program, 'aPos');
    gl.enableVertexAttribArray(loc);
    gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
    gl.bindVertexArray(null);
    const u: Record<string, WebGLUniformLocation | null> = {};
    for (const name of ['uRes', 'uTime', 'uSeed', 'uWarm', 'uExposure', 'uAngle', 'uOffset', 'uGrain', 'uDot']) {
      u[name] = gl.getUniformLocation(program, name);
    }
    return {gl, program, vao, vbo, u};
  },
  apply: ({width, height, params, state}) => {
    const r = resolve(params);
    const {gl, u} = state;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, width, height);
    gl.useProgram(state.program);
    gl.uniform2f(u.uRes, width, height);
    gl.uniform1f(u.uTime, r.time);
    gl.uniform1f(u.uSeed, r.seed);
    gl.uniform1f(u.uWarm, r.warm);
    gl.uniform1f(u.uExposure, r.exposure);
    gl.uniform1f(u.uAngle, r.angle);
    gl.uniform1f(u.uOffset, r.offset);
    gl.uniform1f(u.uGrain, r.grain);
    gl.uniform1f(u.uDot, r.dot);
    gl.bindVertexArray(state.vao);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    gl.bindVertexArray(null);
  },
  cleanup: ({gl, program, vao, vbo}) => {
    gl.deleteBuffer(vbo);
    gl.deleteVertexArray(vao);
    gl.deleteProgram(program);
  },
  schema,
  validateParams: (p) => {
    const r = resolve(p);
    for (const [k, v] of Object.entries(r)) {
      if (typeof v !== 'number' || !Number.isFinite(v)) throw new TypeError(`grainField: ${k} must be a finite number`);
    }
  },
});
