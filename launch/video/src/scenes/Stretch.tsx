import {AbsoluteFill, interpolate, interpolateColors, Interactive} from 'remotion';
import {Sfx} from '../components/Sfx';
import {ramp, useTime} from '../lib/anim';
import {ease, film, SF_DISPLAY} from '../theme';

/**
 * 0:36 — the build. "Make room" stretches with the snare roll: one new "o" per
 * eighth, then sixteenth, then thirty-second note. On the last hit it snaps
 * back like a rubber band to a plain "Make room." and holds through the
 * silence before the drop.
 */
const ARRIVALS: number[] = [];
for (let i = 0; i < 8; i++) ARRIVALS.push(0.0 + i * 0.25);
for (let i = 0; i < 8; i++) ARRIVALS.push(2.0 + i * 0.125);
for (let i = 0; i < 8; i++) ARRIVALS.push(3.0 + i * 0.0625);
const N = ARRIVALS.length;
const END = 3.5;
const SNAP = END - 0.04;
const SIZE = 210;

const type = {
  fontFamily: SF_DISPLAY,
  fontWeight: 650,
  fontSize: SIZE,
  letterSpacing: '-0.045em',
  whiteSpace: 'nowrap',
} as const;

const StretchInner = () => {
  const t = useTime();
  const shown = ARRIVALS.filter((a) => a <= t);
  // each "o" a little bigger than the last, shading from ink into the brand blue
  const os = shown.map((a, i) => ({
    p: ramp(t, [a, a + 0.18], [0, 1], ease.out),
    k: 0.74 + 0.56 * (i / (N - 1)),
    color: interpolateColors(i, [0, 8, N - 1], [film.ink, film.ink, film.brand]),
  }));
  const width = os.reduce((acc, o) => acc + SIZE * 0.62 * o.k * o.p, 0);
  const headWidth = SIZE * 2.95; // "Make r"
  // keep the newest letter in the right third of the frame
  const shift = Math.max(0, headWidth + width - 1320);
  const intro = ramp(t, [0, 0.4], [0, 1], ease.out);

  // the snap: the stretched word recoils toward centre and gives way to the plain one
  const recoil = ramp(t, [SNAP, SNAP + 0.1], [0, 1], ease.in);
  const land = ramp(t, [SNAP + 0.02, SNAP + 0.3], [0, 1], ease.settle);
  const landScale = interpolate(land, [0, 1], [1.18, 1]);

  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      {recoil < 1 && (
        <AbsoluteFill style={{justifyContent: 'center', transformOrigin: '50% 50%', scale: `${1 - recoil * 0.82} 1`, opacity: 1 - recoil}}>
          <div
            style={{
              ...type,
              display: 'flex',
              alignItems: 'baseline',
              color: film.ink,
              translate: `${300 - shift}px 0`,
              opacity: intro,
              filter: intro < 1 ? `blur(${(1 - intro) * 16}px)` : recoil > 0 ? `blur(${recoil * 12}px)` : undefined,
            }}
          >
            <span>Make r</span>
            {os.map((o, i) => (
              <span
                key={i}
                style={{
                  display: 'inline-block',
                  overflow: 'hidden',
                  fontSize: SIZE * o.k,
                  width: SIZE * 0.62 * o.k * o.p,
                  opacity: o.p,
                  filter: o.p < 1 ? `blur(${(1 - o.p) * 8}px)` : undefined,
                  color: o.color,
                  transformOrigin: '0 100%',
                  scale: `${0.6 + 0.4 * o.p}`,
                }}
              >
                o
              </span>
            ))}
          </div>
        </AbsoluteFill>
      )}
      {land > 0 && (
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <div
            style={{
              ...type,
              color: film.ink,
              scale: `${landScale}`,
              opacity: Math.min(1, land * 2.5),
              filter: land < 1 ? `blur(${(1 - land) * 10}px)` : undefined,
            }}
          >
            Make <span style={{color: film.brand}}>room.</span>
          </div>
        </AbsoluteFill>
      )}
      <Sfx name="Stretch" src="stretch" at={1.8} volume={0.22} />
      <Sfx name="Snap back" src="snap" at={SNAP} volume={0.7} />
    </>
  );
};

export const Stretch = Interactive.create({Component: StretchInner, layout: 'absolute-fill'});
