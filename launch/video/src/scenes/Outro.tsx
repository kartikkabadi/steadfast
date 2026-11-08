import {AbsoluteFill, Img, Interactive, interpolate, staticFile} from 'remotion';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {ramp, useTime} from '../lib/anim';
import {ease, film, SF} from '../theme';

const LIVE = 1.5;
const CARD = 3.0; // the final hit (0:51)
const BLACK = 6.3;

/** 0:48 — free and open source, now live, and where to get it. */
const OutroInner = () => {
  const t = useTime();
  const firstOut = ramp(t, [1.3, 1.5], [0, 1], ease.in);
  const card = ramp(t, [CARD, CARD + 0.6], [0, 1], ease.out);
  const iconScale = interpolate(t, [CARD, CARD + 0.25, CARD + 0.6], [0.6, 1.04, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease.out,
  });
  const glow = interpolate(t, [CARD, CARD + 0.1, CARD + 2.4], [0, 1, 0.3], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'});
  const url = ramp(t, [CARD + 0.45, CARD + 0.95], [0, 1], ease.out);
  const black = ramp(t, [BLACK, BLACK + 0.5], [0, 1], ease.inOut);
  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      {t < LIVE + 0.1 && (
        <AbsoluteFill
          style={{
            justifyContent: 'center',
            alignItems: 'center',
            opacity: 1 - firstOut,
            filter: firstOut > 0 ? `blur(${firstOut * 16}px)` : undefined,
          }}
        >
          <Words parts={[{text: 'Free and '}, {text: 'open source.', color: film.brand}]} size={120} start={0} weight={650} />
        </AbsoluteFill>
      )}
      {t >= LIVE && t < CARD && (
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <Words parts={[{text: 'Steadfast is now live.'}]} size={120} start={LIVE} exit={CARD - 0.28} weight={650} />
        </AbsoluteFill>
      )}
      {t >= CARD && (
        <AbsoluteFill style={{justifyContent: 'center', alignItems: 'center'}}>
          <div
            style={{
              position: 'absolute',
              width: 1000,
              height: 1000,
              borderRadius: 500,
              translate: '0 -90px',
              background: `radial-gradient(circle, rgba(10,54,253,${0.2 * glow}) 0%, rgba(10,54,253,0) 60%)`,
            }}
          />
          <Img
            src={staticFile('img/steadfast-icon.png')}
            style={{
              width: 190,
              height: 190,
              borderRadius: 190 * 0.2237,
              translate: '0 -110px',
              scale: `${iconScale}`,
              opacity: card,
              boxShadow: `0 18px 50px rgba(1, 40, 253, ${0.32 * card})`,
            }}
          />
          <div
            style={{
              position: 'absolute',
              translate: '0 70px',
              fontFamily: SF,
              fontSize: 92,
              fontWeight: 650,
              letterSpacing: '-0.04em',
              color: film.ink,
              opacity: card,
              filter: card < 1 ? `blur(${(1 - card) * 14}px)` : undefined,
            }}
          >
            Steadfast
          </div>
          <div
            style={{
              position: 'absolute',
              translate: '0 158px',
              fontFamily: SF,
              fontSize: 34,
              fontWeight: 500,
              letterSpacing: '-0.01em',
              color: film.brand,
              opacity: url,
              filter: url < 1 ? `blur(${(1 - url) * 10}px)` : undefined,
            }}
          >
            github.com/kartikkabadi/steadfast
          </div>
          <div
            style={{
              position: 'absolute',
              translate: '0 214px',
              fontFamily: SF,
              fontSize: 24,
              fontWeight: 400,
              color: film.secondary,
              opacity: ramp(t, [CARD + 0.7, CARD + 1.2], [0, 1], ease.out),
            }}
          >
            Free and open source · For Apple silicon Macs on macOS 26 or later
          </div>
        </AbsoluteFill>
      )}
      <AbsoluteFill style={{backgroundColor: '#000', opacity: black}} />
      <Sfx name="Final shimmer" src="commit" at={CARD} volume={0.35} />
    </>
  );
};

export const Outro = Interactive.create({Component: OutroInner, layout: 'absolute-fill'});
