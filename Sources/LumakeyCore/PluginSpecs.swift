import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginSystem {
    public static let specMarkdown: String = """
    # Lumakey Plugin Specification (v1)
    - Directory: ~/Library/Application Support/Lumakey/Plugins/<id>/
    - Manifest (`plugin.json`): id (`[a-z0-9-]+`), name, version, description, mode (`script` | `view`), keywords (`[String]`), entry (relative path)
    - Script protocol: reads `{"query":"..."}` JSON from stdin, writes plain result text to stdout, exits 0.
    """

    public static let specV2Markdown: String = """
    # Lumakey Plugin Specification (v2)
    - Backward-compatible with v1 `plugin.json`; optional v2 fields: `author`, `icon` (SF Symbol or relative bundle image), `hotkey`, `config` (`[PluginConfigField]` with `key`, `label`, `type`: `text|secret|boolean|select`, `defaultValue`, `placeholder`, `options`, `required`).
    - State & Config: persisted in `plugin-state.json` (`isEnabled` + `configValues`), hot-reloaded with 350ms FSEvents debounce.
    - Enriched stdin JSON: `{"query":"...","mode":"script|view","locale":"zh-Hans|en","theme":"pure-frost|prism-pulse","config":{...},"clipboard":"..."}`.
    - Declarative `view` stdout JSON (`PluginViewPayload`): `{"title":"...","subtitle":"...","badge":"...","markdown":"...","metrics":[{"key":"...","value":"..."}],"items":[{"title":"...","subtitle":"...","icon":"...","tintColor":"...","badge":"...","copyText":"...","openURL":"...","commandArgs":["..."]}]}` (gracefully degrades to plain text if stdout is non-JSON).
    """

    public static let specV3Markdown: String = """
    # Lumakey Plugin Specification (v3.5 · Tiered Global Search Registration, PluginData Backup & Native Experience)

    Lumakey is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution Only**: Plugins are spawned when triggered, emit stdout, and exit immediately. Swift Task cancellation terminates the entire child process group cleanly.
    3. **Mandatory Permission & Resource Declaration on Registration**: Every plugin MUST explicitly declare BOTH `"capabilities"` (Host Bridge capabilities or `[]`) AND `"resourceScopes"` (`network`, `filesystem`, `subprocess`, or `[]`). Omitting either fails strict validation.
    4. **Encrypted Secrets & Gated Context**: `type: "secret"` fields are encrypted locally (never stored in plaintext in `plugin-state.json`). `stdin.clipboard` is injected ONLY when `"clipboard"` is both declared and granted.
    5. **Code/State/Override Separation & Default-OFF Quick Buttons**: Put immutable code/icons in `Plugins/<id>/`, write caches/`search-index.json`/`status.json` into `LUMAKEY_DATA_DIR`, while user customizations (`customKeywords`, `customHotKey`, `commandHotKeys`, `pinnedInOverlay`, `quickButtonCommandIDs`, `commandSearchOverrides`, `includeInGlobalSearchOverride`, `searchIndexGlobalOverride`, `showInSettingsSidebar`, `priorityBoost`) live in `plugin-state.json` (`overrides`). **By default, ALL plugins and ALL sub-commands have NO Quick Button enabled (`pinnedInOverlay = false`, `quickButtonCommandIDs = []`)**.
    6. **Tiered Global Search Control on Registration**:
       - Manifest root supports `"includeInGlobalSearch": true|false` (default `true`) and `"searchIndexInGlobalSearch": true|false` (default inherits main entry).
       - Each item in `"commands"` supports `"includeInGlobalSearch": true|false` independently of the main entry (allowing hotkey-only or scoped-only commands, or exposing selected commands while hiding the main entry).
       - Each item in `search-index.json` supports `"includeInGlobalSearch": true|false` (default `true` when index pool is enabled).
    7. **Backup v2 & External Path Inclusion**: `PluginData/<id>/` is backed up automatically (skipping `.tmp-*`, `cache/`, `*.log`, `*.sock`, plus optional manifest `"backupExclude": ["raw/*"]`). `config` fields with `type: "path"` may set `"includeInBackup": true` to bundle user-home data files with portable `~/...` path restoration.

    ## Native Visuals, Bilingual Manifest & Deep Links
    - **Custom Bundle Icons & Brand Accent**: `icon` accepts either an SF Symbol (`"bookmark.fill"`) or a relative image path inside the plugin folder (`"icon.svg"`, `"assets/icon.png"`). Optional `"accentColor"` (`"teal"`, `"cyan"`, `"orange"`, `"#14B8A6"`, etc.) and `"categoryTag"` (`"书签"`) give external plugins first-class native badges instead of raw `VIEW`/`SCRIPT` labels.
    - **Bilingual `locales` & Runtime Context**: Optional `"locales": { "en": { "name": "...", "description": "...", "categoryTag": "...", "commands": { "<cmdId>": { "title": "...", "subtitle": "..." } }, "config": { "<key>": { "label": "...", "section": "...", "helpText": "..." } } } }` adapts UI live when switching between `简体中文` and `English`. Subprocesses also receive `"locale"` and `"theme"` in `stdin` JSON plus `LUMAKEY_LOCALE` and `LUMAKEY_THEME` env vars.
    - **Auto-Saved Preferences & Sliders**: `config` fields auto-save in Settings; `type: "number"` supports `"control": "slider"` when `minValue < maxValue` are provided.
    - **Sub-Command Global Hotkeys & Lightweight Status**: Each item in `commands` supports optional `"hotkey"` and `"silentWhenHotKeyTriggered": true`, and users can record per-command hotkeys (`commandHotKeys`). Returning `"effect": { "statusSummary": "...", "statusBadge": "..." }` (or writing `PluginData/<id>/status.json`) updates the plugin's zero-subprocess status subtitle.
    - **Rich Markdown & Host Window Deep Links**: `PluginViewPayload.markdown` renders full blocks (tables, fenced code, quotes, callouts, checklists) via `MarkdownBlocksStackView`. `openURL` and `effect` support `lumakey://reader?path=/abs/doc.md` (or `?title=...&markdown=...`), `lumakey://image?path=/abs/img.png&pin=1`, `lumakey://pin?path=/abs/img.png`, and `lumakey://settings/plugin/<id>`.

    ## Capabilities & Ephemeral Host Bridge Protocol
    Declared capabilities default to **DENIED** until toggled ON in Lumakey (`grantedCapabilities`).
    When `capabilities` is non-empty, Lumakey creates an ephemeral `0600` Unix Domain Socket inside a `0700` user-private directory and injects:
    - Env vars: `LUMAKEY_BRIDGE_SOCK`, `LUMAKEY_BRIDGE_TOKEN`, `LUMAKEY_DATA_DIR`, `LUMAKEY_LOCALE`, `LUMAKEY_THEME`
    - `stdin` JSON: `{"query":"...","mode":"...","locale":"...","theme":"...","config":{...},"clipboard":"...","context":{...},"dataDir":"...","bridge":{"socket":"...","token":"...","grantedCapabilities":[...]}}`

    ### Available Capabilities & Actions
    - `clipboard`: `read` (`params:{}`) -> `{text}`; `write` (`params:{"text":"..."}`) -> `{written,length}`
    - `selection`: `read` (`params:{}`) -> `{text,sourceApp,bundleIdentifier}`
    - `audio`: `play` (`params:{"path":"/abs/file.mp3"}`); `speak` (`params:{"text":"...","language":"en-US"}`); `stop` (`params:{}`)
    - `ocr`: `recognize` (`params:{"imagePath":"/abs/path.png"}`) -> `{text,barcodes}`
    - `everythingSearch`: `search` (`params:{"query":"ext:md","limit":20}`) -> `{indexLoaded,count,hits:[...]}`
    - `displayInfo`: `list` (`params:{}`) -> `{displays:[{displayID,name,isMain,currentModeKey,modes:[...]}]}`
    - `systemControl`: `status`; `setVolume` (`{"percent":50}`); `setMute` (`{"muted":true|false|"toggle"}`); `setCaffeine` (`{"active":true|false}`)
    - `lumaLinkStatus`: `status` (`params:{}`) -> `{enabled,isListening,port,connectedDeviceCount,pairedDeviceCount,rdpEnabled,rdpRunning,localIPv4}`
    """
}
