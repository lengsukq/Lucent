import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginSystem {
    public static let specV3Markdown: String = """
    # Lumakey Plugin Specification (v3.7 · Sandboxed WebView Canvas, Geometry Memory, Granular Contexts & Live Progress)

    Lumakey is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution & Window-Bound Lifecycle**: Subprocesses emit stdout and exit immediately (default timeout `8s`, configurable `timeoutSeconds: 3...30` in `plugin.json`; live stage progress via `{"token":"...","op":"progress","message":"..."}` over `LUMAKEY_BRIDGE_SOCK`). Custom windows (`window` / `floatingWindow`) live strictly while visible and tear down `WKWebView` + tasks immediately on close.
    3. **Mandatory Permission & Resource Declaration on Registration**: Every plugin MUST explicitly declare BOTH `"capabilities"` (Host Bridge / Window container capabilities or `[]`) AND `"resourceScopes"` (`network`, `filesystem`, `subprocess`, or `[]`). Both CLI Seatbelt (`sandbox-exec`) AND custom `WKWebView` canvases (`WKContentRuleList`) strictly block external network access when `"network"` is not granted.
    4. **Host-Brokered System TCC & Version Gate**: Optional `"minAppVersion"` (e.g. `"0.9.0"`) prevents installation on older Lumakey hosts. Plugins NEVER prompt macOS TCC directly; `Lumakey.app` brokers Accessibility, Screen Recording, and Notifications (`PluginHostTCCBroker`).
    5. **Encrypted Secrets & Granular Context Routing**: `type: "secret"` fields are sealed in `LMKYVLT2` (`0600` AES-GCM). Optional `"accepts"` (`url`, `text`, `image`, `file`, `directory`) can be narrowed via `"acceptExtensions"` (e.g. `["pdf", "md"]`) and `"acceptURLHosts"` (e.g. `["github.com"]`).
    6. **Code/State/Override Separation & Default-OFF Pins**: Keep immutable code/icons/HTML in `Plugins/<id>/`, write caches/`search-index.json`/`status.json`/`window-frames.json` into `LUMAKEY_DATA_DIR`, and keep `pinnedInOverlay = false`, `showInMenuBar = false`, `quickButtonCommandIDs = []`, `menuBarCommandIDs = []` by default.
    7. **Tiered Global Search & Backup v2**: `includeInGlobalSearch` and `searchIndexInGlobalSearch` control global search visibility; `PluginData/<id>/` and `menubar-config.json` are included in `.lumakeybackup` v2 (`LZFSE` compressed).

    ## Unrestricted Custom Windows & Floating HUDs (`window` / `floatingWindow`)
    Plugins have **100% UI freedom** via native `WKWebView` canvases without losing lightweight JSON cards:
    - **Manifest Defaults (`plugin.json`)**: Optional `"window": { "entryHtml": "ui/widget.html", "width": 392, "height": 488, "minWidth": 280, "minHeight": 160, "resizable": true, "chrome": "standard"|"frameless"|"hud", "transparent": true, "pinOnTop": true, "clickThrough": false, "opacity": 1.0 }`.
    - **Automatic Geometry Memory & Live Env Events**: User-dragged position, resized dimensions, opacity, and pin state are automatically remembered per `windowID` across reopens (`window-frames.json`). When the user switches theme, language, or capabilities while a window is open, the host updates `window.lumakey.env` and dispatches `window.addEventListener("lumakey:envChanged", e => ...)`.
    - **Injected `window.lumakey` JS SDK**:
      - `lumakey.env` -> `{ pluginId, pluginName, version, windowId, chrome, transparent, pinOnTop, locale, theme, declaredCapabilities, grantedCapabilities, initialState }`
      - `await lumakey.run(args = [], query = "")` -> `{ ok, exitCode, stdout, stderr, durationMs, data }`
      - `await lumakey.bridge(capability, action, params = {})` -> invokes Host Bridge directly
      - `await lumakey.permissions.status()` / `await lumakey.permissions.request(capability)` -> triggers host permission prompt + macOS TCC broker
      - `await lumakey.window.{startDrag, resize, moveTo, setPinned, setClickThrough, setOpacity, resetFrame, minimize, close}`

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
    - `systemControl`: `status`, `setVolume`, `setMute`, `setCaffeine`, `setStatusScreen`, `clearStatusScreen`
    - `lumaLinkStatus`: `status` and LumaLink companion actions
    """
}
