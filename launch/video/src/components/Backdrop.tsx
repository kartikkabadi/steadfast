import type React from 'react';
import {Solid, useCurrentFrame, useVideoConfig} from 'remotion';
import {grainField} from '../effects/grain-field';

/** Full-frame grain-field plate. `t0` offsets the drift so cuts don't repeat. */
export const Backdrop: React.FC<{
  readonly seed?: number;
  readonly warm?: number;
  readonly exposure?: number;
  readonly angle?: number;
  readonly offset?: number;
  readonly t0?: number;
  readonly speed?: number;
  readonly style?: React.CSSProperties;
}> = ({seed = 0, warm = 0.6, exposure = 1, angle = -0.42, offset = 0, t0 = 0, speed = 1, style}) => {
  const frame = useCurrentFrame();
  const {fps, width, height} = useVideoConfig();
  return (
    <Solid
      width={width}
      height={height}
      style={{position: 'absolute', inset: 0, ...style}}
      effects={[grainField({time: t0 + (frame / fps) * speed, seed, warm, exposure, angle, offset, grain: 0.55, dot: 2.5})]}
    />
  );
};
