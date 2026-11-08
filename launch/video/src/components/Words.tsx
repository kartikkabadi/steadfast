import type React from 'react';
import {ramp, useTime} from '../lib/anim';
import {ease, film, SF_DISPLAY} from '../theme';

export type Part = {readonly text: string; readonly color?: string; readonly weight?: number};

/**
 * Apple-keynote headline: each word rises out of a blur, slightly staggered,
 * and the whole line dissolves back into blur on exit.
 */
export const Words: React.FC<{
  readonly parts: readonly Part[];
  readonly start?: number;
  readonly exit?: number | null;
  readonly size?: number;
  readonly weight?: number;
  readonly stagger?: number;
  readonly dur?: number;
  readonly tracking?: number;
  readonly align?: 'left' | 'center';
  readonly style?: React.CSSProperties;
  readonly lineHeight?: number;
  readonly maxWidth?: number;
}> = ({
  parts,
  start = 0,
  exit = null,
  size = 96,
  weight = 600,
  stagger = 0.055,
  dur = 0.55,
  tracking = -0.035,
  align = 'center',
  style,
  lineHeight = 1.06,
  maxWidth,
}) => {
  const t = useTime();
  const words: {w: string; color: string; weight: number; space: boolean; br?: boolean}[] = [];
  for (const p of parts) {
    const split = p.text.split(/(\s+)/).filter((s) => s.length > 0);
    for (const s of split) {
      if (/^\s+$/.test(s)) {
        if (s.includes('\n')) words.push({w: '', color: '', weight: 0, space: false, br: true});
        else if (words.length) words[words.length - 1].space = true;
        continue;
      }
      words.push({w: s, color: p.color ?? film.ink, weight: p.weight ?? weight, space: false});
    }
  }
  const out = exit === null ? 0 : ramp(t, [exit, exit + 0.32], [0, 1], ease.in);
  return (
    <div
      style={{
        fontFamily: SF_DISPLAY,
        fontSize: size,
        letterSpacing: `${tracking}em`,
        lineHeight,
        textAlign: align,
        maxWidth,
        opacity: 1 - out,
        filter: out > 0 ? `blur(${out * 18}px)` : undefined,
        translate: `0 ${-out * 10}px`,
        fontKerning: 'normal',
        fontFeatureSettings: '"kern"',
        ...style,
      }}
    >
      {words.map((w, i) => {
        if (w.br) return <br key={i} />;
        const s0 = start + i * stagger;
        const p = ramp(t, [s0, s0 + dur], [0, 1], ease.out);
        return (
          <span
            key={i}
            style={{
              display: 'inline-block',
              color: w.color,
              fontWeight: w.weight,
              opacity: ramp(t, [s0, s0 + dur * 0.6], [0, 1], ease.out),
              filter: p < 1 ? `blur(${(1 - p) * 16}px)` : undefined,
              translate: `0 ${(1 - p) * size * 0.22}px`,
              scale: `${0.97 + 0.03 * p}`,
              whiteSpace: 'pre',
            }}
          >
            {w.w}
            {w.space ? ' ' : ''}
          </span>
        );
      })}
    </div>
  );
};
