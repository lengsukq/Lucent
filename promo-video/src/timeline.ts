import rawTimeline from './timeline.json';

export type ActTheme = 'prism-pulse' | 'pure-frost' | 'dual';

export interface ActDefinition {
  id: string;
  index: string;
  title: string;
  english: string;
  startFrame: number;
  durationFrames: number;
  theme: ActTheme;
  scaleIndex: number;
}

export interface SfxEvent {
  frame: number;
  type: string;
  gain: number;
}

export const FPS = rawTimeline.fps;
export const VIDEO_WIDTH = rawTimeline.width;
export const VIDEO_HEIGHT = rawTimeline.height;
export const TRANSITION_FRAMES = rawTimeline.transitionFrames;
export const TOTAL_FRAMES = rawTimeline.totalFrames;
export const ACTS: readonly ActDefinition[] = rawTimeline.acts as ActDefinition[];
export const SFX_EVENTS: readonly SfxEvent[] = rawTimeline.sfxEvents;

export const ACT_BY_ID: Record<string, ActDefinition> = Object.fromEntries(
  ACTS.map((act) => [act.id, act]),
);

export function getActiveActIndex(globalFrame: number): number {
  for (let i = ACTS.length - 1; i >= 0; i--) {
    if (globalFrame >= ACTS[i].startFrame) {
      return i;
    }
  }
  return 0;
}
