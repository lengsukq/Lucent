import { Config } from '@remotion/cli/config';

Config.setVideoImageFormat('jpeg');
Config.setJpegQuality(94);
Config.setOverwriteOutput(true);
Config.setPixelFormat('yuv420p');
Config.setCodec('h264');
Config.setCrf(17);
Config.setAudioCodec('aac');
Config.setAudioBitrate('256k');
Config.setConcurrency(6);
Config.setChromiumOpenGlRenderer('angle');
