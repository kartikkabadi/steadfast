import {AbsoluteFill, Img, staticFile} from 'remotion';
import {Backdrop} from './components/Backdrop';
import {film, SF} from './theme';

/** 1200×630 social card for the website and link previews. */
export const OgCard = () => (
  <AbsoluteFill>
    <Backdrop seed={1.3} warm={0.6} t0={22} angle={-0.42} offset={0.15} />
    <AbsoluteFill style={{padding: 72, justifyContent: 'flex-end', gap: 18}}>
      <Img
        src={staticFile('img/steadfast-icon.png')}
        style={{width: 104, height: 104, borderRadius: 104 * 0.2237, boxShadow: '0 12px 40px rgba(0,0,40,0.4)'}}
      />
      <div style={{fontFamily: SF, fontSize: 84, fontWeight: 650, letterSpacing: '-0.04em', color: '#fff', lineHeight: 1}}>
        Steadfast
      </div>
      <div style={{fontFamily: SF, fontSize: 38, fontWeight: 500, letterSpacing: '-0.02em', color: 'rgba(255,255,255,0.78)'}}>
        Make room for what you want to do.
      </div>
    </AbsoluteFill>
  </AbsoluteFill>
);

/** Wide grain plate used behind the website's dark sections. */
export const Plate = () => <Backdrop seed={4.2} warm={0.5} t0={9} angle={-0.3} offset={-0.1} />;

/** Film poster (shown before the video plays). */
export const Poster = () => (
  <AbsoluteFill style={{backgroundColor: film.stage, justifyContent: 'center', alignItems: 'center', gap: 36}}>
    <Img src={staticFile('img/steadfast-icon.png')} style={{width: 200, height: 200, borderRadius: 200 * 0.2237, boxShadow: '0 18px 50px rgba(1,40,253,0.3)'}} />
    <div style={{fontFamily: SF, fontSize: 110, fontWeight: 650, letterSpacing: '-0.04em', color: film.ink}}>Meet Steadfast.</div>
  </AbsoluteFill>
);
