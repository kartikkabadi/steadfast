import {Audio} from '@remotion/media';
import {AbsoluteFill, staticFile, Track, useVideoConfig} from 'remotion';
import {Blocks} from './scenes/Blocks';
import {ColdOpen} from './scenes/ColdOpen';
import {Confession} from './scenes/Confession';
import {HowTo} from './scenes/HowTo';
import {Features} from './scenes/Features';
import {KeepsWorking} from './scenes/KeepsWorking';
import {Meet} from './scenes/Meet';
import {NoPause} from './scenes/NoPause';
import {Outro} from './scenes/Outro';
import {Stretch} from './scenes/Stretch';
import {musicVolume} from './mix';

/**
 * The launch film. Scene boundaries sit on the soundtrack's bar grid
 * (120 BPM, 2 s bars); see scripts/compose.py for the arrangement.
 */
export const Launch = () => {
  const {fps} = useVideoConfig();
  return (
    <AbsoluteFill style={{backgroundColor: '#fff'}}>
      <Track name="Scenes">
        <ColdOpen name="Cold open — x.com won't load" durationInFrames={4 * fps} />
        <Confession name="Confession" from={4 * fps} durationInFrames={3.5 * fps} />
        <Meet name="Meet Steadfast" from={7.5 * fps} durationInFrames={2.5 * fps} />
        <Blocks name="Websites. Apps. Locked." from={10 * fps} durationInFrames={2 * fps} />
        <HowTo name="How to set a block" from={12 * fps} durationInFrames={16 * fps} />
        <NoPause name="No pause, no ending early" from={28 * fps} durationInFrames={4 * fps} />
        <KeepsWorking name="Keeps working after quit" from={32 * fps} durationInFrames={4 * fps} />
        <Stretch name="Make rooooom" from={36 * fps} durationInFrames={4 * fps} />
        <Features name="Features" from={40 * fps} durationInFrames={8 * fps} />
        <Outro name="Outro" from={48 * fps} durationInFrames={7 * fps} />
      </Track>
      <Track name="Music">
        <Audio name="Soundtrack" src={staticFile('audio/soundtrack.wav')} volume={(f) => musicVolume(f, fps)} />
      </Track>
    </AbsoluteFill>
  );
};
