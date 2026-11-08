import type React from 'react';
import {Audio} from '@remotion/media';
import {staticFile, useVideoConfig} from 'remotion';

/** A one-shot sound effect at `at` seconds into the enclosing sequence. */
export const Sfx: React.FC<{
  readonly src: string; // file name in public/sfx, without extension
  readonly at: number;
  readonly volume?: number;
  readonly name?: string;
}> = ({src, at, volume = 1, name}) => {
  const {fps} = useVideoConfig();
  return (
    <Audio
      name={name ?? src}
      src={staticFile(`sfx/${src}.wav`)}
      from={Math.round(at * fps)}
      volume={volume}
    />
  );
};
