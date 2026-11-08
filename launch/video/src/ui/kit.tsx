/**
 * Steadfast's interface, rebuilt in HTML from Sources/SteadfastApp (Design.swift,
 * CedarDesign.swift, Dashboard.swift, CommitmentFlow.swift, StatusMenu.swift).
 * Units are SwiftUI points; the scene scales the whole window.
 */
import type React from 'react';
import {Img, staticFile} from 'remotion';
import {Sym} from '../components/Symbol';
import {PauseMark} from '../components/PauseMark';
import {radius, SF, type, ui} from '../theme';

export const font = (size: number, weight = 400, extra?: React.CSSProperties): React.CSSProperties => ({
  fontFamily: SF,
  fontSize: size,
  fontWeight: weight,
  ...extra,
});

/** PrimaryStyle: accent fill, top sheen, white hairline, accent shadow. */
export const PrimaryButton: React.FC<{
  readonly title: string;
  readonly press?: number; // 0…1
  readonly hover?: number;
  readonly minWidth?: number;
  readonly disabled?: boolean;
  readonly large?: boolean;
  readonly style?: React.CSSProperties;
}> = ({title, press = 0, hover = 0, minWidth = 76, disabled = false, large = false, style}) => {
  const r = large ? radius.row + 2 : radius.row;
  return (
    <div
      style={{
        position: 'relative',
        ...font(large ? 14 : type.body, 600),
        color: disabled ? ui.faint : '#fff',
        height: large ? 40 : 32,
        minWidth,
        padding: `0 ${large ? 22 : 16}px`,
        borderRadius: r,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        whiteSpace: 'nowrap',
        background: disabled
          ? ui.wash
          : `linear-gradient(to bottom, rgba(255,255,255,0.14), rgba(255,255,255,0) 50%), ${ui.accent}`,
        boxShadow: disabled
          ? `inset 0 0 0 1px ${ui.hairline}`
          : `inset 0 0 0 1px rgba(255,255,255,0.16), 0 2px ${6 + hover * 4}px rgba(${ui.accentRGB}, ${0.24 + hover * 0.14})`,
        scale: `${1 - press * 0.04}`,
        ...style,
      }}
    >
      {!disabled && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            borderRadius: r,
            background: `rgba(0,0,0,${press * 0.14})`,
            boxShadow: `inset 0 0 0 100px rgba(255,255,255,${hover * (1 - press) * 0.08})`,
          }}
        />
      )}
      <span style={{position: 'relative'}}>{title}</span>
    </div>
  );
};

/** SecondaryButton: wash plate + hairline, 13 medium. */
export const SecondaryButton: React.FC<{
  readonly title: string;
  readonly press?: number;
  readonly style?: React.CSSProperties;
}> = ({title, press = 0, style}) => (
  <div
    style={{
      ...font(type.body, 500),
      color: ui.ink,
      height: 32,
      minWidth: 76,
      padding: '0 16px',
      borderRadius: radius.row,
      background: press > 0 ? `rgba(0,0,0,${0.065 + press * 0.04})` : ui.wash,
      boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      whiteSpace: 'nowrap',
      scale: `${1 - press * 0.02}`,
      ...style,
    }}
  >
    {title}
  </div>
);

export const Card: React.FC<{readonly children: React.ReactNode; readonly style?: React.CSSProperties}> = ({
  children,
  style,
}) => (
  <div
    style={{
      background: ui.card,
      borderRadius: radius.card,
      boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
      overflow: 'hidden',
      ...style,
    }}
  >
    {children}
  </div>
);

export const Rule: React.FC<{readonly inset?: number}> = ({inset = 14}) => (
  <div style={{height: 1, background: ui.hairline, marginLeft: inset}} />
);

export const Titled: React.FC<{readonly title: string; readonly children: React.ReactNode}> = ({title, children}) => (
  <div style={{display: 'flex', flexDirection: 'column', gap: 8}}>
    <div style={{...font(type.chrome, 600), color: ui.muted, paddingLeft: 14}}>{title}</div>
    {children}
  </div>
);

export const SectionLabel: React.FC<{readonly title: string}> = ({title}) => (
  <div style={{...font(type.title, 400), color: ui.ink}}>{title}</div>
);

export const PageHeading: React.FC<{
  readonly title: string;
  readonly detail?: string;
  readonly trailing?: React.ReactNode;
}> = ({title, detail, trailing}) => (
  <div style={{display: 'flex', alignItems: 'flex-start', gap: 16}}>
    <div style={{display: 'flex', flexDirection: 'column', gap: 4, flex: 1}}>
      <div style={{...font(type.display, 600), letterSpacing: -0.6, color: ui.ink, lineHeight: '34px'}}>{title}</div>
      {detail && <div style={{...font(type.body), color: ui.muted}}>{detail}</div>}
    </div>
    <div style={{height: 34, display: 'flex', alignItems: 'center'}}>{trailing}</div>
  </div>
);

