'use strict';
/* Nav turns solid once the hero scrolls away. */
(() => {
  const nav = document.getElementById('nav');
  const hero = document.querySelector('.hero');
  const io = new IntersectionObserver(([e]) => nav.classList.toggle('solid', !e.isIntersecting), {rootMargin: '-60px 0px 0px 0px'});
  io.observe(hero);
  const scrolled = () => nav.classList.toggle('scrolled', scrollY > 8);
  scrolled(); addEventListener('scroll', scrolled, {passive: true});
})();

/* Copy the install command. */
(() => {
  const btn = document.getElementById('copy');
  const text = 'curl -fsSL https://github.com/kartikkabadi/steadfast/releases/latest/download/install.sh | /bin/bash';
  btn.addEventListener('click', async () => {
    try { await navigator.clipboard.writeText(text); btn.textContent = 'Copied'; }
    catch { const r = document.createRange(); r.selectNodeContents(document.getElementById('cmd')); const s = getSelection(); s.removeAllRanges(); s.addRange(r); btn.textContent = 'Press ⌘C'; }
    setTimeout(() => (btn.textContent = 'Copy'), 1800);
  });
  // Fade the command's edge only while some of it is out of view.
  const code = document.getElementById('cmd');
  const edge = () => code.classList.toggle('clipped', code.scrollLeft + code.clientWidth < code.scrollWidth - 1);
  edge(); addEventListener('resize', edge); code.addEventListener('scroll', edge, {passive: true});
})();

/* Film sound toggle. */
(() => {
  const v = document.getElementById('film');
  const b = document.getElementById('sound');
  const label = b.querySelector('span');
  b.addEventListener('click', () => {
    if (v.muted) { v.muted = false; v.currentTime = 0; v.play(); label.textContent = 'Mute'; b.setAttribute('aria-pressed', 'true'); }
    else { v.muted = true; label.textContent = 'Play with sound'; b.setAttribute('aria-pressed', 'false'); }
  });
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) { v.removeAttribute('autoplay'); v.pause(); }
})();

/*
  The signature: the same light-sweep shader that runs in the launch film
  (launch/video/src/effects/grain-field.ts), drawn live behind the hero.
  Falls back to a rendered still of it when WebGL2 is unavailable or motion is reduced.
*/
(() => {
  const canvas = document.getElementById('sweep');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const gl = canvas.getContext('webgl2', {antialias: false, premultipliedAlpha: true});
  if (!gl) { canvas.remove(); return; }
  const vs = `#version 300 es
  in vec2 p; void main(){ gl_Position = vec4(p,0.,1.); }`;
  const fs = `#version 300 es
  precision highp float;
  uniform vec2 uRes; uniform float uTime, uSeed, uWarm, uAngle, uOffset, uGrain, uDot;
  out vec4 o;
  float hash(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
  float noise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.-2.*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),u.x), mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x), u.y); }
  float fbm(vec2 p){ float v=0., a=.5; for(int i=0;i<6;i++){ v+=a*noise(p); p=p*2.03+vec2(1.7,9.2); a*=.5; } return v; }
  float bayer4(vec2 p){ int x=int(mod(p.x,4.)), y=int(mod(p.y,4.));
    int m[16]=int[16](0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5); return float(m[y*4+x])/16.; }
  void main(){
    vec2 p=(gl_FragCoord.xy-.5*uRes)/uRes.y; float t=uTime;
    float c=cos(uAngle), s=sin(uAngle); vec2 q=mat2(c,-s,s,c)*p; q.y-=uOffset*.5;
    vec2 w=vec2(fbm(q*vec2(.9,2.6)+vec2(t*.07,0.)+uSeed), fbm(q*vec2(.9,2.6)-vec2(0.,t*.05)+uSeed+3.7));
    float streak=fbm(vec2(q.x*.7+w.x*.9-t*.12, q.y*5.2+w.y*1.6)+uSeed*1.3);
    float bend=.10*sin(q.x*1.7+t*.35+uSeed)+.18*(w.y-.5);
    float beam=exp(-pow((q.y-bend)*3.1,2.)); float core=exp(-pow((q.y-bend*.8)*9.,2.))*smoothstep(-1.1,.5,q.x);
    float lum=clamp(beam*.78+core*.45+(streak-.5)*1.25*(.35+beam),0.,1.2);
    vec3 night=vec3(.004,.010,.045), deep=vec3(.004,.050,.420), blue=vec3(.039,.212,.992), sky=vec3(.52,.70,1.), white=vec3(.985,.985,1.), warm=vec3(1.,.43,.13), ember=vec3(.9,.16,.06);
    vec3 col=mix(night,deep,smoothstep(.02,.28,lum)); col=mix(col,blue,smoothstep(.22,.55,lum));
    col=mix(col,sky,smoothstep(.55,.82,lum)); col=mix(col,white,smoothstep(.80,1.05,lum));
    float wf=fbm(q*1.3+vec2(-t*.06,t*.04)+uSeed*2.);
    float wm=smoothstep(.48,.80,wf)*smoothstep(-.05,.35,-q.y+.25)*uWarm;
    col=mix(col,mix(ember,warm,smoothstep(.3,.8,lum)),wm*smoothstep(.08,.55,lum)*.95);
    col*=mix(.55,1.,smoothstep(1.25,.25,length(p*vec2(.9,1.15))));
    vec2 cell=floor(gl_FragCoord.xy/uDot); float g=hash(cell+floor(t*24.)*17.31)-.5; float d=bayer4(cell)-.5;
    col+=(d*.10+g*.08)*uGrain*(.35+.65*smoothstep(0.,.6,lum));
    o=vec4(clamp(col,0.,1.),1.);
  }`;
  const sh = (type, src) => { const x = gl.createShader(type); gl.shaderSource(x, src); gl.compileShader(x); return x; };
  const prog = gl.createProgram();
  gl.attachShader(prog, sh(gl.VERTEX_SHADER, vs));
  gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, fs));
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) { canvas.remove(); return; }
  gl.useProgram(prog);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1,1,-1,-1,1,1,1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, 'p');
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const u = n => gl.getUniformLocation(prog, n);
  const U = {res: u('uRes'), time: u('uTime'), seed: u('uSeed'), warm: u('uWarm'), angle: u('uAngle'), offset: u('uOffset'), grain: u('uGrain'), dot: u('uDot')};
  // Render at most ~1.6 MP; the dither is the texture, so full retina adds nothing.
  const size = () => {
    const r = canvas.getBoundingClientRect();
    const k = Math.min(1, Math.sqrt(1600000 / (r.width * r.height)));
    canvas.width = Math.round(r.width * k); canvas.height = Math.round(r.height * k);
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.uniform2f(U.res, canvas.width, canvas.height);
    gl.uniform1f(U.dot, 2.5 * k);
  };
  gl.uniform1f(U.seed, 1.3); gl.uniform1f(U.warm, 0.6); gl.uniform1f(U.angle, -0.42);
  gl.uniform1f(U.offset, 0.05); gl.uniform1f(U.grain, 0.55);
  size(); addEventListener('resize', size);
  const t0 = performance.now();
  let visible = true, raf = 0;
  const draw = now => {
    gl.uniform1f(U.time, 14 + (now - t0) / 1000);
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    if (!reduce && visible) raf = requestAnimationFrame(draw);
  };
  new IntersectionObserver(([e]) => {
    visible = e.isIntersecting;
    if (visible && !reduce) { cancelAnimationFrame(raf); raf = requestAnimationFrame(draw); }
  }).observe(canvas);
  draw(performance.now());
})();
