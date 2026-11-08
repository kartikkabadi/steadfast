import type React from 'react';
import {interpolate} from 'remotion';
import {ease} from '../theme';

export type Key = {readonly t: number; readonly x: number; readonly y: number};

/** Position along a keyframed path; each leg eases in and out like a hand. */
export const pathAt = (keys: readonly Key[], t: number) => {
  if (t <= keys[0].t) return {x: keys[0].x, y: keys[0].y};
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i];
    const b = keys[i + 1];
    if (t <= b.t) {
      const p = interpolate(t, [a.t, b.t], [0, 1], {easing: ease.inOut});
      // slight arc so moves don't look robotic
      const arc = Math.sin(p * Math.PI) * Math.min(24, Math.hypot(b.x - a.x, b.y - a.y) * 0.06);
      return {x: a.x + (b.x - a.x) * p, y: a.y + (b.y - a.y) * p - arc};
    }
  }
  const last = keys[keys.length - 1];
  return {x: last.x, y: last.y};
};

/** The macOS arrow pointer. Its hotspot is the tip at (x, y). */
export const Cursor: React.FC<{
  readonly x: number;
  readonly y: number;
  readonly press?: number; // 0…1
  readonly opacity?: number;
  readonly scale?: number;
}> = ({x, y, press = 0, opacity = 1, scale = 1}) => (
  <svg
    width={28}
    height={36}
    viewBox="-2 -2 18 24"
    style={{
      position: 'absolute',
      left: x - 2 * (28 / 18),
      top: y - 2 * (36 / 24),
      opacity,
      scale: `${scale * (1 - press * 0.16)}`,
      transformOrigin: `${2 * (28 / 18)}px ${2 * (36 / 24)}px`,
      filter: 'drop-shadow(0 1.5px 2px rgba(0,0,0,0.35))',
      zIndex: 50,
      pointerEvents: 'none',
    }}
  >
    <path
      d="M0 0 L0 16.2 L3.9 12.6 L6.6 18.8 L9.2 17.7 L6.6 11.6 L11.8 11.6 Z"
      fill="#000"
      stroke="#fff"
      strokeWidth={1.3}
      strokeLinejoin="round"
    />
  </svg>
);