/** PageNavPill */
export const NavPill: React.FC<{readonly selected: 'Today' | 'Routines' | 'Progress'}> = ({selected}) => (
  <div
    style={{
      display: 'flex',
      gap: 2,
      padding: 3,
      background: ui.wash,
      borderRadius: radius.control + 3,
      boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
    }}
  >
    {(['Today', 'Routines', 'Progress'] as const).map((p) => {
      const on = p === selected;
      return (
        <div
          key={p}
          style={{
            ...font(type.chrome, on ? 600 : 400),
            color: on ? ui.ink : ui.muted,
            padding: '0 14px',
            height: 28,
            display: 'flex',
            alignItems: 'center',
            borderRadius: radius.control,
            background: on ? '#fff' : 'transparent',
            boxShadow: on ? `inset 0 0 0 1px ${ui.hairline}` : undefined,
          }}
        >
          {p}
        </div>
      );
    })}
  </div>
);

/** RootView.header */
export const AppHeader: React.FC<{
  readonly page?: 'Today' | 'Routines' | 'Progress';
  readonly brandClearance?: number;
}> = ({page = 'Today', brandClearance = 0}) => (
  <div style={{position: 'relative', height: 34, display: 'flex', alignItems: 'center'}}>
    <div style={{display: 'flex', alignItems: 'center', gap: 8, paddingLeft: brandClearance}}>
      <PauseMark width={14} height={17} color={ui.accent} />
      <div style={{...font(type.body, 600), letterSpacing: -0.2, color: ui.ink}}>Steadfast</div>
    </div>
    <div style={{position: 'absolute', left: 0, right: 0, display: 'flex', justifyContent: 'center'}}>
      <NavPill selected={page} />
    </div>
    <div style={{flex: 1}} />
    <div
      style={{
        width: 28,
        height: 28,
        borderRadius: radius.control,
        background: ui.wash,
        boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
      }}
    >
      <Sym name="gearshape" size={11} color={ui.muted} />
    </div>
  </div>
);

/** ChoiceTile — the pickable tile used for websites, apps and aims. */
export const ChoiceTile: React.FC<{
  readonly title: string;
  readonly symbol: string;
  readonly mark: 'off' | 'on' | 'partial';
  readonly markIn?: number; // 0…1 spring for the checkmark
  readonly press?: number;
}> = ({title, symbol, mark, markIn = 1, press = 0}) => {
  const on = mark === 'on';
  return (
    <div
      style={{
        height: 40,
        padding: '0 14px',
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        borderRadius: radius.row,
        background: on ? `rgba(${ui.accentRGB}, 0.14)` : ui.wash,
        boxShadow: `inset 0 0 0 1px ${on ? `rgba(${ui.accentRGB}, 0.55)` : ui.hairline}`,
        scale: `${1 - press * 0.02}`,
      }}
    >
      <div style={{width: 20, display: 'flex', justifyContent: 'center'}}>
        <Sym name={symbol} size={15} color={on ? ui.accent : ui.muted} />
      </div>
      <div style={{...font(type.body, 500), color: ui.ink, flex: 1, whiteSpace: 'nowrap'}}>{title}</div>
      {mark !== 'off' && (
        <div
          style={{
            position: 'relative',
            width: 16,
            height: 16,
            scale: `${0.25 + 0.75 * markIn}`,
            opacity: markIn,
          }}
        >
          <div style={{position: 'absolute', inset: 2, borderRadius: 99, background: '#fff'}} />
          <Sym
            name={mark === 'on' ? 'checkmark.circle.fill' : 'minus.circle'}
            size={14}
            color={ui.accent}
            style={{position: 'absolute', left: -0.3, top: -0.3, width: 16.8, height: 16.8}}
          />
        </div>
      )}
    </div>
  );
};

