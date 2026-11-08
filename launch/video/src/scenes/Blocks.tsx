import {AbsoluteFill, Img, Interactive, interpolate, staticFile} from 'remotion';
import {Backdrop} from '../components/Backdrop';
import {Sfx} from '../components/Sfx';
import {Sym} from '../components/Symbol';
import {Words} from '../components/Words';
import {ramp, useTime} from '../lib/anim';
import {ease, SF, ui} from '../theme';

type Item = {label: string; symbol?: string; app?: string; at: number};

const ITEMS: Item[] = [
  {label: 'x.com', symbol: 'bubble', at: 0.5},
  {label: 'youtube.com', symbol: 'play.rectangle', at: 0.75},
  {label: 'reddit.com', symbol: 'text.bubble', at: 1.0},
  {label: 'Spotify', app: 'spotify', at: 1.25},
  {label: 'WhatsApp', app: 'whatsapp', at: 1.5},
];

const Chip: React.FC<{readonly item: Item; readonly t: number; readonly i: number}> = ({item, t, i}) => {
  const enter = ramp(t, [0.05 + i * 0.06, 0.55 + i * 0.06], [0, 1], ease.out);
  const lock = ramp(t, [item.at, item.at + 0.16], [0, 1], ease.out);
  const pop = interpolate(t, [item.at, item.at + 0.08, item.at + 0.3], [1, 1.07, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 14,
        height: 78,
        padding: '0 26px 0 20px',
        borderRadius: 22,
        background: `rgba(255,255,255,${0.14 + lock * 0.8})`,
        boxShadow: `inset 0 0 0 1px rgba(255,255,255,${0.38 - lock * 0.2}), 0 18px 40px rgba(0,0,20,${0.18 + lock * 0.12})`,
        backdropFilter: 'blur(24px) saturate(1.4)',
        opacity: enter,
        translate: `0 ${(1 - enter) * 40}px`,
        filter: enter < 1 ? `blur(${(1 - enter) * 10}px)` : undefined,
        scale: `${pop}`,
      }}
    >
      {item.app ? (
        <Img src={staticFile(`img/apps/${item.app}.png`)} style={{width: 44, height: 44}} />
      ) : (
        <div style={{width: 44, display: 'flex', justifyContent: 'center'}}>
          <Sym name={item.symbol!} size={26} color={lock > 0.5 ? ui.muted : '#fff'} />
        </div>
      )}
      <div
        style={{
          fontFamily: SF,
          fontSize: 30,
          fontWeight: 500,
          letterSpacing: -0.3,
          color: lock > 0.5 ? '#1d1d1f' : '#fff',
        }}
      >
        {item.label}
      </div>
      <div
        style={{
          width: 30 * lock,
          overflow: 'hidden',
          display: 'flex',
          justifyContent: 'flex-end',
          opacity: lock,
        }}
      >
        <Sym name="lock.fill" size={20} color={ui.muted} />
      </div>
    </div>
  );
};

/** 0:10 — on the beat, each distraction locks. */
const BlocksInner = () => {
  const t = useTime();
  const out = ramp(t, [1.78, 2.0], [0, 1], ease.in);
  return (
    <>
      <Backdrop seed={4.2} warm={0.55} t0={6} angle={-0.36} />
      <AbsoluteFill
        style={{
          justifyContent: 'center',
          alignItems: 'center',
          gap: 64,
          opacity: 1 - out,
          filter: out > 0 ? `blur(${out * 14}px)` : undefined,
        }}
      >
        <Words
          parts={[
            {text: 'Websites. ', color: '#fff'},
            {text: 'Apps. ', color: '#fff'},
            {text: 'Locked.', color: 'rgba(255,255,255,0.62)'},
          ]}
          size={96}
          start={0.0}
          stagger={0.25}
          dur={0.45}
        />
        <div style={{display: 'flex', gap: 18}}>
          {ITEMS.map((item, i) => (
            <Chip key={item.label} item={item} t={t} i={i} />
          ))}
        </div>
      </AbsoluteFill>
      {ITEMS.map((item) => (
        <Sfx key={item.label} name={`Lock ${item.label}`} src="select" at={item.at} volume={0.6} />
      ))}
    </>
  );
};

export const Blocks = Interactive.create({Component: BlocksInner, layout: 'absolute-fill'});
