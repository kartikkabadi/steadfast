import {AbsoluteFill, Interactive, interpolate} from 'remotion';
import {Browser} from '../components/Browser';
import {Sfx} from '../components/Sfx';
import {ramp, typed, typedTimes, useTime} from '../lib/anim';
import {ease, film} from '../theme';

export const DOMAIN = 'x.com';
export const TYPE_AT = 0.55;
export const CPS = 11;
export const ENTER = 1.32;
export const LOADED = 2.25;

/** 0:00 — the habit. Type x.com, press return, and it doesn't load. */
const ColdOpenInner = () => {
  const t = useTime();
  const typedText = typed(DOMAIN, t, TYPE_AT, CPS);
  const submitted = t >= ENTER;
  const loading = submitted ? ramp(t, [ENTER, LOADED], [0, 0.82], ease.out) : -1;
  const error = ramp(t, [LOADED, LOADED + 0.35], [0, 1], ease.out);
  const caret = Math.floor(t * 2.2) % 2 === 0 || (t > TYPE_AT && t < ENTER);

  // Camera: start tight on the address bar, pull back on return, then push
  // slowly into the error. Focus is in browser points; it lands at frame centre.
  const enter = ramp(t, [0, 0.7], [0, 1], ease.out);
  const o = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut} as const;
  const keys = [0, 1.0, ENTER + 0.05, LOADED + 0.1, 4.0];
  // the push ends with the toolbar fully out of frame, so the last beat is just the error
  const k = interpolate(t, keys, [2.55, 2.4, 2.4, 1.32, 2.0], o);
  const fx = interpolate(t, keys, [590, 590, 590, 590, 590], o);
  const fy = interpolate(t, keys, [40, 34, 34, 330, 342], o);
  const out = ramp(t, [3.62, 4.0], [0, 1], ease.in);

  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      <AbsoluteFill
        style={{
          opacity: enter * (1 - out),
          filter: `blur(${(1 - enter) * 14 + out * 22}px)`,
        }}
      >
        <div
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            transformOrigin: '0 0',
            translate: `${960 - fx * k}px ${540 - fy * k}px`,
            scale: `${k}`,
          }}
        >
          <Browser
            width={1180}
            height={700}
            address={submitted ? DOMAIN : typedText}
            focused={!submitted}
            caret={caret}
            loading={loading}
            error={error}
            domain={DOMAIN}
          />
        </div>
      </AbsoluteFill>
      {typedTimes(DOMAIN, TYPE_AT, CPS).map((at, i) => (
        <Sfx key={i} name={`Key ${i + 1}`} src={`key-${i % 4}`} at={at} volume={0.55} />
      ))}
      <Sfx name="Return" src="key-enter" at={ENTER} volume={0.7} />
      <Sfx name="Can't load" src="error" at={LOADED} volume={0.85} />
    </>
  );
};

export const ColdOpen = Interactive.create({Component: ColdOpenInner, layout: 'absolute-fill'});
