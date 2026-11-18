import Foundation

extension ScriptLibraryStore {
    public static let specV1Markdown: String = """
    # Lucent Quick Scripts Library Specification (v1.0)

    Lucent's **Script Library (`Quick Scripts`)** provides a zero-boilerplate way for users and AI agents (`lucent-mcp`) to turn single-file scripts into native global quick actions with custom vector icons, bilingual names, hotkeys, and Launcher Home / Menu Bar mounts.

    ## 1. When to Use Quick Scripts vs. Plugins (`plugin-v3`)
    - **Use Quick Scripts (`lucent://specs/scripts-v1`)** for lightweight, single-file quick actions, text/clipboard transformers, developer utilities, Finder/AppleScript automations, or CLI wrappers (Zsh, Bash, Python 3, AppleScript, Swift, or Custom Shebang like Node / Deno / Ruby).
    - **Use External Plugins (`lucent://specs/plugin-v3`)** when you need multi-item interactive `PluginViewPayload` cards, persistent `search-index.json` pools, configuration forms with encrypted `.secret` vault fields, or custom `WKWebView` HUD windows.

    ## 2. Storage & Two-Way File Sync
    - Metadata index: `~/Library/Application Support/Lucent/scripts-library.json`.
    - Executable scripts: `~/Library/Application Support/Lucent/Scripts/<id>.<ext>` (`chmod 0755`).
    - Custom vector icons: `~/Library/Application Support/Lucent/Scripts/icons/<id>.svg`.
    - Dropping or editing a script in `Scripts/` with `# @lucent.*` (`-- @lucent.*` for AppleScript, `// @lucent.*` for Swift/JS/TS) magic comments in the first 30 lines automatically syncs metadata with Lucent.
    - All scripts and custom SVG icons are automatically included in `.lucentbackup` v2 encrypted archives and WebDAV sync.

    ## 3. Naming & Custom SVG Icon Crafting Guidelines (For AI Agents)
    Whenever creating or updating a script via `lucent_upsert_script`, you SHOULD give it both a clear name and a polished visual identity:
    1. **Clear Bilingual Naming**:
       - Provide a concise, action-oriented `title` (Chinese, e.g., `"压缩剪贴板 JSON"`, `"清理 Xcode 派生缓存"`) and `englishTitle` (e.g., `"Minify Clipboard JSON"`, `"Clean Xcode DerivedData"`), plus `subtitle` / `englishSubtitle` explaining what happens on execution.
       - Set memorable `keywords` (e.g., `["!jsonmin", "minify"]`) so the user can trigger it instantly from `⌥Space`.
    2. **Custom Vector Icon (`iconSvg` or SF Symbol + `accentColor`)**:
       - You can draw a bespoke vector badge directly by passing `iconSvg` to `lucent_upsert_script`! Lucent validates and saves it to `Scripts/icons/<id>.svg` and renders it natively across Launcher search rows, Side Lens, Bento Tiles, Omni Dock, Menu Bar, and Settings.
       - **SVG Rules**:
         - Use `<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">` (`<= 64 KB`).
         - Prefer a rounded squircle background (`<rect x="4" y="4" width="56" height="56" rx="15" .../>` with `<linearGradient>`) and crisp high-contrast geometric `<path>` / `<rect>` / `<circle>` foreground glyphs (`stroke-linecap="round"`).
         - Strictly NO `<script>`, `<foreignObject>`, `<iframe>`, `javascript:`, or external image URLs.
       - Alternatively, set `icon` to a native macOS SF Symbol (e.g., `"bolt.fill"`, `"wand.and.stars"`) paired with `accentColor` (`cyan`, `blue`, `indigo`, `purple`, `mint`, `teal`, `green`, `orange`, `pink`, `red`, `slate`, or `#RRGGBB`).

    ## 4. Supported Runtimes & Sandbox Scopes
    - `runtime`:
      - `"zsh"` (`/bin/zsh`), `"bash"` (`/bin/bash`), `"python3"` (auto-detected Python 3), `"appleScript"` (`/usr/bin/osascript`), `"swift"` (`/usr/bin/swift`), or `"customShebang"` (executes `#!` directly, e.g., `#!/usr/bin/env node`, `#!/usr/bin/env deno -A`, `#!/usr/bin/env ruby` with custom `fileExtension` such as `"mjs"`, `"ts"`, `"rb"`).
    - **Environment Inputs**:
      - `LUCENT_QUERY` (also passed as `$1` and `stdin` when non-empty), `LUCENT_SELECTED_TEXT`, `LUCENT_CLIPBOARD` (populated ONLY when `passClipboard: true`), `LUCENT_LOCALE`, `LUCENT_THEME`.
    - **Seatbelt Sandbox (`allowedScopes`)**:
      - Unconditionally blocks `.vault` and `~/Library/Keychains`.
      - Declare `allowedScopes` explicitly from `["network", "filesystem", "subprocess"]` (or `[]` for pure read-only local scripts). Note: `customShebang` scripts invoking Homebrew runtimes (`node`, `deno`, `ruby`, `bun`) or CLI tools (`git`, `curl`, `ffmpeg`) MUST include `"subprocess"` (and `"network"` / `"filesystem"` if they make network calls or write to `$HOME`).

    ## 5. Output Modes & Quick Action Mounting
    - `outputMode`: `"toast"` | `"inlinePreview"` | `"copyToClipboard"` | `"pasteToFrontApp"` | `"openReader"`.
    - Quick mounts (`pinnedInQuickBar`, `showInMenuBar`) default to `false` to keep the UI clean; enable them only when requested by the user.
    - To pin a script onto Launcher Home Bento Tiles, Omni Dock, or Pill Shelves, call `lucent_upsert_home_item` with `kind: "script"` and `scriptID: "<id>"`.
    - Always verify newly created or modified scripts using `lucent_run_script_test`.
    """
}
