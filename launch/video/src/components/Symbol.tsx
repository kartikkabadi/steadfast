import type React from 'react';
import {staticFile} from 'remotion';

/**
 * Real SF Symbols, exported from macOS by scripts/export-assets.swift at a
 * 96-point configuration. Sizes are their natural bounds at that point size, so
 * `size` behaves like SwiftUI's `.font(.system(size:))` on an Image.
 */
const dims: Record<string, [number, number]> = {
  'lock.fill': [92, 111],
  lock: [90, 109],
  hourglass: [80, 105],
  xmark: [99, 93],
  'chevron.right': [72, 100],
  'chevron.left': [72, 100],
  magnifyingglass: [114, 110],
  'checkmark.circle.fill': [115, 115],
  gearshape: [119, 119],
  'play.rectangle': [135, 104],
  camera: [140, 107],
  bubble: [128, 114],
  'text.bubble': [128, 114],
  'music.note': [82, 112],
  tv: [142, 111],
  plus: [102, 95],
  'arrow.right': [112, 89],
  'calendar.badge.clock': [132, 119],
  star: [125, 119],
  ellipsis: [106, 36],
  'xmark.circle.fill': [113, 113],
  'minus.circle': [115, 115],
  'person.crop.circle.badge.xmark': [129, 120],
  'chart.bar.xaxis': [129, 104],
  'icloud.slash': [135, 118],
  laptopcomputer: [160, 94],
  timer: [113, 113],
  'arrow.clockwise': [101, 119],
  shield: [102, 112],
  'exclamationmark.triangle.fill': [118, 107],
  keyboard: [142, 92],
  power: [114, 117],
  checkmark: [109, 100],
  'square.and.arrow.up': [108, 130],
  'sidebar.left': [135, 104],
  macwindow: [135, 104],
};

export const Sym: React.FC<{
  readonly name: string;
  readonly size: number; // point size, as in SwiftUI
  readonly color: string;
  readonly style?: React.CSSProperties;
}> = ({name, size, color, style}) => {
  const [w, h] = dims[name] ?? [100, 100];
  const k = size / 96;
  const url = `url(${staticFile(`img/sym/${name}.png`)})`;
  return (
    <span
      style={{
        display: 'inline-block',
        width: w * k,
        height: h * k,
        backgroundColor: color,
        WebkitMaskImage: url,
        maskImage: url,
        WebkitMaskSize: '100% 100%',
        maskSize: '100% 100%',
        flexShrink: 0,
        ...style,
      }}
    />
  );
};
