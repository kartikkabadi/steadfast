import {AbsoluteFill, Interactive, interpolate, Sequence, useVideoConfig} from 'remotion';
import {Sfx} from '../components/Sfx';
import {Sym} from '../components/Symbol';
import {Words} from '../components/Words';
import {ramp, useTime} from '../lib/anim';
import {ease, film, radius, type, ui} from '../theme';
import {AppIcon, Card, font, Rule, SecondaryButton, SectionLabel} from '../ui/kit';

const K = 2.0; // UI scale on the stage

/** Headline at the top, a real piece of the app rising beneath it. */
const Beat: React.FC<{
  readonly title: string;
  readonly dim?: string;
  readonly children: React.ReactNode;
  readonly width: number;
}> = ({title, dim, children, width}) => {
  const t = useTime();
  const card = ramp(t, [0.12, 0.62], [0, 1], ease.out);
  const out = ramp(t, [1.8, 2.0], [0, 1], ease.in);
  return (
    <AbsoluteFill
      style={{
        opacity: 1 - out,
        filter: out > 0 ? `blur(${out * 14}px)` : undefined,
        justifyContent: 'center',
        alignItems: 'center',
        gap: 72,
        paddingBottom: 20,
      }}
    >
      <Words parts={[{text: title}, ...(dim ? [{text: ` ${dim}`, color: film.secondary}] : [])]} size={92} start={0} />
      {/* zoom (not scale) so the scaled card still takes its real height in the centred stack */}
      <div
        style={{
          width,
          zoom: K,
          opacity: card,
          translate: `0 ${(1 - card) * 35}px`, // zoomed: 70 px on stage
          filter: card < 1 ? `blur(${(1 - card) * 5}px)` : undefined,
        }}
      >
        <div
          style={{
            background: ui.window,
            borderRadius: 18,
            padding: 22,
            boxShadow: '0 0 0 0.5px rgba(0,0,0,0.14), 0 14px 40px rgba(0,0,0,0.10), 0 40px 100px rgba(0,0,0,0.10)',
          }}
        >
          {children}
        </div>
      </div>
    </AbsoluteFill>
  );
};

