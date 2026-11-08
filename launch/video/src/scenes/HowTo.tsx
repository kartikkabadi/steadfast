import {AbsoluteFill, Interactive, interpolate} from 'remotion';
import {Backdrop} from '../components/Backdrop';
import {Cursor, pathAt, type Key} from '../components/Cursor';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {pulse, ramp, typed, typedTimes, useTime} from '../lib/anim';
import {ease} from '../theme';
import {MacWindow} from '../ui/kit';
import {ActiveScreen, Composer, ReviewSheet, WebsitePicker, WINDOW} from '../ui/screens';

/* Layout of the window on the 1920×1080 stage. */
const S = 1.5;
const WX = 1920 - WINDOW.width * S - 80;
const WY = (1080 - WINDOW.height * S) / 2;
const SHEET_TOP = 40;

/* Every click sits on the soundtrack's sixteenth-note grid, clear of the claps on beats 2 and 4. */
export const T = {
  chooseClick: 1.0,
  sheetIn: 1.05,
  xClick: 1.75,
  ytClick: 2.25,
  redditClick: 2.75,
  doneClick: 3.25,
  sheetOut: 3.3,
  durationClick: 4.625,
  purposeClick: 6.625,
  typeAt: 6.85,
  reviewClick: 9.625,
  reviewIn: 9.675,
  commitClick: 10.5,
  reviewOut: 10.55,
  active: 10.75,
};

export const NAME = 'Ship my app';
export const DOMAINS = ['reddit.com', 'twitter.com', 'x.com', 'youtu.be', 'youtube.com'];

/* Cursor path in window points (hotspot). */
const PATH: Key[] = [
  {t: 0.3, x: 790, y: 560},
  {t: 0.86, x: 631, y: 260},
  {t: 1.15, x: 622, y: 262},
  {t: 1.6, x: 228, y: 262},
  {t: 1.8, x: 228, y: 262},
  {t: 2.1, x: 232, y: 214},
  {t: 2.6, x: 466, y: 262},
  {t: 3.1, x: 558, y: 520},
  {t: 3.6, x: 550, y: 500},
  {t: 4.35, x: 362, y: 434},
  {t: 5.4, x: 380, y: 470},
  {t: 6.35, x: 240, y: 186},
  {t: 6.9, x: 246, y: 190},
  {t: 8.6, x: 470, y: 360},
  {t: 9.35, x: 610, y: 611},
  {t: 9.8, x: 600, y: 560},
  {t: 10.35, x: 528, y: 408},
  {t: 10.9, x: 550, y: 450},
];
const CLICKS = [T.chooseClick, T.xClick, T.ytClick, T.redditClick, T.doneClick, T.durationClick, T.purposeClick, T.reviewClick, T.commitClick];

/* Camera: zoom toward a focus point (window points). */
const CAM = [
  {t: 0.0, k: 1.0, x: 360, y: 320},
  {t: 1.0, k: 1.0, x: 360, y: 320},
  {t: 1.45, k: 1.05, x: 360, y: 290},
  {t: 3.35, k: 1.05, x: 360, y: 290},
  {t: 3.9, k: 1.07, x: 360, y: 420},
  {t: 5.6, k: 1.07, x: 360, y: 420},
  {t: 6.2, k: 1.07, x: 330, y: 190},
  {t: 8.6, k: 1.07, x: 330, y: 190},
  {t: 9.2, k: 1.02, x: 360, y: 330},
  {t: 10.7, k: 1.04, x: 360, y: 300},
  {t: 11.6, k: 1.06, x: 270, y: 200},
  {t: 16.0, k: 1.12, x: 240, y: 190},
];

const camAt = (t: number) => {
  const ts = CAM.map((c) => c.t);
  const o = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut} as const;
  return {
    k: interpolate(t, ts, CAM.map((c) => c.k), o),
    x: interpolate(t, ts, CAM.map((c) => c.x), o),
    y: interpolate(t, ts, CAM.map((c) => c.y), o),
  };
};

