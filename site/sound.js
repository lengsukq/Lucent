/* ==========================================================================
   Lucent — Procedural Web Audio Engine (Zero External Assets)
   Glassy / Crystalline / Optical Ambience + Real-Time Physics Sonification
   ========================================================================== */

(() => {
  'use strict';

  const STORAGE_KEY = 'lucent-showcase-sound-v1';

  function safeReadPref() {
    try {
      const v = window.localStorage.getItem(STORAGE_KEY);
      return v === 'off' ? false : true;
    } catch (_) {
      return true;
    }
  }

  function safeWritePref(enabled) {
    try {
      window.localStorage.setItem(STORAGE_KEY, enabled ? 'on' : 'off');
    } catch (_) {}
  }

  const STAGE_SCALES = [
    [392.00, 440.00, 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50], // 00 Liquid Droplet
    [523.25, 587.33, 659.25, 783.99, 987.77, 1046.50, 1174.66, 1318.51], // 01 Optical Glass
    [440.00, 523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66], // 02 Astrolabe Crystal
    [220.00, 261.63, 293.66, 329.63, 392.00, 440.00, 523.25, 587.33], // 03 Helicoid Forge
    [587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51, 1567.98], // 04 Diamond DAG
    [261.63, 329.63, 392.00, 493.88, 523.25, 659.25, 783.99, 987.77]  // 05 Solar Eclipse
  ];

  const STAGE_CHORDS = [
    [130.81, 196.00, 293.66],
    [146.83, 220.00, 329.63],
    [174.61, 261.63, 392.00],
    [110.00, 164.81, 246.94],
    [196.00, 293.66, 440.00],
    [130.81, 196.00, 329.63]
  ];

  const CRYSTAL_SCALE = [523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51];

  const state = {
    enabled: safeReadPref(),
    unlocked: false,
    scene: 0,
    lightMode: false,
    pluginRatio: 0.625,
    listeners: new Set()
  };

  let ctx = null;
  let masterGain = null;
  let compressor = null;
  let dryGain = null;
  let reverbSend = null;
  let reverbDamp = null;
  let delayL = null;
  let delayR = null;
  let fbL = null;
  let fbR = null;
  let noiseBuffer = null;

  // Continuous gravity-charge voice (purely silent unless holding)
  let chargeBuilt = false;
  let chargeGain = null;
  let chargeFilter = null;
  let chargeOsc = null;
  let chargeSub = null;

  // Throttle & edge-detection trackers
  let lastHoverAt = 0;
  let lastWhisperAt = 0;
  let lastSceneWhooshAt = 0;
  let lastLayerOpen = false;
  let lastScene = 0;

  function notify() {
    const snap = getStatus();
    state.listeners.forEach((fn) => {
      try { fn(snap); } catch (_) {}
    });
  }

  function getStatus() {
    return {
      enabled: state.enabled,
      unlocked: state.unlocked,
      active: state.enabled && state.unlocked
    };
  }

  function createNoiseBuffer(audioCtx) {
    const length = audioCtx.sampleRate * 2;
    const buf = audioCtx.createBuffer(1, length, audioCtx.sampleRate);
    const data = buf.getChannelData(0);
    let b0 = 0, b1 = 0, b2 = 0;
    for (let i = 0; i < length; i++) {
      const white = Math.random() * 2 - 1;
      b0 = 0.99765 * b0 + white * 0.0990460;
      b1 = 0.96300 * b1 + white * 0.2965164;
      b2 = 0.57000 * b2 + white * 1.0526913;
      data[i] = (b0 + b1 + b2 + white * 0.1848) * 0.16;
    }
    return buf;
  }

  function ensureGraph() {
    if (ctx) return true;
    const AudioCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioCtor) return false;

    ctx = new AudioCtor();
    noiseBuffer = createNoiseBuffer(ctx);

    compressor = ctx.createDynamicsCompressor();
    compressor.threshold.value = -16;
    compressor.knee.value = 18;
    compressor.ratio.value = 4;
    compressor.attack.value = 0.008;
    compressor.release.value = 0.22;

    masterGain = ctx.createGain();
    masterGain.gain.value = 0.0001;

    dryGain = ctx.createGain();
    dryGain.gain.value = 0.85;

    // Cross-coupled stereo crystalline shimmer delay network
    reverbSend = ctx.createGain();
    reverbSend.gain.value = 0.42;

    delayL = ctx.createDelay(1.0);
    delayR = ctx.createDelay(1.0);
    delayL.delayTime.value = 0.19;
    delayR.delayTime.value = 0.27;

    fbL = ctx.createGain();
    fbR = ctx.createGain();
    fbL.gain.value = state.lightMode ? 0.34 : 0.46;
    fbR.gain.value = state.lightMode ? 0.34 : 0.46;

    reverbDamp = ctx.createBiquadFilter();
    reverbDamp.type = 'lowpass';
    reverbDamp.frequency.value = state.lightMode ? 4800 : 3200;

    const merger = ctx.createChannelMerger(2);

    dryGain.connect(compressor);
    reverbSend.connect(delayL);
    reverbSend.connect(delayR);

    delayL.connect(fbL);
    delayR.connect(fbR);
    fbL.connect(delayR);
    fbR.connect(reverbDamp);
    reverbDamp.connect(delayL);

    delayL.connect(merger, 0, 0);
    delayR.connect(merger, 0, 1);
    merger.connect(compressor);

    compressor.connect(masterGain);
    masterGain.connect(ctx.destination);

    ensureChargeVoice();
    return true;
  }

  function ensureChargeVoice() {
    if (chargeBuilt || !ctx) return;
    chargeBuilt = true;

    // Continuous gravity-whirlpool charge voice (strictly silent unless holding)
    chargeOsc = ctx.createOscillator();
    chargeOsc.type = 'triangle';
    chargeOsc.frequency.value = 135;

    chargeSub = ctx.createOscillator();
    chargeSub.type = 'sine';
    chargeSub.frequency.value = 67.5;

    chargeFilter = ctx.createBiquadFilter();
    chargeFilter.type = 'bandpass';
    chargeFilter.frequency.value = 260;
    chargeFilter.Q.value = 2.4;

    chargeGain = ctx.createGain();
    chargeGain.gain.value = 0;

    chargeOsc.connect(chargeFilter);
    chargeSub.connect(chargeFilter);
    chargeFilter.connect(chargeGain);
    chargeGain.connect(dryGain);
    chargeGain.connect(reverbSend);

    chargeOsc.start();
    chargeSub.start();
  }

  function syncMasterRamp() {
    if (!ctx || !masterGain) return;
    const now = ctx.currentTime;
    const active = state.enabled && state.unlocked && !document.hidden;
    masterGain.gain.cancelScheduledValues(now);
    masterGain.gain.setTargetAtTime(active ? 0.72 : 0, now, active ? 0.04 : 0.03);
    if (!active && chargeGain) {
      chargeGain.gain.setTargetAtTime(0, now, 0.02);
    }
  }

  async function unlockFromGesture() {
    if (!state.enabled) return false;
    if (!ensureGraph()) return false;

    if (ctx.state === 'suspended') {
      try {
        await ctx.resume();
      } catch (_) {
        return false;
      }
    }

    if (ctx.state === 'running' && !state.unlocked) {
      state.unlocked = true;
      syncMasterRamp();
      notify();
    } else if (ctx.state === 'running') {
      syncMasterRamp();
    }
    return state.unlocked;
  }

  function isReady() {
    return Boolean(ctx && state.enabled && state.unlocked && ctx.state === 'running' && !document.hidden);
  }

  function withUnlocked(fn) {
    if (!state.enabled || document.hidden) return;
    if (isReady()) {
      fn();
    } else {
      unlockFromGesture().then((ok) => {
        if (ok && isReady()) fn();
      });
    }
  }

  function scheduleCleanup(nodes, stopAt) {
    const primary = nodes[0];
    if (!primary) return;
    primary.onended = () => {
      nodes.forEach((n) => {
        try { n.disconnect(); } catch (_) {}
      });
    };
    try {
      primary.stop(stopAt);
    } catch (_) {}
  }

  function routeOutput(env, wet, pan, cleanupList) {
    let outNode = env;
    if (Math.abs(pan) > 0.02 && typeof ctx.createStereoPanner === 'function') {
      const panner = ctx.createStereoPanner();
      panner.pan.value = Math.max(-0.85, Math.min(0.85, pan));
      env.connect(panner);
      outNode = panner;
      cleanupList.push(panner);
    }
    outNode.connect(dryGain);
    if (wet > 0) {
      const send = ctx.createGain();
      send.gain.value = wet;
      outNode.connect(send);
      send.connect(reverbSend);
      cleanupList.push(send);
    }
  }

  function playTone({
    freq,
    freqEnd = null,
    type = 'sine',
    gain = 0.1,
    attack = 0.006,
    decay = 0.45,
    delay = 0,
    wet = 0.5,
    pan = 0,
    filterFreq = null
  }) {
    if (!isReady()) return;
    const t0 = ctx.currentTime + delay;
    const tEnd = t0 + attack + decay + 0.06;

    const osc = ctx.createOscillator();
    osc.type = type;
    osc.frequency.setValueAtTime(Math.max(20, freq), t0);
    if (freqEnd !== null) {
      osc.frequency.exponentialRampToValueAtTime(Math.max(20, freqEnd), t0 + attack + decay * 0.85);
    }

    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.linearRampToValueAtTime(gain, t0 + attack);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + attack + decay);

    let tailNode = osc;
    const cleanupList = [osc, env];

    if (filterFreq) {
      const flt = ctx.createBiquadFilter();
      flt.type = 'lowpass';
      flt.frequency.setValueAtTime(filterFreq, t0);
      osc.connect(flt);
      tailNode = flt;
      cleanupList.push(flt);
    }

    tailNode.connect(env);
    routeOutput(env, wet, pan, cleanupList);

    osc.start(t0);
    scheduleCleanup(cleanupList, tEnd);
  }

  function playNoiseBurst({
    freq = 1200,
    freqEnd = 600,
    q = 1.6,
    filterType = 'bandpass',
    gain = 0.04,
    attack = 0.015,
    decay = 0.24,
    delay = 0,
    wet = 0.35,
    pan = 0
  }) {
    if (!isReady() || !noiseBuffer) return;
    const t0 = ctx.currentTime + delay;
    const tEnd = t0 + attack + decay + 0.05;

    const src = ctx.createBufferSource();
    src.buffer = noiseBuffer;
    src.loop = true;

    const flt = ctx.createBiquadFilter();
    flt.type = filterType;
    flt.Q.value = q;
    flt.frequency.setValueAtTime(Math.max(60, freq), t0);
    flt.frequency.exponentialRampToValueAtTime(Math.max(60, freqEnd), t0 + attack + decay);

    const env = ctx.createGain();
    env.gain.setValueAtTime(0.0001, t0);
    env.gain.linearRampToValueAtTime(gain, t0 + attack);
    env.gain.exponentialRampToValueAtTime(0.0001, t0 + attack + decay);

    const cleanupList = [src, flt, env];
    src.connect(flt);
    flt.connect(env);
    routeOutput(env, wet, pan, cleanupList);

    src.start(t0, Math.random() * 1.2);
    scheduleCleanup(cleanupList, tEnd);
  }

  /* ------------------------------------------------------------------------
     Public Interaction & Choreography Cues
     ------------------------------------------------------------------------ */
  function pickStagePitch(sceneIdx, nx = 0, ny = 0) {
    const scale = STAGE_SCALES[sceneIdx] || STAGE_SCALES[0];
    const ux = Math.max(0, Math.min(1, (nx + 1) * 0.5));
    const uy = Math.max(0, Math.min(1, (ny + 1) * 0.5));
    // Vertical position controls pitch height, horizontal position shifts degree & stereo pan
    const rawIdx = Math.round(uy * 5.2 + ux * 2.2);
    const idx = Math.max(0, Math.min(scale.length - 1, rawIdx));
    return {
      freq: scale[idx],
      fifth: scale[Math.min(scale.length - 1, idx + 2)],
      low: scale[Math.max(0, idx - 2)],
      pan: Math.max(-0.78, Math.min(0.78, nx * 0.78)),
      ux,
      uy
    };
  }

  function playPulse(power = 1.0, opts = {}) {
    withUnlocked(() => {
      const p = Math.max(0.4, Math.min(1.5, power));
      const sc = opts.scene !== undefined ? Math.max(0, Math.min(5, opts.scene | 0)) : state.scene;
      const nx = typeof opts.nx === 'number' && Math.abs(opts.nx) <= 1.2 ? opts.nx : 0;
      const ny = typeof opts.ny === 'number' && Math.abs(opts.ny) <= 1.2 ? opts.ny : 0;
      const { freq, fifth, low, pan, uy } = pickStagePitch(sc, nx, ny);

      if (sc === 0) {
        // 00 Liquid Droplet & Caustic Mirror: buoyant water-drop pitch-up + ripple sub
        playTone({ freq: freq * 0.72, freqEnd: freq * 1.18, type: 'sine', gain: 0.11 * p, attack: 0.004, decay: 0.16, wet: 0.45, pan });
        playTone({ freq: freq * 1.18, type: 'sine', gain: 0.055 * p, attack: 0.005, decay: 0.42 * p, delay: 0.032, wet: 0.72, pan });
        if (uy < 0.42) {
          playTone({ freq: low * 0.5, freqEnd: low * 0.42, type: 'sine', gain: 0.075 * p, attack: 0.006, decay: 0.28, wet: 0.35, pan });
        }
      } else if (sc === 1) {
        // 01 Optical Glass Tablet: crisp non-harmonic glass tap (1 : 2.32 : 3.85)
        playTone({ freq, type: 'sine', gain: 0.085 * p, attack: 0.002, decay: 0.22 * p, wet: 0.38, pan });
        playTone({ freq: freq * 2.32, type: 'sine', gain: 0.036 * p, attack: 0.002, decay: 0.11, wet: 0.45, pan });
        playTone({ freq: freq * 3.85, type: 'sine', gain: 0.014 * p, attack: 0.001, decay: 0.06, wet: 0.3, pan });
        playNoiseBurst({ freq: 2600 + uy * 1400, freqEnd: 1400, q: 2.8, gain: 0.018 * p, attack: 0.002, decay: 0.06, pan });
      } else if (sc === 2) {
        // 02 8-Petal Astrolabe: crystalline dual-chime arpeggio
        playTone({ freq, type: 'sine', gain: 0.075 * p, attack: 0.004, decay: 0.46 * p, wet: 0.62, pan });
        playTone({ freq: fifth, type: 'sine', gain: 0.055 * p, attack: 0.005, decay: 0.56 * p, delay: 0.038, wet: 0.72, pan: -pan * 0.45 });
        playTone({ freq: freq * 2, type: 'triangle', gain: 0.022 * p, attack: 0.008, decay: 0.38, delay: 0.07, wet: 0.68, pan, filterFreq: 3600 });
      } else if (sc === 3) {
        // 03 Helicoid Forge: deep metallic gyro resonance + FM-like harmonic shimmer
        playTone({ freq: freq * 0.5, freqEnd: freq * 0.44, type: 'triangle', gain: 0.11 * p, attack: 0.005, decay: 0.34, wet: 0.42, pan, filterFreq: 950 });
        playTone({ freq: freq * 1.414, type: 'sine', gain: 0.048 * p, attack: 0.004, decay: 0.38 * p, delay: 0.015, wet: 0.62, pan });
        playNoiseBurst({ freq: 680 + uy * 700, freqEnd: 340, q: 1.8, gain: 0.026 * p, attack: 0.006, decay: 0.22, pan });
      } else if (sc === 4) {
        // 04 Diamond DAG Spire: razor-sharp faceted diamond sparkle
        playTone({ freq, type: 'triangle', gain: 0.068 * p, attack: 0.002, decay: 0.20 * p, wet: 0.45, pan, filterFreq: 4800 });
        playTone({ freq: freq * 1.5, type: 'sine', gain: 0.048 * p, attack: 0.002, decay: 0.28, delay: 0.018, wet: 0.58, pan });
        playTone({ freq: freq * 2.75, type: 'sine', gain: 0.022 * p, attack: 0.001, decay: 0.14, delay: 0.028, wet: 0.5, pan });
      } else {
        // 05 Solar Eclipse Finale: serene wide celestial chime
        playTone({ freq: low, type: 'sine', gain: 0.075 * p, attack: 0.01, decay: 0.72 * p, wet: 0.7, pan });
        playTone({ freq: fifth, type: 'sine', gain: 0.052 * p, attack: 0.014, decay: 0.85 * p, delay: 0.045, wet: 0.8, pan: -pan * 0.5 });
        playTone({ freq: freq * 2.25, type: 'sine', gain: 0.024 * p, attack: 0.02, decay: 0.92, delay: 0.09, wet: 0.85, pan });
      }
    });
  }

  function playShockRelease(chargePower = 1.0, opts = {}) {
    if (!isReady()) return;
    const p = Math.max(0.6, Math.min(1.6, chargePower));
    const sc = opts.scene !== undefined ? Math.max(0, Math.min(5, opts.scene | 0)) : state.scene;
    const nx = typeof opts.nx === 'number' && Math.abs(opts.nx) <= 1.2 ? opts.nx : 0;
    const ny = typeof opts.ny === 'number' && Math.abs(opts.ny) <= 1.2 ? opts.ny : 0;
    const { freq, fifth, low, pan } = pickStagePitch(sc, nx, ny);

    playTone({ freq: Math.max(95, low * 0.45), freqEnd: 42, type: 'sine', gain: 0.14 * p, attack: 0.004, decay: 0.36, wet: 0.25, pan });
    playNoiseBurst({ freq: 420, freqEnd: 2400, q: 0.9, gain: 0.042 * p, attack: 0.01, decay: 0.34, wet: 0.5, pan });
    [low, freq, fifth, freq * 2].forEach((f, idx) => {
      playTone({
        freq: f,
        type: sc === 4 || sc === 3 ? 'triangle' : 'sine',
        gain: 0.042 * p,
        attack: 0.006,
        decay: 0.68,
        delay: idx * 0.036,
        wet: 0.75,
        pan: pan * (1 - idx * 0.25),
        filterFreq: sc === 3 ? 2200 : null
      });
    });
  }

  function playNodeHover(kind, index = 0, nx = 0) {
    if (!isReady()) return;
    const now = performance.now();
    if (now - lastHoverAt < 58) return;
    lastHoverAt = now;

    const base = CRYSTAL_SCALE[Math.abs(index) % CRYSTAL_SCALE.length];
    const freq = kind === 'dag' ? base * 1.25 : base;
    const pan = Math.max(-0.75, Math.min(0.75, nx * 0.75));
    playTone({
      freq,
      type: kind === 'dag' ? 'triangle' : 'sine',
      gain: 0.040,
      attack: 0.003,
      decay: 0.20,
      wet: 0.6,
      pan,
      filterFreq: 4200
    });
  }

  function playPluginToggle(enabled) {
    withUnlocked(() => {
      if (enabled) {
        playTone({ freq: 523.25, type: 'sine', gain: 0.075, attack: 0.004, decay: 0.28, wet: 0.55 });
        playTone({ freq: 783.99, type: 'sine', gain: 0.08, attack: 0.004, decay: 0.45, delay: 0.055, wet: 0.65 });
      } else {
        playTone({ freq: 659.25, type: 'sine', gain: 0.06, attack: 0.004, decay: 0.22, wet: 0.4 });
        playTone({ freq: 440.0, type: 'sine', gain: 0.055, attack: 0.005, decay: 0.34, delay: 0.05, wet: 0.45 });
      }
    });
  }

  function playForgeCollapse() {
    withUnlocked(() => {
      // 1.05s inward compression sweep matching forgePinchProgress 0 -> 0.52
      playTone({ freq: 185, freqEnd: 460, type: 'triangle', gain: 0.065, attack: 0.14, decay: 0.92, wet: 0.6, filterFreq: 1800 });
      playNoiseBurst({ freq: 1600, freqEnd: 440, q: 1.8, gain: 0.032, attack: 0.12, decay: 0.88, wet: 0.5 });
    });
  }

  function playForgeConfirm() {
    if (!isReady()) return;
    playTone({ freq: 140, freqEnd: 56, type: 'sine', gain: 0.13, attack: 0.004, decay: 0.24, wet: 0.25 });
    [659.25, 987.77, 1318.51].forEach((f, i) => {
      playTone({
        freq: f,
        type: 'sine',
        gain: 0.068,
        attack: 0.004,
        decay: 0.58,
        delay: i * 0.048,
        wet: 0.72
      });
    });
  }

  function playLayerFan() {
    if (!isReady()) return;
    playNoiseBurst({ freq: 680, freqEnd: 2100, q: 1.4, gain: 0.022, attack: 0.04, decay: 0.32, wet: 0.55 });
    playTone({ freq: 587.33, type: 'sine', gain: 0.028, attack: 0.02, decay: 0.38, wet: 0.65 });
  }

  function playSceneTransition(newScene, prevScene) {
    if (!isReady()) return;
    const now = performance.now();
    if (now - lastSceneWhooshAt < 240) return;
    lastSceneWhooshAt = now;

    const up = newScene >= prevScene;
    playNoiseBurst({
      freq: up ? 340 : 880,
      freqEnd: up ? 960 : 320,
      q: 1.1,
      gain: 0.024,
      attack: 0.03,
      decay: 0.28,
      wet: 0.48
    });
    const chord = STAGE_CHORDS[newScene] || STAGE_CHORDS[0];
    playTone({
      freq: chord[2],
      type: 'sine',
      gain: 0.034,
      attack: 0.015,
      decay: 0.52,
      wet: 0.7
    });
  }

  function playUiTick(kind = 'click') {
    withUnlocked(() => {
      if (kind === 'theme') {
        playTone({ freq: 740, freqEnd: 520, type: 'sine', gain: 0.04, attack: 0.003, decay: 0.14, wet: 0.4 });
      } else if (kind === 'lang') {
        playTone({ freq: 880, type: 'sine', gain: 0.035, attack: 0.002, decay: 0.11, wet: 0.35 });
      } else if (kind === 'play') {
        playTone({ freq: 523.25, type: 'sine', gain: 0.045, attack: 0.004, decay: 0.22, wet: 0.45 });
        playTone({ freq: 659.25, type: 'sine', gain: 0.045, attack: 0.004, decay: 0.28, delay: 0.045, wet: 0.5 });
      } else {
        playTone({ freq: 660, type: 'sine', gain: 0.028, attack: 0.002, decay: 0.09, wet: 0.3 });
      }
    });
  }

  function updateFrame({
    scene = 0,
    holdCharge = 0,
    layerSpread = 0,
    pointerSpeed = 0,
    pluginRatio = state.pluginRatio,
    lightMode = state.lightMode
  }) {
    state.scene = Math.max(0, Math.min(5, scene | 0));
    state.pluginRatio = pluginRatio;
    state.lightMode = Boolean(lightMode);

    if (state.scene !== lastScene) {
      playSceneTransition(state.scene, lastScene);
      lastScene = state.scene;
    }

    const layerOpen = layerSpread > 0.34;
    if (layerOpen && !lastLayerOpen) {
      playLayerFan();
    }
    lastLayerOpen = layerOpen;

    if (!isReady()) return;
    const now = ctx.currentTime;

    reverbDamp.frequency.setTargetAtTime(state.lightMode ? 4800 : 3100, now, 0.25);
    const fb = state.lightMode ? 0.30 : 0.40;
    fbL.gain.setTargetAtTime(fb, now, 0.25);
    fbR.gain.setTargetAtTime(fb, now, 0.25);

    // Modulate gravity-whirlpool charge hum only while actively holding (> 0.03)
    const ch = Math.max(0, Math.min(1, holdCharge));
    if (ch > 0.03) {
      chargeGain.gain.setTargetAtTime(0.008 + ch * 0.055, now, 0.04);
      const f = 128 + ch * 215;
      chargeOsc.frequency.setTargetAtTime(f, now, 0.05);
      chargeSub.frequency.setTargetAtTime(f * 0.5, now, 0.05);
      chargeFilter.frequency.setTargetAtTime(240 + ch * 1450, now, 0.05);
    } else {
      chargeGain.gain.setTargetAtTime(0, now, 0.025);
    }

    // Subtle pointer ribbon whisper on brisk sweeps
    if (pointerSpeed > 9.5) {
      const tMs = performance.now();
      if (tMs - lastWhisperAt > 190) {
        lastWhisperAt = tMs;
        const norm = Math.min(1, (pointerSpeed - 9.5) / 9.5);
        playNoiseBurst({
          freq: 1400 + norm * 1600,
          freqEnd: 900,
          q: 2.2,
          gain: 0.007 + norm * 0.010,
          attack: 0.012,
          decay: 0.12,
          wet: 0.40
        });
      }
    }
  }

  async function toggleEnabled() {
    state.enabled = !state.enabled;
    safeWritePref(state.enabled);

    if (state.enabled) {
      await unlockFromGesture();
      syncMasterRamp();
      playUiTick('play');
    } else {
      syncMasterRamp();
      if (ctx && ctx.state === 'running') {
        setTimeout(() => {
          if (!state.enabled && ctx && ctx.state === 'running') {
            ctx.suspend().catch(() => {});
          }
        }, 120);
      }
    }
    notify();
    return getStatus();
  }

  document.addEventListener('visibilitychange', () => {
    if (!ctx) return;
    if (document.hidden) {
      syncMasterRamp();
      setTimeout(() => {
        if (document.hidden && ctx && ctx.state === 'running') {
          ctx.suspend().catch(() => {});
        }
      }, 120);
    } else if (state.enabled && state.unlocked) {
      ctx.resume().then(() => syncMasterRamp()).catch(() => {});
    }
  });

  // Unlock smoothly on first real user gesture if sound is enabled
  const gestureEvents = ['pointerdown', 'keydown'];
  function handleFirstGesture() {
    if (state.enabled && !state.unlocked) {
      unlockFromGesture();
    }
  }
  gestureEvents.forEach((evt) => {
    window.addEventListener(evt, handleFirstGesture, { passive: true, capture: true });
  });

  window.LucentSound = {
    getStatus,
    onStateChange(fn) {
      state.listeners.add(fn);
      fn(getStatus());
      return () => state.listeners.delete(fn);
    },
    unlockFromGesture,
    toggleEnabled,
    updateFrame,
    playPulse,
    playShockRelease,
    playNodeHover,
    playPluginToggle,
    playForgeCollapse,
    playForgeConfirm,
    playUiTick
  };
})();
