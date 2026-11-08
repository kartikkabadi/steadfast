import {interpolate} from 'remotion';
import {typedTimes} from './lib/anim';
import {CPS, DOMAIN, ENTER, LOADED, TYPE_AT} from './scenes/ColdOpen';
import {NAME, T} from './scenes/HowTo';
import {QUIT} from './scenes/KeepsWorking';
import {CLICK} from './scenes/NoPause';

/**
 * Every UI sound in the film, in seconds from the start, with how deep the
 * music should dip under it. The music sidesteps each click for ~0.2 s so the
 * interface is heard without the groove losing its drive.
 */
const SCENE = {blocks: 10, howTo: 12, noPause: 28, keepsWorking: 32, features: 40};

type Duck = {at: number; depth: number; hold?: number};

export const DUCKS: Duck[] = [
  ...typedTimes(DOMAIN, TYPE_AT, CPS).map((at) => ({at, depth: 0.25})),
  {at: ENTER, depth: 0.3},
  {at: LOADED, depth: 0.35, hold: 0.3},
  ...[0.5, 0.75, 1, 1.25, 1.5].map((at) => ({at: SCENE.blocks + at, depth: 0.35})),
  ...[T.chooseClick, T.xClick, T.ytClick, T.redditClick, T.doneClick, T.durationClick, T.purposeClick, T.reviewClick, T.commitClick].map((c) => ({
    at: SCENE.howTo + c - 0.03,
    depth: 0.45,
  })),
  ...[T.sheetIn - 0.05, T.sheetOut, T.durationClick - 0.1, T.reviewIn - 0.05].map((at) => ({at: SCENE.howTo + at, depth: 0.35})),
  ...typedTimes(NAME, T.typeAt, 12).map((at) => ({at: SCENE.howTo + at, depth: 0.3})),
  {at: SCENE.howTo + T.commitClick, depth: 0.55, hold: 0.45},
  {at: SCENE.noPause + CLICK - 0.03, depth: 0.4, hold: 0.25},
  {at: SCENE.keepsWorking + QUIT - 0.03, depth: 0.4},
  {at: SCENE.keepsWorking + 1.9, depth: 0.3},
  {at: SCENE.keepsWorking + 2.3, depth: 0.4, hold: 0.25},
  {at: SCENE.features + 1.3, depth: 0.35},
  {at: SCENE.features + 2.75, depth: 0.35},
];

const BASE = 0.86;

/** Music gain at a frame: a gentle overall trim, dipping under each UI sound. */
export const musicVolume = (frame: number, fps: number) => {
  const t = frame / fps;
  let gain = 1;
  for (const d of DUCKS) {
    if (t < d.at - 0.05 || t > d.at + (d.hold ?? 0.12) + 0.3) continue;
    const g = interpolate(
      t,
      [d.at - 0.04, d.at, d.at + (d.hold ?? 0.12), d.at + (d.hold ?? 0.12) + 0.26],
      [1, 1 - d.depth, 1 - d.depth, 1],
      {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'},
    );
    gain = Math.min(gain, g);
  }
  return BASE * gain;
};
