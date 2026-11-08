import {AbsoluteFill, Interactive} from 'remotion';
import {Browser} from '../components/Browser';
import {Cursor, pathAt} from '../components/Cursor';
import {Sfx} from '../components/Sfx';
import {Words} from '../components/Words';
import {pulse, ramp, useTime} from '../lib/anim';
import {ease, film, SF} from '../theme';
import {MacWindow} from '../ui/kit';
import {ActiveScreen, MenuPanel, WINDOW} from '../ui/screens';
import {DOMAINS, NAME} from './HowTo';

// Continuity with HowTo: a 2-hour block set at 09:30, 26 minutes in.
const LEFT = '1 h 34 min left';
const ELAPSED = 26 / 120;

export const QUIT = 1.0;
const BAR = 37; // menu bar height on the stage (24 pt × ~1.5)

const MenuBar: React.FC<{readonly steadfast: number}> = ({steadfast}) => (
  <div
    style={{
      position: 'absolute',
      left: 0,
      right: 0,
      top: 0,
      height: BAR,
      background: 'rgba(246,246,248,0.85)',
      borderBottom: '1px solid rgba(0,0,0,0.06)',
      display: 'flex',
      alignItems: 'center',
      padding: '0 22px',
      gap: 30,
      fontFamily: SF,
      fontSize: 20,
      color: '#1d1d1f',
      zIndex: 20,
    }}
  >
    <span style={{fontSize: 22}}>{''}</span>
    <span style={{fontWeight: 700}}>Steadfast</span>
    <span>File</span>
    <span>Edit</span>
    <span>Window</span>
    <span style={{flex: 1}} />
    {/* StatusMenu.icon: two 3.5×12 capsules in a 16-point template */}
    <div style={{width: 24, height: 24, position: 'relative', opacity: steadfast, scale: `${0.6 + 0.4 * steadfast}`}}>
      <div style={{position: 'absolute', left: 5.25, top: 3, width: 5.25, height: 18, borderRadius: 3, background: '#1d1d1f'}} />
      <div style={{position: 'absolute', left: 14.25, top: 3, width: 5.25, height: 18, borderRadius: 3, background: '#1d1d1f'}} />
    </div>
    <span style={{fontVariantNumeric: 'tabular-nums'}}>Sun 8 Nov 09:56</span>
  </div>
);

/** 0:32 — quit Steadfast from the menu bar; x.com still won't load. */
const KeepsWorkingInner = () => {
  const t = useTime();
  const enter = ramp(t, [0, 0.4], [0, 1], ease.out);
  const quit = ramp(t, [QUIT + 0.05, QUIT + 0.4], [0, 1], ease.in);
  const panelIn = ramp(t, [0.15, 0.45], [0, 1], ease.out);
  const browser = ramp(t, [1.95, 2.45], [0, 1], ease.out);
  const out = ramp(t, [3.72, 4.0], [0, 1], ease.in);
  const cursor = pathAt(
    [
      {t: 0.1, x: 1460, y: 760},
      {t: 0.85, x: 1545, y: 476},
      {t: 1.3, x: 1560, y: 490},
    ],
    t,
  );
  const S = 1.5;
  return (
    <>
      <AbsoluteFill style={{backgroundColor: '#EEF0F4'}} />
      <AbsoluteFill style={{opacity: 1 - out, filter: out > 0 ? `blur(${out * 16}px)` : undefined}}>
        <MenuBar steadfast={1 - quit} />
        {/* the app window, quitting */}
        <div
          style={{
            position: 'absolute',
            left: 170,
            top: 104,
            transformOrigin: '0 0',
            scale: `${S * (1 - quit * 0.06)}`,
            opacity: enter * (1 - quit),
          }}
        >
          <MacWindow width={WINDOW.width} height={610}>
            <ActiveScreen name={NAME} left={LEFT} unlock="Websites unlock at 11:30" domains={DOMAINS} />
          </MacWindow>
        </div>
        {/* the menu bar panel */}
        <div
          style={{
            position: 'absolute',
            right: 120,
            top: BAR + 10,
            transformOrigin: '70% 0',
            scale: `${S * (0.96 + 0.04 * panelIn)}`,
            opacity: panelIn * (1 - quit),
          }}
        >
          <MenuPanel
            left={LEFT}
            unlocks="Unlocks at 11:30"
            name={NAME}
            fraction={ELAPSED}
            quitHover={ramp(t, [0.7, 0.8], [0, 1])}
            quitPress={pulse(t, QUIT - 0.04, 0.16)}
          />
        </div>
        <Cursor x={cursor.x} y={cursor.y} press={pulse(t, QUIT - 0.05, 0.16)} opacity={1 - ramp(t, [1.3, 1.5], [0, 1])} scale={1.5} />

        {/* caption + the proof */}
        <div style={{position: 'absolute', left: 0, right: 0, top: 150, display: 'flex', justifyContent: 'center'}}>
          <Words
            parts={[{text: 'It keeps working'}, {text: ' even if you quit.', color: film.secondary}]}
            size={80}
            start={QUIT + 0.3}
          />
        </div>
        <div
          style={{
            position: 'absolute',
            left: (1920 - 1180 * 0.95) / 2,
            top: 330,
            transformOrigin: '0 0',
            scale: '0.95',
            opacity: browser,
            translate: `0 ${(1 - browser) * 160}px`,
          }}
        >
          <Browser
            width={1180}
            height={700}
            address="x.com"
            focused={false}
            caret={false}
            loading={ramp(t, [2.0, 2.3], [0.3, 0.82])}
            error={ramp(t, [2.3, 2.6], [0, 1], ease.out)}
            domain="x.com"
          />
        </div>
      </AbsoluteFill>
      <Sfx name="Quit click" src="rm-mouse-click" at={QUIT - 0.03} volume={0.85} />
      <Sfx name="App closes" src="air" at={QUIT + 0.05} volume={0.25} />
      <Sfx name="Browser in" src="air" at={1.9} volume={0.2} />
      <Sfx name="Still blocked" src="error" at={2.3} volume={0.8} />
    </>
  );
};

export const KeepsWorking = Interactive.create({Component: KeepsWorkingInner, layout: 'absolute-fill'});