/** BlockDurationControls — the four presets plus Custom, with a sliding plate. */
export const DurationTrack: React.FC<{
  readonly position: number; // continuous index of the plate (0 = 30 min … 4 = Custom)
  readonly selected: number;
}> = ({position, selected}) => {
  const labels = ['30 min', '1 hour', '2 hours', '4 hours', 'Custom'];
  return (
    <div
      style={{
        position: 'relative',
        display: 'flex',
        gap: 2,
        padding: 3,
        background: ui.wash,
        borderRadius: radius.row + 3,
        boxShadow: `inset 0 0 0 1px ${ui.hairline}`,
      }}
    >
      <div
        style={{
          position: 'absolute',
          top: 3,
          bottom: 3,
          left: `calc(3px + ${position} * ((100% - 6px - 8px) / 5 + 2px))`,
          width: 'calc((100% - 6px - 8px) / 5)',
          borderRadius: radius.row,
          background: `rgba(${ui.accentRGB}, 0.16)`,
          boxShadow: `inset 0 0 0 1px rgba(${ui.accentRGB}, 0.5)`,
        }}
      />
      {labels.map((l, i) => (
        <div
          key={l}
          style={{
            position: 'relative',
            flex: 1,
            height: 30,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            ...font(type.chrome, i === selected ? 600 : 500),
            color: i === selected ? ui.ink : ui.muted,
            fontVariantNumeric: 'tabular-nums',
          }}
        >
          {l}
        </div>
      ))}
    </div>
  );
};

/** A macOS 26 window: rounded, hairline, deep shadow, traffic lights. */
export const MacWindow: React.FC<{
  readonly width: number;
  readonly height: number;
  readonly children: React.ReactNode;
  readonly background?: string;
  readonly style?: React.CSSProperties;
  readonly dim?: number;
}> = ({width, height, children, background = ui.window, style, dim = 0}) => (
  <div
    style={{
      position: 'relative',
      width,
      height,
      borderRadius: 18,
      background,
      overflow: 'hidden',
      boxShadow:
        '0 0 0 0.5px rgba(0,0,0,0.22), 0 1px 1px rgba(0,0,0,0.04), 0 22px 48px rgba(0,0,0,0.22), 0 60px 140px rgba(0,0,0,0.22)',
      ...style,
    }}
  >
    {/* measured from a macOS 26 NSWindow: 14 pt buttons at x 9, 32, 55, 9 pt from the top */}
    <div style={{position: 'absolute', left: 9, top: 9, display: 'flex', gap: 9, zIndex: 5}}>
      {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
        <div
          key={c}
          style={{width: 14, height: 14, borderRadius: 7, background: c, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)'}}
        />
      ))}
    </div>
    {children}
    {dim > 0 && <div style={{position: 'absolute', inset: 0, background: `rgba(0,0,0,${dim * 0.08})`, zIndex: 8}} />}
  </div>
);

/** Plate — a sheet: title, subtitle, close door, content, hairline, foot. */
export const Plate: React.FC<{
  readonly title: string;
  readonly subtitle?: string;
  readonly children: React.ReactNode;
  readonly foot?: React.ReactNode;
  readonly style?: React.CSSProperties;
}> = ({title, subtitle, children, foot, style}) => (
  <div
    style={{
      width: 520,
      background: ui.ground,
      borderRadius: 16,
      overflow: 'hidden',
      boxShadow: '0 0 0 0.5px rgba(0,0,0,0.18), 0 12px 32px rgba(0,0,0,0.18), 0 40px 90px rgba(0,0,0,0.16)',
      ...style,
    }}
  >
    <div style={{display: 'flex', alignItems: 'flex-start', gap: 12, padding: '22px 24px 16px'}}>
      <div style={{display: 'flex', flexDirection: 'column', gap: 3, flex: 1}}>
        <div style={{...font(20, 600), letterSpacing: -0.3, color: ui.ink}}>{title}</div>
        {subtitle && <div style={{...font(type.chrome), color: ui.muted}}>{subtitle}</div>}
      </div>
      <div style={{width: 28, height: 28, display: 'flex', alignItems: 'center', justifyContent: 'center'}}>
        <Sym name="xmark" size={13} color={ui.muted} />
      </div>
    </div>
    <div style={{padding: '0 24px'}}>{children}</div>
    {foot ? (
      <>
        <div style={{height: 1, background: ui.hairline, marginTop: 18}} />
        <div style={{padding: '14px 24px'}}>{foot}</div>
      </>
    ) : (
      <div style={{height: 20}} />
    )}
  </div>
);

export const LockRow: React.FC<{readonly domain: string; readonly trailing?: string}> = ({domain, trailing}) => (
  <div style={{display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px', minHeight: 36}}>
    <div style={{width: 16, display: 'flex', justifyContent: 'center'}}>
      <Sym name="lock.fill" size={11} color={ui.muted} />
    </div>
    <div style={{...font(type.body), color: ui.ink, flex: 1}}>{domain}</div>
    {trailing && (
      <div style={{...font(type.chrome), color: ui.muted, fontVariantNumeric: 'tabular-nums'}}>{trailing}</div>
    )}
  </div>
);

export const AppIcon: React.FC<{readonly name: string; readonly size: number; readonly style?: React.CSSProperties}> = ({
  name,
  size,
  style,
}) => <Img src={staticFile(`img/apps/${name}.png`)} style={{width: size, height: size, ...style}} />;
