import {Config} from '@remotion/cli/config';

Config.setRspack(true);
Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(95);
Config.setOverwriteOutput(true);
Config.setDefaultPremountInSeconds(2);
// WebGL for the grain-field effect and @remotion/effects.
Config.setChromiumOpenGlRenderer('angle');
