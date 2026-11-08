import {AbsoluteFill} from 'remotion';

const fams = ['system-ui', 'BlinkMacSystemFont', '.AppleSystemUIFont', 'SF NS', 'SF Pro', 'SF Pro Display', 'Helvetica Neue', '-apple-system'];
export const Test = () => (
  <AbsoluteFill style={{background: 'white', padding: 40, gap: 10}}>
    {fams.map((f) => (
      <div key={f} style={{fontFamily: `${f === ".AppleSystemUIFont" ? `"${f}"` : f}, monospace`, fontSize: 64, fontWeight: 600, letterSpacing: '-0.03em'}}>
        {f}: Steadfast 10:30 Rag
      </div>
    ))}
  </AbsoluteFill>
);
