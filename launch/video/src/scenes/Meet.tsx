import {AbsoluteFill, Img, Interactive, interpolate, staticFile} from 'remotion';
import {PauseMark} from '../components/PauseMark';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {ramp, useTime} from '../lib/anim';
import {ease, film} from '../theme';

const DROP = 0.5; // the beat drops half a second in

/** 0:07.5 — silence, the pause mark snaps in; on the drop it becomes the app. */
const MeetInner = () => {
  const t = useTime();
  const grow = interpolate(t, [0.04, 0.3], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease.out,
  });
  const markScale = interpolate(t, [0.04, 0.22, 0.42], [0.7, 1.06, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const tile = ramp(t, [DROP, DROP + 0.42], [0, 1], ease.out);
  const tileScale = interpolate(t, [DROP, DROP + 0.22, DROP + 0.5], [0.2, 1.06, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: ease.out,
  });
  const real = ramp(t, [DROP + 0.3, DROP + 0.5], [0, 1], ease.inOut);
  const lift = ramp(t, [DROP + 0.25, DROP + 0.95], [0, 1], ease.out);
  const glow = interpolate(t, [DROP, DROP + 0.12, DROP + 1.6], [0, 1, 0.25], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const out = ramp(t, [2.2, 2.5], [0, 1], ease.in);
  const ICON = 236;
  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          opacity: 1 - out,
          filter: out > 0 ? `blur(${out * 16}px)` : undefined,
        }}
      >
        <div
          style={{
            position: 'absolute',
            width: 900,
            height: 900,
            borderRadius: 450,
            background: `radial-gradient(circle, rgba(10,54,253,${0.22 * glow}) 0%, rgba(10,54,253,0) 60%)`,
            translate: `0 ${-lift * 118}px`,
          }}
        />
        <div
          style={{
            position: 'absolute',
            width: ICON,
            height: ICON,
            translate: `0 ${-lift * 118}px`,
            scale: `${1 - lift * 0.18}`,
          }}
        >
          {/* the squircle blooming behind the mark */}
          <div
            style={{
              position: 'absolute',
              inset: 0,
              borderRadius: ICON * 0.2237,
              background: `linear-gradient(160deg, #0141FD, #0117FB)`,
              scale: `${tileScale}`,
              opacity: tile,
              boxShadow: `0 ${18 * tile}px ${50 * tile}px rgba(1, 40, 253, ${0.35 * tile})`,
            }}
          />
          <div
            style={{
              position: 'absolute',
              inset: 0,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              scale: `${markScale}`,
              opacity: 1 - real,
            }}
          >
            <PauseMark
              width={ICON * 0.45}
              height={ICON * 0.58}
              grow={grow}
              color={`rgb(${Math.round(10 + 245 * tile)}, ${Math.round(54 + 201 * tile)}, ${Math.round(253 + 2 * tile)})`}
            />
          </div>
          <Img
            src={staticFile('img/steadfast-icon.png')}
            style={{
              position: 'absolute',
              inset: 0,
              width: ICON,
              height: ICON,
              borderRadius: ICON * 0.2237,
              opacity: real,
              scale: `${tileScale}`,
            }}
          />
        </div>
        <div style={{position: 'absolute', translate: '0 128px'}}>
          <Words parts={[{text: 'Meet Steadfast.'}]} size={104} start={DROP + 0.32} weight={650} />
        </div>
        <div style={{position: 'absolute', translate: '0 222px'}}>
          <Words
            parts={[{text: 'Blocks distracting websites and apps on your Mac.', color: film.secondary}]}
            size={34}
            weight={500}
            tracking={-0.015}
            start={DROP + 0.85}
            stagger={0.035}
          />
        </div>
      </AbsoluteFill>
      <Sfx name="Pause snap" src="snap" at={0.04} volume={0.8} />
    </>
  );
};

export const Meet = Interactive.create({Component: MeetInner, layout: 'absolute-fill'});
