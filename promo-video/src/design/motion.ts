import { Easing, interpolate, spring } from 'remotion';
import { FPS } from '../timeline';

export const SPRING_SNAPPY = { damping: 22, stiffness: 240, mass: 0.85 };
export const SPRING_GLASS = { damping: 20, stiffness: 150, mass: 0.95 };
export const SPRING_GENTLE = { damping: 26, stiffness: 95, mass: 1.1 };
export const SPRING_BOUNCY = { damping: 14, stiffness: 190, mass: 0.85 };

export function spr(
  frame: number,
  delay = 0,
  config = SPRING_GLASS,
): number {
  return spring({
    frame: Math.max(0, frame - delay),
    fps: FPS,
    config,
  });
}

export function clampLerp(
  frame: number,
  inRange: [number, number],
  outRange: [number, number],
  easing: (t: number) => number = Easing.out(Easing.cubic),
): number {
  return interpolate(frame, inRange, outRange, {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing,
  });
}

export function fadeInOut(
  frame: number,
  start: number,
  end: number,
  fadeIn = 18,
  fadeOut = 18,
): number {
  if (frame < start || frame > end) return 0;
  const enter = interpolate(frame, [start, start + fadeIn], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.out(Easing.cubic),
  });
  const exit = interpolate(frame, [end - fadeOut, end], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
    easing: Easing.in(Easing.cubic),
  });
  return Math.min(enter, exit);
}

export function typewriter(
  text: string,
  frame: number,
  startFrame: number,
  charsPerSecond = 20,
): string {
  if (frame <= startFrame) return '';
  const elapsedSec = (frame - startFrame) / FPS;
  const count = Math.min(text.length, Math.floor(elapsedSec * charsPerSecond));
  return text.slice(0, count);
}
