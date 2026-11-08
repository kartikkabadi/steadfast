/**
 * Whole Steadfast screens, laid out like RootView: a 640-point column, the
 * header, the page, and the pinned draft bar.
 */
import type React from 'react';
import {Sym} from '../components/Symbol';
import {PauseMark} from '../components/PauseMark';
import {radius, type, ui} from '../theme';
import {
  AppHeader,
  Card,
  ChoiceTile,
  DurationTrack,
  font,
  LockRow,
  PageHeading,
  Plate,
  PrimaryButton,
  Rule,
  SecondaryButton,
  SectionLabel,
  Titled,
} from './kit';

export const WINDOW = {width: 720, height: 640};
const COLUMN = 640;

const Column: React.FC<{readonly children: React.ReactNode; readonly style?: React.CSSProperties}> = ({
  children,
  style,
}) => (
  <div style={{width: COLUMN, margin: '0 auto', ...style}}>
    {children}
  </div>
);

/** RootView.brandClearance keeps the wordmark clear of the traffic lights. */
const BRAND_CLEARANCE = Math.max(0, 78 - (WINDOW.width - COLUMN) / 2);

export const Header: React.FC<{readonly page?: 'Today' | 'Routines' | 'Progress'}> = ({page}) => (
  // The real header sits under the 32 pt title bar (centre ~61 pt); this keeps the
  // header block's 70 pt height, so everything below stays where it was.
  <Column style={{paddingTop: 32, paddingBottom: 4}}>
    <AppHeader page={page} brandClearance={BRAND_CLEARANCE} />
  </Column>
);

/** The draft composer ("New block") with its pinned bar. */
export const Composer: React.FC<{
  readonly purpose: string;
  readonly caret: boolean;
  readonly focused: boolean;
  readonly websites: string; // detail line
  readonly websitesHover?: number;
  readonly apps?: string;
  readonly durationPos: number;
  readonly durationSel: number;
  readonly summary: string | null;
  readonly reviewPress?: number;
  readonly reviewHover?: number;
}> = ({
  purpose,
  caret,
  focused,
  websites,
  websitesHover = 0,
  apps = 'None chosen',
  durationPos,
  durationSel,
  summary,
  reviewPress = 0,
  reviewHover = 0,
}) => (
  <div style={{position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column'}}>
    <Header />
    <Column style={{paddingTop: 12, display: 'flex', flexDirection: 'column', gap: 24, flex: 1}}>
      <PageHeading title="New block" trailing={<SecondaryButton title="Cancel" />} />
      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        <SectionLabel title="What this time is for · optional" />
        <div
          style={{
            height: 32,
            borderRadius: radius.control,
            background: ui.wash,
            boxShadow: focused
              ? `inset 0 0 0 1px ${ui.hairline}, 0 0 0 3.5px rgba(${ui.accentRGB}, 0.35)`
              : `inset 0 0 0 1px ${ui.hairline}`,
            padding: '0 14px',
            display: 'flex',
            alignItems: 'center',
            ...font(type.body),
            color: purpose ? ui.ink : ui.muted,
          }}
        >
          {purpose || (focused ? '' : 'Think, make something, or take a break')}
          {focused && (
            <span
              style={{
                display: 'inline-block',
                width: 1.5,
                height: 16,
                marginLeft: 1,
                background: ui.accent,
                opacity: caret ? 1 : 0,
              }}
            />
          )}
          {focused && !purpose && (
            <span style={{color: ui.muted, marginLeft: -1.5}}>Think, make something, or take a break</span>
          )}
        </div>
      </div>
      <div style={{display: 'flex', flexDirection: 'column'}}>
        <DistractionRow title="Websites" detail={websites} hover={websitesHover} />
        <Rule inset={0} />
        <DistractionRow title="Apps" detail={apps} />
      </div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 10}}>
        <SectionLabel title="Duration" />
        <DurationTrack position={durationPos} selected={durationSel} />
      </div>
    </Column>
    <DraftBar summary={summary} press={reviewPress} hover={reviewHover} />
  </div>
);

