import type React from 'react';
import {Sym} from './Symbol';
import {SF} from '../theme';

/**
 * A neutral macOS 26 browser window in Safari's shape. The error page carries
 * Safari's real wording for a name that doesn't resolve — which is exactly what
 * Steadfast's DNS block produces (NXDOMAIN for the blocked domain).
 */
export const Browser: React.FC<{
  readonly width: number;
  readonly height: number;
  readonly address: string;
  readonly focused: boolean;
  readonly caret: boolean;
  readonly loading: number; // 0…1 progress, <0 hidden
  readonly error: number; // 0…1 reveal of the error page
  readonly domain: string;
  readonly style?: React.CSSProperties;
}> = ({width, height, address, focused, caret, loading, error, domain, style}) => {
  const bar = 52;
  return (
    <div
      style={{
        position: 'relative',
        width,
        height,
        borderRadius: 18,
        overflow: 'hidden',
        background: '#fff',
        boxShadow:
          '0 0 0 0.5px rgba(0,0,0,0.22), 0 22px 48px rgba(0,0,0,0.20), 0 60px 140px rgba(0,0,0,0.20)',
        fontFamily: SF,
        ...style,
      }}
    >
      <div
        style={{
          position: 'relative',
          height: bar,
          background: 'rgb(246,246,246)',
          borderBottom: '1px solid rgb(226,226,226)',
          display: 'flex',
          alignItems: 'center',
          padding: '0 16px',
          gap: 18,
        }}
      >
        <div style={{display: 'flex', gap: 8}}>
          {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
            <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)'}} />
          ))}
        </div>
        <Sym name="sidebar.left" size={15} color="rgb(110,110,115)" />
        <div style={{display: 'flex', gap: 18, alignItems: 'center'}}>
          <Sym name="chevron.left" size={14} color="rgb(110,110,115)" />
          <Sym name="chevron.right" size={14} color="rgb(190,190,195)" />
        </div>
        {/* the address field is centred on the window, not between the button groups */}
        <div style={{flex: 1}} />
        <div style={{position: 'absolute', left: 0, right: 0, top: 0, bottom: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none'}}>
          <div
            style={{
              position: 'relative',
              width: Math.min(560, width * 0.5),
              height: 34,
              borderRadius: 10,
              background: focused ? '#fff' : 'rgb(232,232,234)',
              boxShadow: focused
                ? '0 0 0 1px rgba(0,122,255,0.55), 0 0 0 4px rgba(0,122,255,0.18)'
                : 'inset 0 0 0 0.5px rgba(0,0,0,0.04)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: focused ? 'flex-start' : 'center',
              padding: '0 14px',
              fontSize: 14,
              color: address ? '#1d1d1f' : 'rgb(140,140,145)',
              overflow: 'hidden',
            }}
          >
            <span>{address || (focused ? '' : 'Search or enter website name')}</span>
            {focused && (
              <span style={{width: 1.5, height: 17, background: 'rgb(0,122,255)', marginLeft: 1, opacity: caret ? 1 : 0}} />
            )}
            {focused && !address && <span style={{color: 'rgb(150,150,155)', marginLeft: 2}}>Search or enter website name</span>}
            {loading >= 0 && (
              <div
                style={{
                  position: 'absolute',
                  left: 0,
                  bottom: 0,
                  height: 2.5,
                  width: `${loading * 100}%`,
                  background: 'rgb(0,122,255)',
                  opacity: loading >= 1 ? 0 : 1,
                }}
              />
            )}
          </div>
        </div>
        <div style={{display: 'flex', gap: 18, alignItems: 'center'}}>
          <Sym name="square.and.arrow.up" size={14} color="rgb(110,110,115)" />
          <Sym name="plus" size={14} color="rgb(110,110,115)" />
        </div>
      </div>
      <div
        style={{
          position: 'absolute',
          top: bar,
          left: 0,
          right: 0,
          bottom: 0,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          gap: 14,
          paddingBottom: 60,
          opacity: error,
          translate: `0 ${(1 - error) * 8}px`,
        }}
      >
        <div style={{fontSize: 30, fontWeight: 700, color: 'rgb(60,60,67)', letterSpacing: -0.4}}>
          Safari Can’t Find the Server
        </div>
        <div style={{fontSize: 15, color: 'rgb(120,120,128)', textAlign: 'center', lineHeight: 1.45, maxWidth: 520}}>
          Safari can’t open the page “{domain}” because Safari can’t find the server “{domain}”.
        </div>
      </div>
    </div>
  );
};
