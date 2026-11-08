import {Easing} from 'remotion';

/** Film palette — Apple-style white stage with Steadfast's own blue. */
export const film = {
  stage: '#FFFFFF',
  ink: '#1D1D1F',
  secondary: '#86868B',
  tertiary: '#AEAEB2',
  // Sampled from Icon/Steadfast.png (top-left #0141FD → bottom #0117FB).
  brand: '#0A36FD',
  brandDeep: '#0117FB',
  brandLight: '#3D6BFF',
};

/**
 * The app's own light palette, transcribed from Sources/SteadfastApp/CedarDesign.swift
 * (Palette.NS, light appearance, normal contrast).
 */
export const ui = {
  ground: '#FFFFFF', // pair(1, …)
  window: 'rgb(249, 249, 250)', // Glass veil (0.975, 0.975, 0.98) at frost 0.9
  ink: '#171717', // 0x17
  muted: '#626262', // 0x62
  faint: 'rgb(158, 158, 158)', // 0.62
  hairline: 'rgb(232, 232, 232)', // 0.91
  wash: 'rgba(0, 0, 0, 0.065)', // veil 0.065
  hover: 'rgba(0, 0, 0, 0.04)',
  accent: 'rgb(43, 101, 201)', // #2B65C9
  accentRGB: '43, 101, 201',
  danger: 'rgb(219, 38, 38)',
  card: 'rgba(255, 255, 255, 0.5)',
};

/** SwiftUI TypeScale sizes (points). */
export const type = {
  caption: 11,
  chrome: 12,
  body: 13,
  title: 15,
  display: 26,
  hero: 34,
};

export const radius = {control: 6, row: 8, card: 12, panel: 24};

// In headless Chrome on macOS, `system-ui` and `BlinkMacSystemFont` resolve to
// SF Pro with optical sizing; `-apple-system` does not (it falls back to Times).
export const SF = 'system-ui, BlinkMacSystemFont, "Helvetica Neue", Helvetica, Arial, sans-serif';
export const SF_DISPLAY = SF;
export const SF_MONO = 'ui-monospace, "SF Mono", Menlo, monospace';

/** Soundtrack tempo — every cut lands on this grid. */
export const BPM = 120;
export const BEAT = 60 / BPM;

/** Apple-ish curves. */
export const ease = {
  out: Easing.bezier(0.16, 1, 0.3, 1),
  inOut: Easing.bezier(0.65, 0, 0.35, 1),
  in: Easing.bezier(0.55, 0, 1, 0.45),
  swift: Easing.bezier(0.2, 0.9, 0.1, 1),
  settle: Easing.spring({damping: 200}),
};
