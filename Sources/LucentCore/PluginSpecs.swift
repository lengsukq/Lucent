import Foundation

extension PluginSystem {
    public static let specV3Markdown: String = """
    # Lucent Plugin Specification (v3.7 · Sandboxed WebView Canvas, Geometry Memory, Granular Contexts & Live Progress)

    Lucent is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution & Window-Bound Lifecycle**: Subprocesses emit stdout and exit immediately (default timeout `8s`, configurable `timeoutSeconds: 3...30` in `plugin.json`; live stage progress via `{"token":"...","op":"progress","message":"..."}` over `LUCENT_BRIDGE_SOCK`). Custom windows (`window` / `floatingWindow`) live strictly while visible and tear down `WKWebView` + tasks immediately on close.
    3. **Mandatory Permission & Resource Declaration on Registration**: Every plugin MUST explicitly declare BOTH `"capabilities"` (Host Bridge / Window container capabilities or `[]`) AND `"resourceScopes"` (`network`, `filesystem`, `subprocess`, or `[]`). Both CLI Seatbelt (`sandbox-exec`) AND custom `WKWebView` canvases (`WKContentRuleList`) strictly block external network access when `"network"` is not granted.
    4. **Host-Brokered System TCC & Version Gate**: Optional `"minAppVersion"` (e.g. `"0.9.0"`) prevents installation on older Lucent hosts. Plugins NEVER prompt macOS TCC directly; `Lucent.app` brokers Accessibility, Screen Recording, and Notifications (`PluginHostTCCBroker`).
    5. **Encrypted Secrets & Granular Context Routing**: `type: "secret"` fields are sealed in `LCNTVLT2` (`0600` AES-GCM). Optional `"accepts"` (`url`, `text`, `image`, `file`, `directory`) can be narrowed via `"acceptExtensions"` (e.g. `["pdf", "md"]`) and `"acceptURLHosts"` (e.g. `["github.com"]`).
    6. **Code/State/Override Separation & Default-OFF Pins**: Keep immutable code/icons/HTML in `Plugins/<id>/`, write caches/`search-index.json`/`status.json`/`window-frames.json` into `LUCENT_DATA_DIR`, and keep `pinnedInOverlay = false`, `showInMenuBar = false`, `quickButtonCommandIDs = []`, `menuBarCommandIDs = []` by default.
    7. **Tiered Global Search & Backup v2**: `includeInGlobalSearch` and `searchIndexInGlobalSearch` control global search visibility; `PluginData/<id>/` and `menubar-config.json` are included in `.lucentbackup` v2 (`LZFSE` compressed).

    ## Unrestricted Custom Windows & Floating HUDs (`window` / `floatingWindow`)
    Plugins have **100% UI freedom** via native `WKWebView` canvases without losing lightweight JSON cards:
    - **Manifest Defaults (`plugin.json`)**: Optional `"window": { "entryHtml": "ui/widget.html", "width": 392, "height": 488, "minWidth": 280, "minHeight": 160, "resizable": true, "chrome": "standard"|"frameless"|"hud", "transparent": true, "pinOnTop": true, "clickThrough": false, "showInDock": false, "opacity": 1.0, "persistSession": true }` (`showInDock` defaults to `true` for `standard` windows and `false` for `frameless`/`hud` floating widgets; set `"persistSession": false` for on-demand tool windows that must never auto-reopen at app launch).
    - **Automatic Geometry Memory, Smooth Native Motion, File Drop & Live Events**: User-dragged position, resized dimensions, opacity, and pin state are automatically remembered per `windowID` across reopens (`window-frames.json`), and floating windows are safely clamped to visible screen bounds so they can never disappear off-screen. Pass `reuseIfOpen: true` in `openWindow` to focus an existing canvas and push a fresh `lucent:windowPayload` without tearing down active sessions. The host pushes `lucent:envChanged`, `lucent:windowPayload`, `lucent:filesDropped`, `lucent:fileDragState`, `lucent:frameChanged`, `lucent:dragStart`, `lucent:dragMove`, `lucent:dragEnd`, and `lucent:edgeProximity` events into the canvas.
    - **Window-Bound Session Process (`lucent.session`)**: A custom window may start at most one sandboxed session subprocess (`lucent.session.start(args)` -> NDJSON `stdin`/`stdout` via `lucent.session.send(obj)`, `onEvent`, `onExit`, `stop`). The host tears down the entire process group immediately when the window closes, plugin is disabled, or Lucent quits — zero resident daemons.
    - **Injected `window.lucent` JS SDK**:
      - `lucent.env` -> `{ pluginId, pluginName, version, windowId, chrome, transparent, pinOnTop, showInDock, locale, theme, declaredCapabilities, grantedCapabilities, initialState }`
      - `await lucent.run(args = [], query = "")` -> `{ ok, exitCode, stdout, stderr, durationMs, data }`
      - `await lucent.bridge(capability, action, params = {})` -> invokes Host Bridge directly
      - `lucent.session.{start, send, stop, onEvent, onExit}` -> window-bound sandboxed NDJSON process
      - `await lucent.permissions.status()` / `await lucent.permissions.request(capability)` -> triggers host permission prompt + macOS TCC broker
      - `await lucent.window.{getFrame, startDrag, resize, moveTo, animateFrame, morph, snapToEdge, setEdgeBehavior, setPinned, setShowInDock, setClickThrough, setOpacity, resetFrame, minimize, close}`
      - `lucent.window.{onPayload, onFilesDropped, onFileDragState, onFrameChanged, onDragStart, onDragMove, onDragEnd, onEdgeProximity}(listener)` -> returns unsubscribe function; `animateFrame` / `morph` / `snapToEdge` support `{ durationMs, easing: "spring"|"easeOut"|"easeInOut"|"linear", anchor, margin, keepOnScreen }` with native macOS AppKit `NSAnimationContext` motion (floating windows may morph down to compact `64x36` pills).

    ## Capabilities, Post-Action Effects & Host Bridge Actions
    Declared capabilities default to **DENIED** until granted (`grantedCapabilities`):
    - `window`: `open` (`{htmlPath,width,height,title}`), `close` (`{windowID}`) — standard custom HTML/CSS/Canvas windows
    - `floatingWindow`: `open` (`{htmlPath,chrome:"frameless"|"hud",transparent:true,pinOnTop:true,clickThrough:false}`), `close` — pinned, frameless, transparent HUDs (implies `window`)
    - `screenCapture`: `status`, `requestPermission`, `sampleColor` (`{x,y}` -> `{hex,rgb}`), `captureMainDisplay` (`{}` -> `{imagePath,width,height}`), `captureInteractive` (`{}` -> `{cancelled,imagePath,width,height}`)
    - `notifications`: `status`, `requestPermission`, `send` (`{title,subtitle,body,sound}`) -> native macOS banner
    - `clipboard`: `read` -> `{text}`; `write` (`{text}`) -> `{written,length}`; `writeImage` (`{imagePath}`) -> `{written,width,height,bytes}`
    - `selection`: `read` -> `{text,sourceApp,bundleIdentifier,accessibilityGranted}`; `pasteBack` (`{text}`) -> writes clipboard, restores active app focus & synthesizes `⌘V`
    - `audio`: `play` (`{path}`), `speak` (`{text,language}`), `stop`
    - `ocr`: `recognize` (`{imagePath}`) -> `{text,barcodes}`
    - `everythingSearch`: `search` (`{query,limit}`) -> `{indexLoaded,count,hits}`
    - `displayInfo`: `list` -> `{displays}`
    - `fileShelf`: `open`, `addContextItems` (no params; only files captured by the desktop host for the current invocation).
    - `audioDevices`: `list` / `status`, `apply` (`{inputUID,outputUID,showFeedback?}`), `setDevice` (`{direction:"input"|"output",uid}`); returns the actual defaults and `applied`, `unavailable`, `restored`, or `partial`.
    - `systemControl`: `status`, `setVolume`, `setMute`, `setCaffeine`, `setStatusScreen`, `clearStatusScreen`
    - `lumaLinkStatus`: `status` and LumaLink companion actions
    - `contextRouter`: `match` (`{kind,filePaths?,text?,url?,source?}` -> `{plugins}`) and `route` (`{targetPluginId,kind,...}`) for safe host-brokered cross-plugin routing
    """
}