const DistractionRow: React.FC<{readonly title: string; readonly detail: string; readonly hover?: number}> = ({
  title,
  detail,
  hover = 0,
}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 20,
      padding: '16px 0',
      position: 'relative',
    }}
  >
    <div
      style={{
        position: 'absolute',
        inset: '4px -10px',
        borderRadius: radius.row,
        background: `rgba(0,0,0,${hover * 0.04})`,
      }}
    />
    <div style={{display: 'flex', flexDirection: 'column', gap: 6, flex: 1, position: 'relative'}}>
      <div style={{...font(type.body, 500), color: ui.ink}}>{title}</div>
      <div style={{...font(type.chrome), color: ui.muted}}>{detail}</div>
    </div>
    <div style={{...font(type.chrome, 500), color: ui.accent, position: 'relative'}}>Choose…</div>
    <Sym name="chevron.right" size={9} color={ui.muted} style={{position: 'relative'}} />
  </div>
);

const DraftBar: React.FC<{readonly summary: string | null; readonly press: number; readonly hover: number}> = ({
  summary,
  press,
  hover,
}) => (
  <div
    style={{
      borderTop: `1px solid ${ui.hairline}`,
      background: ui.window,
      padding: '14px 0',
    }}
  >
    <Column style={{display: 'flex', alignItems: 'center', gap: 12}}>
      <div
        style={{
          ...font(type.body),
          color: summary ? ui.ink : ui.muted,
          flex: 1,
          fontVariantNumeric: 'tabular-nums',
          whiteSpace: 'nowrap',
        }}
      >
        {summary ?? 'Choose at least one website or app'}
      </div>
      <PrimaryButton title="Review Block" minWidth={152} disabled={!summary} press={press} hover={hover} />
    </Column>
  </div>
);

export const QUICK = [
  {name: 'YouTube', symbol: 'play.rectangle', domains: ['youtube.com', 'youtu.be']},
  {name: 'Instagram', symbol: 'camera', domains: ['instagram.com']},
  {name: 'X / Twitter', symbol: 'bubble', domains: ['x.com', 'twitter.com']},
  {name: 'Reddit', symbol: 'text.bubble', domains: ['reddit.com']},
  {name: 'TikTok', symbol: 'music.note', domains: ['tiktok.com']},
  {name: 'Netflix', symbol: 'tv', domains: ['netflix.com']},
];

/** Category counts with the Popular domains removed, as WebsiteEditor shows them. */
const CATEGORIES = [
  ['Social', 11],
  ['Streaming', 22],
  ['Forums & feeds', 14],
  ['News', 27],
  ['Shopping', 25],
] as const;

