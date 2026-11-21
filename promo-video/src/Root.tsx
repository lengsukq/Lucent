import React from 'react';
import { Composition } from 'remotion';
import { LucentPromoVideo } from './LucentPromoVideo';
import { Act0Prologue } from './scenes/Act0Prologue';
import { Act1CustomHome } from './scenes/Act1CustomHome';
import { Act2UnifiedSearch } from './scenes/Act2UnifiedSearch';
import { Act3NativeTools } from './scenes/Act3NativeTools';
import { Act4PluginEcosystem } from './scenes/Act4PluginEcosystem';
import { Act5McpCoCreation } from './scenes/Act5McpCoCreation';
import { Act6EngineeringPhilosophy } from './scenes/Act6EngineeringPhilosophy';
import { Act7Finale } from './scenes/Act7Finale';
import { ACT_BY_ID, FPS, TOTAL_FRAMES, VIDEO_HEIGHT, VIDEO_WIDTH } from './timeline';

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="LucentPromo"
        component={LucentPromoVideo}
        durationInFrames={TOTAL_FRAMES}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
        defaultProps={{ enableAudio: true }}
      />
      <Composition
        id="Act0Prologue"
        component={Act0Prologue}
        durationInFrames={ACT_BY_ID.act0.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act1CustomHome"
        component={Act1CustomHome}
        durationInFrames={ACT_BY_ID.act1.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act2UnifiedSearch"
        component={Act2UnifiedSearch}
        durationInFrames={ACT_BY_ID.act2.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act3NativeTools"
        component={Act3NativeTools}
        durationInFrames={ACT_BY_ID.act3.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act4PluginEcosystem"
        component={Act4PluginEcosystem}
        durationInFrames={ACT_BY_ID.act4.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act5McpCoCreation"
        component={Act5McpCoCreation}
        durationInFrames={ACT_BY_ID.act5.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act6EngineeringPhilosophy"
        component={Act6EngineeringPhilosophy}
        durationInFrames={ACT_BY_ID.act6.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
      <Composition
        id="Act7Finale"
        component={Act7Finale}
        durationInFrames={ACT_BY_ID.act7.durationFrames}
        fps={FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
    </>
  );
};
