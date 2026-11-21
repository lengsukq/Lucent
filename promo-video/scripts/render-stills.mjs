#!/usr/bin/env node
import { bundle } from '@remotion/bundler';
import { renderStill, selectComposition } from '@remotion/renderer';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = path.resolve(__dirname, '..');
const OUT_DIR = path.join(PROJECT_DIR, 'out/stills');
fs.mkdirSync(OUT_DIR, { recursive: true });

const BROWSER_BIN =
  '/Volumes/lightlsle/dependencies/remotion-browser/chrome-headless-shell/chrome-headless-shell-mac-arm64/chrome-headless-shell';

const FRAMES = [
  ['00_prologue_keycap', 240],
  ['00_prologue_panel', 860],
  ['01_home_dark', 1500],
  ['01_home_wipe', 2628],
  ['01_home_frost', 2850],
  ['02_search_files', 3540],
  ['02_search_clip', 4100],
  ['02_search_scripts', 5280],
  ['03_capture', 5860],
  ['03_gif', 6360],
  ['03_ocr', 6860],
  ['03_mouse_120hz', 7260],
  ['03_toolbox', 7850],
  ['04_plugins_7', 8860],
  ['04_widget', 9600],
  ['05_mcp_plugin', 10760],
  ['05_mcp_script_svg', 11540],
  ['06_dag', 12860],
  ['06_memory_frost', 13880],
  ['07_finale', 14420],
];

console.log('==> Bundling Remotion project once...');
const serveUrl = await bundle({
  entryPoint: path.join(PROJECT_DIR, 'src/index.ts'),
  onProgress: () => {},
});

const inputProps = { enableAudio: false };
const composition = await selectComposition({
  serveUrl,
  id: 'LucentPromo',
  inputProps,
  browserExecutable: BROWSER_BIN,
  chromiumOptions: { gl: 'angle' },
});

console.log(`==> Rendering ${FRAMES.length} keyframe stills (1920x1080)...`);
for (const [name, frame] of FRAMES) {
  const output = path.join(OUT_DIR, `${name}_f${frame}.png`);
  await renderStill({
    composition,
    serveUrl,
    output,
    frame,
    inputProps,
    browserExecutable: BROWSER_BIN,
    chromiumOptions: { gl: 'angle' },
    imageFormat: 'png',
  });
  console.log(`  [OK] ${path.basename(output)}`);
}
console.log(`==> Done! All ${FRAMES.length} stills saved to ${OUT_DIR}`);