/** WebsitePicker sheet ("Choose Websites"). */
export const WebsitePicker: React.FC<{
  readonly marks: Record<string, number>; // tile name → 0…1 check progress
  readonly presses: Record<string, number>;
  readonly count: number;
  readonly donePress?: number;
}> = ({marks, presses, count, donePress = 0}) => (
  <Plate
    title="Choose Websites"
    subtitle="Blocked websites and their subdomains won't load until the block ends"
    foot={
      <div style={{display: 'flex', alignItems: 'center', gap: 8}}>
        <div style={{...font(type.body), color: ui.muted, flex: 1, fontVariantNumeric: 'tabular-nums'}}>
          {count === 0 ? 'Nothing selected' : `${count} selected`}
        </div>
        <SecondaryButton title="Clear" style={{opacity: count === 0 ? 0.35 : 1}} />
        <PrimaryButton title="Done" press={donePress} />
      </div>
    }
  >
    <div style={{display: 'flex', flexDirection: 'column', gap: 14}}>
      <div
        style={{
          height: 36,
          borderRadius: radius.row,
          background: ui.wash,
          padding: '0 14px',
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          ...font(type.body),
          color: ui.muted,
        }}
      >
        <Sym name="magnifyingglass" size={13} color={ui.muted} />
        Search websites or paste a domain
      </div>
      <div style={{height: 300, overflow: 'hidden', display: 'flex', flexDirection: 'column', gap: 12}}>
        <div style={{flexShrink: 0}}>
        <Titled title="Popular">
          <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8}}>
            {QUICK.map((q) => {
              const m = marks[q.name] ?? 0;
              return (
                <ChoiceTile
                  key={q.name}
                  title={q.name}
                  symbol={q.symbol}
                  mark={m > 0 ? 'on' : 'off'}
                  markIn={m}
                  press={presses[q.name] ?? 0}
                />
              );
            })}
          </div>
        </Titled>
        </div>
        {CATEGORIES.map(([name, n]) => (
          <Card key={name} style={{flexShrink: 0}}>
            <div style={{display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', height: 36}}>
              <Sym name="chevron.right" size={9} color={ui.muted} />
              <div style={{...font(type.body, 500), color: ui.ink}}>{name}</div>
              <div style={{...font(type.caption), color: ui.muted, flex: 1}}>{n}</div>
              <div
                style={{
                  ...font(type.chrome, 500),
                  color: ui.ink,
                  height: 28,
                  minWidth: 76,
                  padding: '0 12px',
                  borderRadius: radius.control,
                  background: ui.wash,
                  boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                }}
              >
                Add All
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  </Plate>
);

/** CommitmentFlow review sheet. */
export const ReviewSheet: React.FC<{
  readonly name: string;
  readonly domains: string[];
  readonly ends: string;
  readonly duration: string;
  readonly press?: number;
  readonly hover?: number;
}> = ({name, domains, ends, duration, press = 0, hover = 0}) => (
  <Plate
    title={`Start ${name}?`}
    subtitle={`${domains.length} websites · ends at ${ends}`}
    foot={
      <div style={{display: 'flex', justifyContent: 'flex-end', gap: 8}}>
        <SecondaryButton title="Back" />
        <PrimaryButton title={`Block for ${duration}`} minWidth={120} press={press} hover={hover} />
      </div>
    }
  >
    <div style={{display: 'flex', flexDirection: 'column', gap: 14}}>
      <Titled title="Websites">
        <Card style={{height: Math.min(168, domains.length * 37)}}>
          {domains.map((d, i) => (
            <div key={d}>
              {i > 0 && <Rule />}
              <LockRow domain={d} />
            </div>
          ))}
        </Card>
      </Titled>
      <div style={{display: 'flex', gap: 8, padding: '0 14px', alignItems: 'baseline'}}>
        <Sym name="hourglass" size={11} color={ui.muted} style={{translate: '0 1px'}} />
        <div style={{...font(type.chrome), color: ui.muted, lineHeight: 1.35}}>
          Once it starts, this block can't be ended early. It keeps running even if you quit Steadfast.
        </div>
      </div>
    </div>
  </Plate>
);

/** Active block page (BlockHold + blocked list). */
export const ActiveScreen: React.FC<{
  readonly name: string;
  readonly left: string;
  readonly unlock: string;
  readonly domains: string[];
  readonly reveal?: number; // 0…1 for staggered entrance
}> = ({name, left, unlock, domains, reveal = 1}) => {
  const r = (i: number) => {
    const p = Math.max(0, Math.min(1, reveal * 6 - i));
    return {opacity: p, translate: `0 ${(1 - p) * 10}px`};
  };
  return (
    <div style={{position: 'absolute', inset: 0}}>
      <Header />
      <Column style={{paddingTop: 12, display: 'flex', flexDirection: 'column', gap: 28}}>
        <div style={{display: 'flex', flexDirection: 'column', gap: 20, ...r(0)}}>
          <PageHeading title="Active blocks" trailing={<SecondaryButton title="Add Another Block" />} />
          <div style={{display: 'flex', flexDirection: 'column', gap: 20, padding: '12px 0'}}>
            <div style={{...font(34, 600), letterSpacing: -0.8, color: ui.ink, ...r(1)}}>{name}</div>
            <div style={{display: 'flex', flexDirection: 'column', gap: 8, ...r(2)}}>
              <div style={{...font(25, 500), color: ui.ink, fontVariantNumeric: 'tabular-nums'}}>{left}</div>
              <div style={{...font(type.body), color: ui.muted}}>{unlock}</div>
            </div>
            <div style={{...font(type.chrome), color: ui.muted, ...r(3)}}>
              You can close Steadfast. Your blocks keep running.
            </div>
          </div>
          <div style={r(4)}>
            <Titled title={`Blocked · ${domains.length}`}>
              <Card>
                {domains.map((d, i) => (
                  <div key={d}>
                    {i > 0 && <Rule />}
                    <LockRow domain={d} />
                  </div>
                ))}
              </Card>
            </Titled>
          </div>
        </div>
      </Column>
    </div>
  );
};

/** StatusMenu — the menu bar panel. */
export const MenuPanel: React.FC<{
  readonly left: string;
  readonly unlocks: string;
  readonly name: string;
  readonly fraction: number;
  readonly quitHover?: number;
  readonly quitPress?: number;
}> = ({left, unlocks, name, fraction, quitHover = 0, quitPress = 0}) => {
  const row = (label: string, icon: string, detail?: string, hover = 0, press = 0) => (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 10,
        height: 30,
        padding: '0 8px',
        margin: '0 -8px',
        borderRadius: radius.control,
        background: `rgba(0,0,0,${hover * 0.05 + press * 0.04})`,
      }}
    >
      <div style={{width: 18, display: 'flex', justifyContent: 'center'}}>
        <Sym name={icon} size={12} color={ui.muted} />
      </div>
      <div style={{...font(type.chrome), color: ui.ink, flex: 1}}>{label}</div>
      {detail && <div style={{...font(type.chrome), color: ui.faint}}>{detail}</div>}
    </div>
  );
  const divider = <div style={{height: 1, background: ui.hairline, margin: '4px 0'}} />;
  const ring = 44;
  const sw = 4.4;
  const rr = (ring - sw) / 2;
  const circ = 2 * Math.PI * rr;
  return (
    <div
      style={{
        width: 300,
        padding: 16,
        borderRadius: 18,
        background: 'rgba(248,248,248,0.96)',
        boxShadow: '0 0 0 0.5px rgba(0,0,0,0.2), 0 18px 50px rgba(0,0,0,0.22)',
        display: 'flex',
        flexDirection: 'column',
        gap: 14,
      }}
    >
      <div style={{display: 'flex', alignItems: 'center', gap: 7}}>
        <PauseMark width={12} height={14} color={ui.accent} />
        <div style={{...font(type.body, 600), color: ui.ink, flex: 1}}>Steadfast</div>
        <div
          style={{
            ...font(type.caption, 600),
            color: ui.accent,
            padding: '2px 7px',
            borderRadius: 99,
            background: `rgba(${ui.accentRGB}, 0.14)`,
          }}
        >
          Blocking
        </div>
      </div>
      <div style={{display: 'flex', alignItems: 'center', gap: 12}}>
        <svg width={ring} height={ring}>
          <circle cx={ring / 2} cy={ring / 2} r={rr} stroke={ui.wash} strokeWidth={sw} fill="none" />
          <circle
            cx={ring / 2}
            cy={ring / 2}
            r={rr}
            stroke={ui.accent}
            strokeWidth={sw}
            fill="none"
            strokeLinecap="round"
            strokeDasharray={`${Math.max(0.012, fraction) * circ} ${circ}`}
            transform={`rotate(-90 ${ring / 2} ${ring / 2})`}
          />
          <foreignObject x={ring / 2 - 6} y={ring / 2 - 7.5} width={12} height={15}>
            <PauseMark width={9.7} height={12.3} color={ui.accent} style={{margin: '1.35px 1.15px'}} />
          </foreignObject>
        </svg>
        <div style={{display: 'flex', flexDirection: 'column', gap: 2}}>
          <div style={{...font(20, 600), letterSpacing: -0.4, color: ui.ink, fontVariantNumeric: 'tabular-nums'}}>
            {left}
          </div>
          <div style={{...font(type.chrome), color: ui.muted}}>{unlocks}</div>
        </div>
      </div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 3}}>
        <div style={{...font(type.chrome), color: ui.ink}}>{name}</div>
        <div style={{...font(type.chrome), color: ui.muted}}>14 h with blocks active in the past 7 days</div>
      </div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 2}}>
        {row('Add Another Block', 'plus')}
        {divider}
        {row('Open Steadfast', 'macwindow')}
        {row('Daily Limits', 'hourglass')}
        {divider}
        {row('Quit Steadfast', 'power', '⌘Q', quitHover, quitPress)}
      </div>
    </div>
  );
};
