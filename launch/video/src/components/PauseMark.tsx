import type React from 'react';

/** Design.swift `PauseMark`: two capsules, each 36% of the width, 88% of the height. */
export const PauseMark: React.FC<{
  readonly width: number;
  readonly height: number;
  readonly color: string;
  readonly style?: React.CSSProperties;
  /** 0…1, how far each bar has grown (for the reveal). */
  readonly grow?: number;
}> = ({width, height, color, style, grow = 1}) => {
  const bar = width * 0.36;
  const gap = width - bar * 2;
  const h = height * 0.88 * grow;
  return (
    <div
      style={{
        width,
        height,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap,
        ...style,
      }}
    >
      <div style={{width: bar, height: h, borderRadius: bar, background: color}} />
      <div style={{width: bar, height: h, borderRadius: bar, background: color}} />
    </div>
  );
};