const Caption: React.FC<{readonly text: string; readonly dim?: string; readonly start: number; readonly exit: number}> = ({
  text,
  dim,
  start,
  exit,
}) => (
  <div style={{position: 'absolute', left: 110, top: 0, bottom: 0, width: WX - 170, display: 'flex', alignItems: 'center'}}>
    <Words
      parts={[{text, color: '#fff'}, ...(dim ? [{text: ` ${dim}`, color: 'rgba(255,255,255,0.6)'}] : [])]}
      size={74}
      align="left"
      start={start}
      exit={exit}
      lineHeight={1.08}
      stagger={0.045}
    />
  </div>
);

const HowToInner = () => {
  const t = useTime();

  // State of the draft over time.
  const picked = {
    'X / Twitter': ramp(t, [T.xClick, T.xClick + 0.3], [0, 1], ease.settle),
    YouTube: ramp(t, [T.ytClick, T.ytClick + 0.3], [0, 1], ease.settle),
    Reddit: ramp(t, [T.redditClick, T.redditClick + 0.3], [0, 1], ease.settle),
  };
  const count = (t >= T.xClick ? 2 : 0) + (t >= T.ytClick ? 2 : 0) + (t >= T.redditClick ? 1 : 0);
  const chosen = t >= T.sheetOut;
  const twoHours = t >= T.durationClick + 0.05;
  const durationPos = ramp(t, [T.durationClick, T.durationClick + 0.32], [1, 2], ease.settle);
  const summary = chosen ? `5 websites · ${twoHours ? '2 hours' : '1 hour'} · ends at ${twoHours ? '11:30' : '10:30'}` : null;
  const focused = t >= T.purposeClick && t < T.reviewClick;
  const purpose = typed(NAME, t, T.typeAt, 12);
  const caret = Math.floor((t - T.purposeClick) * 2.4) % 2 === 0 || (t > T.typeAt && t < T.typeAt + 1.0);

  const sheetA = ramp(t, [T.sheetIn, T.sheetIn + 0.32], [0, 1], ease.out) * (1 - ramp(t, [T.sheetOut, T.sheetOut + 0.25], [0, 1], ease.in));
  const reviewA =
    ramp(t, [T.reviewIn, T.reviewIn + 0.32], [0, 1], ease.out) * (1 - ramp(t, [T.reviewOut, T.reviewOut + 0.25], [0, 1], ease.in));
  const active = ramp(t, [T.active, T.active + 0.9], [0, 1], ease.out);

  const press = (at: number) => pulse(t, at - 0.04, 0.2);
  const near = (x: number, y: number, r = 40) => {
    const c = pathAt(PATH, t);
    return Math.hypot(c.x - x, c.y - y) < r ? 1 : 0;
  };

  // Time-lapse while the payoff line plays: the block counts down in real format.
  const minutes = Math.round(interpolate(t, [13.2, 15.6], [120, 94], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut}));
  const remaining = minutes >= 120 ? '2 h' : `${Math.floor(minutes / 60)} h ${minutes % 60} min`;
  const enter = ramp(t, [0, 0.65], [0, 1], ease.out);
  const out = ramp(t, [15.62, 16.0], [0, 1], ease.in);
  const cam = camAt(t);
  const cursor = pathAt(PATH, t);
  const clickPress = Math.max(...CLICKS.map((c) => pulse(t, c - 0.05, 0.16)));
  const cursorOpacity = ramp(t, [0.3, 0.5], [0, 1]) * (1 - ramp(t, [10.9, 11.2], [0, 1]));

  return (
    <>
      <Backdrop seed={1.3} warm={0.65} t0={14} angle={-0.48} offset={0.1} />
      <AbsoluteFill style={{opacity: 1 - out, filter: out > 0 ? `blur(${out * 16}px)` : undefined}}>
        <Caption text="Pick what to block." start={0.15} exit={3.45} />
        <Caption text="Choose how long." start={3.7} exit={5.75} />
        <Caption text="Say what it's for." start={6.0} exit={8.7} />
        <Caption text="Then commit." start={8.95} exit={10.9} />
        <Caption text="Now it holds." start={11.2} exit={12.85} />
        <Caption text="Make room for what you" dim="actually want to do." start={13.1} exit={20} />

        <div
          style={{
            position: 'absolute',
            left: WX,
            top: WY,
            width: WINDOW.width * S,
            height: WINDOW.height * S,
            transformOrigin: '0 0',
            translate: `${cam.x * S * (1 - cam.k)}px ${cam.y * S * (1 - cam.k) + (1 - enter) * 90}px`,
            scale: `${cam.k}`,
            opacity: enter,
            filter: enter < 1 ? `blur(${(1 - enter) * 12}px)` : undefined,
          }}
        >
          <div style={{transformOrigin: '0 0', scale: `${S}`, width: WINDOW.width, height: WINDOW.height, position: 'relative'}}>
            <MacWindow width={WINDOW.width} height={WINDOW.height} dim={Math.max(sheetA, reviewA)}>
              <div style={{position: 'absolute', inset: 0, opacity: 1 - active}}>
                <Composer
                  purpose={purpose}
                  caret={caret}
                  focused={focused}
                  websites={chosen ? DOMAINS.join(', ') : 'None chosen'}
                  websitesHover={t < T.sheetIn ? near(622, 262, 60) : 0}
                  durationPos={durationPos}
                  durationSel={twoHours ? 2 : 1}
                  summary={summary}
                  reviewPress={press(T.reviewClick)}
                  reviewHover={near(604, 610, 70)}
                />
              </div>
              {active > 0 && (
                <ActiveScreen name={NAME} left={`${remaining} left`} unlock="Websites unlock at 11:30" domains={DOMAINS} reveal={active} />
              )}
            </MacWindow>
            {sheetA > 0 && (
              <div
                style={{
                  position: 'absolute',
                  left: (WINDOW.width - 520) / 2,
                  top: SHEET_TOP,
                  opacity: sheetA,
                  scale: `${0.94 + 0.06 * sheetA}`,
                  translate: `0 ${(1 - sheetA) * -16}px`,
                  transformOrigin: '50% 0',
                }}
              >
                <WebsitePicker
                  marks={picked}
                  presses={{
                    'X / Twitter': press(T.xClick),
                    YouTube: press(T.ytClick),
                    Reddit: press(T.redditClick),
                  }}
                  count={count}
                  donePress={press(T.doneClick)}
                />
              </div>
            )}
            {reviewA > 0 && (
              <div
                style={{
                  position: 'absolute',
                  left: (WINDOW.width - 520) / 2,
                  top: SHEET_TOP,
                  opacity: reviewA,
                  scale: `${0.94 + 0.06 * reviewA}`,
                  translate: `0 ${(1 - reviewA) * -16}px`,
                  transformOrigin: '50% 0',
                }}
              >
                <ReviewSheet
                  name={NAME}
                  domains={DOMAINS}
                  ends="11:30"
                  duration="2 hours"
                  press={press(T.commitClick)}
                  hover={near(524, 407, 70)}
                />
              </div>
            )}
            <Cursor x={cursor.x} y={cursor.y} press={clickPress} opacity={cursorOpacity} scale={1 / S + 0.12} />
          </div>
        </div>
      </AbsoluteFill>

      {CLICKS.map((c, i) => (
        <Sfx key={i} name={`Click ${i + 1}`} src="rm-mouse-click" at={c - 0.03} volume={0.9} />
      ))}
      {/* a crisp tap layered under each click so it cuts through the off-beat hats */}
      {CLICKS.map((c, i) => (
        <Sfx key={`tap${i}`} name={`Click tap ${i + 1}`} src="key-2" at={c - 0.03} volume={0.5} />
      ))}
      <Sfx name="Sheet in" src="air" at={T.sheetIn - 0.05} volume={0.25} />
      <Sfx name="Tick X" src="select" at={T.xClick} volume={0.75} />
      <Sfx name="Tick YouTube" src="select" at={T.ytClick} volume={0.75} />
      <Sfx name="Tick Reddit" src="select" at={T.redditClick} volume={0.75} />
      <Sfx name="Sheet out" src="air" at={T.sheetOut} volume={0.18} />
      <Sfx name="Duration" src="rm-switch" at={T.durationClick - 0.1} volume={0.7} />
      {typedTimes(NAME, T.typeAt, 12).map((at, i) => (
        <Sfx key={`k${i}`} name={`Key ${i + 1}`} src={`key-${i % 4}`} at={at} volume={0.6} />
      ))}
      <Sfx name="Review in" src="air" at={T.reviewIn - 0.05} volume={0.22} />
      <Sfx name="Commit" src="commit" at={T.commitClick} volume={1} />
    </>
  );
};

export const HowTo = Interactive.create({Component: HowToInner, layout: 'absolute-fill'});
