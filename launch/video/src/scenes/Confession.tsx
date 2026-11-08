import {AbsoluteFill, Interactive} from 'remotion';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {ramp, useTime} from '../lib/anim';
import {ease, film, SF_DISPLAY} from '../theme';

const SIZE = 92;
const ROLL = [0.42, 1.02] as const;

/** A digit wheel that spins up to `to`. */
const Roller: React.FC<{readonly to: number; readonly t: number; readonly start: number}> = ({to, t, start}) => {
  const v = ramp(t, [ROLL[0], ROLL[1]], [0, to], ease.out);
  const p = ramp(t, [start, start + 0.45], [0, 1], ease.out);
  return (
    <span
      style={{
        display: 'inline-block',
        height: '1.06em',
        overflow: 'hidden',
        verticalAlign: 'top',
        opacity: p,
        filter: p < 1 ? `blur(${(1 - p) * 14}px)` : undefined,
        WebkitMaskImage: 'linear-gradient(to bottom, transparent, #000 18%, #000 82%, transparent)',
        color: film.brand,
      }}
    >
      <span style={{display: 'block', translate: `0 ${-v * 1.06}em`}}>
        {Array.from({length: to + 1}, (_, i) => (
          <span key={i} style={{display: 'block', height: '1.06em', fontVariantNumeric: 'tabular-nums'}}>
            {i}
          </span>
        ))}
      </span>
    </span>
  );
};

/** 0:04 — "i was spending about 6 hours a day on x. so i built an app that locks me out." */
const ConfessionInner = () => {
  const t = useTime();
  const firstOut = ramp(t, [1.72, 2.0], [0, 1], ease.in);
  // ticks as the wheel passes each number
  const ticks: number[] = [];
  for (let n = 1; n <= 6; n++) {
    // invert ease.out roughly by sampling
    for (let s = ROLL[0]; s <= ROLL[1]; s += 1 / 120) {
      if (ramp(s, [ROLL[0], ROLL[1]], [0, 6], ease.out) >= n - 0.5) {
        ticks.push(s);
        break;
      }
    }
  }
  const lock = ramp(t, [2.72, 2.95], [0, 1], ease.out);
  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
        <div
          style={{
            position: 'absolute',
            opacity: 1 - firstOut,
            filter: firstOut > 0 ? `blur(${firstOut * 18}px)` : undefined,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
          }}
        >
          <Words parts={[{text: 'i was spending about', color: film.secondary}]} size={SIZE} start={0.0} />
          <div
            style={{
              fontFamily: SF_DISPLAY,
              fontSize: SIZE,
              fontWeight: 600,
              letterSpacing: '-0.035em',
              lineHeight: 1.06,
              display: 'flex',
              alignItems: 'flex-start',
            }}
          >
            <Roller to={6} t={t} start={0.3} />
            <span style={{width: '0.2em'}} />
            <Words parts={[{text: 'hours a day on x.'}]} size={SIZE} start={0.36} />
          </div>
        </div>
        {t >= 1.95 && (
          <div style={{position: 'absolute', display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
            <Words parts={[{text: 'so i built an app'}]} size={SIZE} start={2.0} exit={3.15} />
            <Words
              parts={[{text: 'that '}, {text: 'locks me out.', color: film.brand}]}
              size={SIZE}
              start={2.3}
              exit={3.15}
              style={{scale: `${1 + lock * 0.015}`}}
            />
          </div>
        )}
      </AbsoluteFill>
      {ticks.map((at, i) => (
        <Sfx key={i} name={`Tick ${i + 1}`} src="tick" at={at} volume={0.5} />
      ))}
      <Sfx name="Whoosh in" src="air" at={1.85} volume={0.35} />
    </>
  );
};

export const Confession = Interactive.create({Component: ConfessionInner, layout: 'absolute-fill'});
