import {Composition, Folder, Still} from 'remotion';
import {Launch} from './Launch';
import {OgCard, Plate, Poster} from './Stills';
import {Test} from './Test';

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="Launch" component={Launch} durationInFrames={3300} fps={60} width={1920} height={1080} />
    <Folder name="Website">
      <Still id="OgCard" component={OgCard} width={1200} height={630} />
      <Still id="Plate" component={Plate} width={2400} height={1350} />
      <Still id="Poster" component={Poster} width={1920} height={1080} />
    </Folder>
    <Folder name="Dev">
      <Composition id="Test" component={Test} durationInFrames={120} fps={60} width={1920} height={1080} />
    </Folder>
  </>
);