/** Dashboard.limitsSummary — youtube.com runs out and locks until midnight. */
const Limits = () => {
  const t = useTime();
  const left = Math.round(interpolate(t, [0.55, 1.25], [30, 0], {extrapolateLeft: 'clamp', extrapolateRight: 'clamp', easing: ease.inOut}));
  const reached = t >= 1.3;
  return (
    <Beat title="Daily website limits." width={560}>
      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        <SectionLabel title="Daily limits" />
        <Card>
          <div style={{display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px', minHeight: 36}}>
            <div style={{...font(type.body), color: ui.ink, flex: 1}}>youtube.com</div>
            <div style={{...font(type.chrome), color: reached ? ui.danger : ui.muted, fontVariantNumeric: 'tabular-nums'}}>
              {reached ? 'Limit reached · resets at midnight' : `${Math.max(left, 1)} min left`}
            </div>
          </div>
          <Rule />
          <div style={{display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px', minHeight: 36}}>
            <div style={{...font(type.body), color: ui.ink, flex: 1}}>reddit.com</div>
            <div style={{...font(type.chrome), color: ui.muted}}>15 min left</div>
          </div>
          <Rule />
          <div style={{display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px', minHeight: 36}}>
            <div style={{...font(type.body), color: ui.ink, flex: 1}}>instagram.com</div>
            <div style={{...font(type.chrome), color: ui.muted}}>22 min left</div>
          </div>
          <Rule inset={0} />
          <div style={{display: 'flex', alignItems: 'center', padding: '0 14px', minHeight: 36}}>
            <div style={{...font(type.chrome, 500), color: ui.muted, flex: 1}}>Edit Limits</div>
            <Sym name="chevron.right" size={11} color={ui.faint} />
          </div>
        </Card>
      </div>
      <Sfx name="Limit reached" src="deny" at={1.3} volume={0.4} />
    </Beat>
  );
};

/** RoutinesView row with its weekly schedule switching on. */
const Routines = () => {
  const t = useTime();
  const on = ramp(t, [0.85, 1.05], [0, 1], ease.settle);
  const enabled = on > 0.5;
  const toggle = (
    <div
      style={{
        width: 26,
        height: 15,
        borderRadius: 8,
        background: `rgba(${on > 0 ? ui.accentRGB : '0,0,0'}, ${0.12 + on * 0.88})`,
        position: 'relative',
        boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.08)',
      }}
    >
      <div
        style={{
          position: 'absolute',
          top: 1.5,
          left: 1.5 + on * 11,
          width: 12,
          height: 12,
          borderRadius: 6,
          background: '#fff',
          boxShadow: '0 1px 2px rgba(0,0,0,0.25)',
        }}
      />
    </div>
  );
  const row = (name: string, detail: string, schedule: boolean) => (
    <div style={{padding: '14px 14px', display: 'flex', flexDirection: 'column', gap: 10}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 8}}>
        <div style={{display: 'flex', flexDirection: 'column', gap: 3, flex: 1}}>
          <div style={{...font(type.title, 600), letterSpacing: -0.2, color: ui.ink}}>{name}</div>
          <div style={{...font(type.chrome), color: ui.muted, whiteSpace: 'nowrap'}}>{detail}</div>
        </div>
        <div style={{width: 24, display: 'flex', justifyContent: 'center'}}>
          <Sym name="star" size={11} color={ui.muted} />
        </div>
        <div style={{width: 24, display: 'flex', justifyContent: 'center'}}>
          <Sym name="ellipsis" size={11} color={ui.muted} />
        </div>
        <SecondaryButton title="Start" style={{marginLeft: 4}} />
      </div>
      {schedule && (
        <div style={{display: 'flex', alignItems: 'center', gap: 6, paddingTop: 10, borderTop: `1px solid ${ui.hairline}`}}>
          <Sym name="calendar.badge.clock" size={11} color={enabled ? ui.accent : ui.faint} />
          <div style={{...font(type.chrome, 500), color: enabled ? ui.ink : ui.muted, flex: 1}}>Weekdays at 09:00</div>
          <div style={{...font(type.chrome), color: ui.muted, fontVariantNumeric: 'tabular-nums'}}>
            {enabled ? 'Next tomorrow at 09:00' : 'Off'}
          </div>
          {toggle}
        </div>
      )}
    </div>
  );
  return (
    <Beat title="Scheduled routines." width={560}>
      <Card style={{background: '#fff'}}>
        {row('morning focus', '1 hour  ·  x.com, youtube.com', true)}
        <Rule />
        {row('reading', '30 minutes  ·  news.ycombinator.com, reddit.com', false)}
      </Card>
      <Sfx name="Schedule on" src="rm-switch" at={0.75} volume={0.6} />
    </Beat>
  );
};

/** ActivityView — a local record; nothing is uploaded. */
const Activity = () => {
  const rows = [
    ['xcode', 'Xcode', '1 h 27 min'],
    ['google-chrome', 'Google Chrome', '1 h 5 min'],
    ['messages', 'Messages', '22 min'],
    ['music', 'Music', '12 min'],
  ] as const;
  return (
    <Beat title="Activity stays on your Mac." width={560}>
      <div style={{display: 'flex', flexDirection: 'column', gap: 4, marginBottom: 14}}>
        <div style={{...font(type.display, 600), letterSpacing: -0.6, color: ui.ink}}>Where your time goes</div>
        <div style={{...font(type.body), color: ui.muted}}>App and website time only. Nothing is uploaded.</div>
      </div>
      {rows.map(([icon, name, time], i) => (
        <div key={name}>
          {i > 0 && <div style={{height: 1, background: ui.hairline}} />}
          <div style={{display: 'flex', alignItems: 'center', gap: 10, height: 44}}>
            <AppIcon name={icon} size={22} />
            <div style={{...font(type.body), color: ui.ink, flex: 1}}>{name}</div>
            <div style={{...font(type.body), color: ui.muted, fontVariantNumeric: 'tabular-nums'}}>{time}</div>
            <div
              style={{
                ...font(type.chrome, 500),
                color: ui.ink,
                height: 28,
                padding: '0 12px',
                borderRadius: radius.control,
                background: ui.wash,
                boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
                display: 'flex',
                alignItems: 'center',
              }}
            >
              Block…
            </div>
          </div>
        </div>
      ))}
    </Beat>
  );
};

/** "No account. No analytics." on two beats. */
const NoAccount = () => {
  const t = useTime();
  const out = ramp(t, [1.8, 2.0], [0, 1], ease.in);
  return (
    <AbsoluteFill
      style={{
        justifyContent: 'center',
        alignItems: 'center',
        opacity: 1 - out,
        filter: out > 0 ? `blur(${out * 14}px)` : undefined,
      }}
    >
      <Words parts={[{text: 'No account.'}]} size={150} start={0} weight={650} />
      <Words parts={[{text: 'No analytics.', color: film.brand}]} size={150} start={0.5} weight={650} />
    </AbsoluteFill>
  );
};

/** 0:40 — the second drop: four features, one per bar. */
const FeaturesInner = () => {
  const {fps} = useVideoConfig();
  return (
    <>
      <AbsoluteFill style={{backgroundColor: film.stage}} />
      <Sequence name="Daily limits" durationInFrames={2 * fps}>
        <Limits />
      </Sequence>
      <Sequence name="Routines" from={2 * fps} durationInFrames={2 * fps}>
        <Routines />
      </Sequence>
      <Sequence name="Activity" from={4 * fps} durationInFrames={2 * fps}>
        <Activity />
      </Sequence>
      <Sequence name="No account" from={6 * fps} durationInFrames={2 * fps}>
        <NoAccount />
      </Sequence>
    </>
  );
};

export const Features = Interactive.create({Component: FeaturesInner, layout: 'absolute-fill'});
