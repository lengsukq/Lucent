import React from 'react';
import { AbsoluteFill, Audio, staticFile, useCurrentFrame } from 'remotion';
import { linearTiming, TransitionSeries } from '@remotion/transitions';
import { fade } from '@remotion/transitions/fade';
import { ChapterRail } from './components/ChapterRail';
import { ThemeMode } from './design/tokens';
import { Act0Prologue } from './scenes/Act0Prologue';
import { Act1CustomHome } from './scenes/Act1CustomHome';
import { Act2UnifiedSearch } from './scenes/Act2UnifiedSearch';
import { Act3NativeTools } from './scenes/Act3NativeTools';
import { Act4PluginEcosystem } from './scenes/Act4PluginEcosystem';
import { Act5McpCoCreation } from './scenes/Act5McpCoCreation';
import { Act6EngineeringPhilosophy } from './scenes/Act6EngineeringPhilosophy';
import { Act7Finale } from './scenes/Act7Finale';
import { ACT_BY_ID, TRANSITION_FRAMES } from './timeline';

function resolveRailTheme(globalFrame: number): ThemeMode {
  // Act 1 diagonal Pure Frost sweep crosses top-left brand mark around global frame 2595
  if (globalFrame >= 2595 && globalFrame < 3240) return 'pure-frost';
  // Act 3 uses Pure Frost during Capture (5520..6100) and 120Hz Mouse (7000..7580)
  if (globalFrame >= 5520 && globalFrame < 6100) return 'pure-frost';
  if (globalFrame >= 7000 && globalFrame < 7580) return 'pure-frost';
  // Act 6 uses Pure Frost during Ephemeral Memory section (12480 + 1060 = 13540..14040)
  if (globalFrame >= 13540 && globalFrame < 14040) return 'pure-frost';
  return 'prism-pulse';
}

export interface LucentPromoProps {
  enableAudio?: boolean;
}

export const LucentPromoVideo: React.FC<LucentPromoProps> = ({ enableAudio = true }) => {
  const frame = useCurrentFrame();
  const railTheme = resolveRailTheme(frame);
  const transition = linearTiming({ durationInFrames: TRANSITION_FRAMES });

  return (
    <AbsoluteFill style={{ backgroundColor: '#03040a' }}>
      {enableAudio && (
        <Audio src={staticFile('audio/generated/soundtrack-master.wav')} volume={1} />
      )}

      <TransitionSeries>
        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act0.durationFrames}>
          <Act0Prologue />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act1.durationFrames}>
          <Act1CustomHome />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act2.durationFrames}>
          <Act2UnifiedSearch />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act3.durationFrames}>
          <Act3NativeTools />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act4.durationFrames}>
          <Act4PluginEcosystem />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act5.durationFrames}>
          <Act5McpCoCreation />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act6.durationFrames}>
          <Act6EngineeringPhilosophy />
        </TransitionSeries.Sequence>
        <TransitionSeries.Transition presentation={fade()} timing={transition} />

        <TransitionSeries.Sequence durationInFrames={ACT_BY_ID.act7.durationFrames}>
          <Act7Finale />
        </TransitionSeries.Sequence>
      </TransitionSeries>

      <ChapterRail theme={railTheme} />
    </AbsoluteFill>
  );
};
