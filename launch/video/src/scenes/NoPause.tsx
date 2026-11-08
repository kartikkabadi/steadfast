import {AbsoluteFill, Interactive, interpolate} from 'remotion';
import {Cursor, pathAt} from '../components/Cursor';
import {PauseMark} from '../components/PauseMark';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {pulse, ramp, useTime} from '../lib/anim';
import {ease, film, SF, ui} from '../theme';

export const CLICK = 2.75;

/**
 * 0:28 — the breakdown. "Once a block starts, you can't pause or end it early."
 * Then the joke the logo has been setting up: the pause mark that won't pause.
 */
const NoPauseInner = () => {
  const t = useTime();
  const firstOut = ramp(t, [1.72, 1.98], [0, 1], ease.in);
  const ring = ramp(t, [2.0, 2.5], [0, 1], ease.out);
  const shake = t > CLICK ? Math.sin((t - CLICK) * 70) * Math.exp(-(t - CLICK) * 9) * 14 : 0;
  // the same block, 26 minutes in (see HowTo) — the ring is time already held
  const fraction = interpolate(t, [2.0, 4.0], [26 / 120, 26.4 / 120]);
  const cursor = pathAt(
    [
      {t: 2.1, x: 1240, y: 820},
      {t: 2.65, x: 970, y: 552},
      {t: 3.2, x: 977, y: 560},
    ],
    t,
  );
  const out = ramp(t, [3.72, 4.0], [0, 1], ease.in);
  const R = 190;
  const W = 20;
  const r = R - W / 2;
  const circ = 2 * Math.PI * r;
  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          opacity: 1 - firstOut,
          filter: firstOut > 0 ? `blur(${firstOut * 18}px)` : undefined,
        }}
      >
        <Words parts={[{text: 'Once a block starts,', color: film.secondary}]} size={96} start={0.02} />
        <Words parts={[{text: "you can't pause it"}]} size={96} start={0.5} />
        <Words parts={[{text: 'or end it early.'}]} size={96} start={1.0} />
      </AbsoluteFill>
      {t >= 1.95 && (
        <AbsoluteFill
          style={{
            justifyContent: 'center',
            alignItems: 'center',
            opacity: ring * (1 - out),
            filter: out > 0 ? `blur(${out * 16}px)` : undefined,
          }}
        >
          {/* BlockRing from ProgressHold.swift, at film scale */}
          <div style={{position: 'relative', width: R * 2, height: R * 2, translate: `${shake}px 0`, scale: `${0.9 + 0.1 * ring}`}}>
            <svg width={R * 2} height={R * 2} style={{position: 'absolute', inset: 0}}>
              <circle cx={R} cy={R} r={r} stroke="rgba(0,0,0,0.065)" strokeWidth={W} fill="none" />
              <circle
                cx={R}
                cy={R}
                r={r}
                stroke={ui.accent}
                strokeWidth={W}
                strokeLinecap="round"
                fill="none"
                strokeDasharray={`${fraction * circ} ${circ}`}
                transform={`rotate(-90 ${R} ${R})`}
              />
            </svg>
            <div style={{position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
              <PauseMark width={R * 2 * 0.22} height={R * 2 * 0.28} color={ui.accent} style={{scale: `${1 - pulse(t, CLICK - 0.03, 0.18) * 0.08}`}} />
            </div>
          </div>
          <div
            style={{
              position: 'absolute',
              translate: '0 290px',
              fontFamily: SF,
              fontSize: 56,
              fontWeight: 600,
              letterSpacing: '-0.02em',
              color: film.ink,
              opacity: ramp(t, [CLICK + 0.12, CLICK + 0.45], [0, 1]),
              filter: `blur(${(1 - ramp(t, [CLICK + 0.12, CLICK + 0.45], [0, 1])) * 10}px)`,
            }}
          >
            Not even this pause button.
          </div>
          <Cursor
            x={cursor.x}
            y={cursor.y}
            press={pulse(t, CLICK - 0.05, 0.16)}
            opacity={ramp(t, [2.1, 2.3], [0, 1])}
            scale={1.6}
          />
        </AbsoluteFill>
      )}
      <Sfx name="Click pause" src="rm-mouse-click" at={CLICK - 0.03} volume={0.85} />
      <Sfx name="Denied" src="deny" at={CLICK + 0.02} volume={0.7} />
    </>
  );
};

export const NoPause = Interactive.create({Component: NoPauseInner, layout: 'absolute-fill'});
