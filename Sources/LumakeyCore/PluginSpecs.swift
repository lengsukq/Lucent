import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginSystem {
    public static let specV3Markdown: String = """
    # Lumakey Plugin Specification (v3.6 · Custom WebView Windows, Frameless Floating HUD & Host TCC Broker)

    Lumakey is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution & Window-Bound Lifecycle**: Subprocesses emit stdout and exit immediately; custom windows (`window` / `floatingWindow`) live strictly while visible and tear down `WKWebView` + tasks immediately on close.
    3. **Mandatory Permission & Resource Declaration on Registration**: Every plugin MUST explicitly declare BOTH `"capabilities"` (Host Bridge / Window container capabilities or `[]`) AND `"resourceScopes"` (`network`, `filesystem`, `subprocess`, or `[]`).
    4. **Host-Brokered System TCC ("macOS trusts Host, Host audits Plugin")**: Plugins NEVER prompt macOS TCC directly from unsigned scripts. When a granted capability requires macOS TCC (`selection` -> Accessibility, `screenCapture` -> Screen Recording, `notifications` -> Notifications), `Lumakey.app` checks and requests macOS TCC on the plugin's behalf (`PluginHostTCCBroker`).
    5. **Encrypted Secrets & Gated Context**: `type: "secret"` fields are sealed in `LMKYVLT2` (`0600` AES-GCM). `stdin.clipboard` is injected ONLY when `"clipboard"` is declared and granted.
    6. **Code/State/Override Separation & Default-OFF Quick Buttons**: Keep immutable code/icons/HTML in `Plugins/<id>/`, write caches/`search-index.json`/`status.json` into `LUMAKEY_DATA_DIR`, and keep `pinnedInOverlay = false`, `quickButtonCommandIDs = []` by default.
    7. **Tiered Global Search & Backup v2**: `includeInGlobalSearch` and `searchIndexInGlobalSearch` control global search visibility per plugin/command/item; `PluginData/<id>/` is included in `.lumakeybackup` v2 (`LZFSE` compressed).

    ## Unrestricted Custom Windows & Floating HUDs (`window` / `floatingWindow`)
    Plugins have **100% UI freedom** via native `WKWebView` canvases without losing lightweight JSON cards:
    - **Manifest Defaults (`plugin.json`)**: Optional `"window": { "entryHtml": "ui/widget.html", "width": 392, "height": 488, "minWidth": 280, "minHeight": 160, "resizable": true, "chrome": "standard"|"frameless"|"hud", "transparent": true, "pinOnTop": true, "clickThrough": false, "opacity": 1.0 }`.
    - **Launch Routes**:
      - Deep link: `lumakey://window/<id>?html=ui/widget.html&chrome=frameless&transparent=1&pin=1&w=392&h=488`
      - Post-action effect: `"effect": { "openWindow": { "windowID": "hud", "htmlPath": "ui/widget.html", "chrome": "frameless", "transparent": true, "pinOnTop": true, "width": 392, "height": 488 }, "closeOverlay": true }`
      - Structured card floating panel (zero HTML needed): `lumakey://panel/<id>?pin=1&interval=30` or `"effect": { "openFloatingPanel": true }`.
    - **Injected `window.lumakey` JS SDK**:
      - `lumakey.env` -> `{ pluginId, pluginName, version, windowId, chrome, transparent, pinOnTop, locale, theme, declaredCapabilities, grantedCapabilities, initialState }`
      - `await lumakey.run(args = [], query = "")` -> `{ ok, exitCode, stdout, stderr, durationMs, data }`
      - `await lumakey.bridge(capability, action, params = {})` -> invokes Host Bridge directly
      - `await lumakey.permissions.status()` / `await lumakey.permissions.request(capability)` -> triggers host permission prompt + macOS TCC broker
      - `await lumakey.window.{startDrag, resize, moveTo, setPinned, setClickThrough, setOpacity, minimize, close}` (any HTML element with `data-lumakey-drag` drags frameless windows natively at 120Hz; opacity clamped `0.15...1.0`, max `4` windows per plugin, menu bar includes 1-click close-all escape hatch).

    ## Capabilities, Post-Action Effects & Host Bridge Actions
    Declared capabilities default to **DENIED** until granted (`grantedCapabilities`):
    - `window`: `open` (`{htmlPath,width,height,title}`), `close` (`{windowID}`) — standard custom HTML/CSS/Canvas windows
    - `floatingWindow`: `open` (`{htmlPath,chrome:"frameless"|"hud",transparent:true,pinOnTop:true,clickThrough:false}`), `close` — pinned, frameless, transparent HUDs (implies `window`)
    - `screenCapture`: `status`, `requestPermission`, `sampleColor` (`{x,y}` -> `{hex,rgb}`), `captureMainDisplay` (`{}` -> `{imagePath,width,height}`), `captureInteractive` (`{}` -> `{cancelled,imagePath,width,height}`)
    - `notifications`: `status`, `requestPermission`, `send` (`{title,subtitle,body,sound}`) -> native macOS banner
    - `clipboard`: `read` -> `{text}`; `write` (`{text}`) -> `{written,length}`; `writeImage` (`{imagePath}`) -> `{written,width,height,bytes}`
    - `selection`: `read` -> `{text,sourceApp,bundleIdentifier,accessibilityGranted}`; `pasteBack` (`{text}`) -> writes clipboard, restores active app focus & synthesizes `⌘V` (also available via `effect.pasteText`)
    - `audio`: `play` (`{path}`), `speak` (`{text,language}`), `stop`
    - `ocr`: `recognize` (`{imagePath}`) -> `{text,barcodes}`
    - `everythingSearch`: `search` (`{query,limit}`) -> `{indexLoaded,count,hits}`
    - `displayInfo`: `list` -> `{displays}`
    - `systemControl`: `status`, `setVolume`, `setMute`, `setCaffeine`, `setStatusScreen`, `clearStatusScreen`
    - `lumaLinkStatus`: `status` and LumaLink companion actions
    """
}
