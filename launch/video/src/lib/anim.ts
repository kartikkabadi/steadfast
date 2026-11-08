import {interpolate, useCurrentFrame, useVideoConfig, type EasingFunction} from 'remotion';
import {ease} from '../theme';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;

/** Clamped interpolation over seconds. */
export const ramp = (
  t: number,
  range: readonly number[],
  out: readonly number[],
  easing: EasingFunction | EasingFunction[] = ease.out,
) => interpolate(t, range as number[], out as number[], {...clamp, easing});

/** Current time inside the enclosing Sequence, in seconds. */
export const useTime = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return frame / fps;
};

/** 0 → 1 → 0 bell, used for press feedback. */
export const pulse = (t: number, at: number, len = 0.18) => {
  if (t < at || t > at + len) return 0;
  const p = (t - at) / len;
  return Math.sin(p * Math.PI);
};

/** A typed string revealed at a steady cadence with a little human jitter. */
export const typed = (text: string, t: number, start: number, cps = 14) => {
  if (t < start) return '';
  let elapsed = 0;
  for (let i = 0; i < text.length; i++) {
    const jitter = ((i * 7919) % 13) / 13 - 0.5; // deterministic
    elapsed += (1 / cps) * (1 + jitter * 0.6);
    if (start + elapsed > t) return text.slice(0, i);
  }
  return text;
};

/** Times at which each character of `text` lands (for key-tap SFX). */
export const typedTimes = (text: string, start: number, cps = 14) => {
  const out: number[] = [];
  let elapsed = 0;
  for (let i = 0; i < text.length; i++) {
    const jitter = ((i * 7919) % 13) / 13 - 0.5;
    elapsed += (1 / cps) * (1 + jitter * 0.6);
    out.push(start + elapsed);
  }
  return out;
};
