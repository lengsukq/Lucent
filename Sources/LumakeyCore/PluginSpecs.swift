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
    - Backward-compatible with v1 `plugin.json`; optional v2 fields: `author`, `icon` (SF Symbol), `hotkey`, `config` (`[PluginConfigField]` with `key`, `label`, `type`: `text|secret|boolean|select`, `defaultValue`, `placeholder`, `options`, `required`).
    - State & Config: persisted in `plugin-state.json` (`isEnabled` + `configValues`), hot-reloaded with 350ms FSEvents debounce.
    - Enriched stdin JSON: `{"query":"...","mode":"script|view","config":{...},"clipboard":"..."}`.
    - Declarative `view` stdout JSON (`PluginViewPayload`): `{"title":"...","subtitle":"...","badge":"...","markdown":"...","metrics":[{"key":"...","value":"..."}],"items":[{"title":"...","subtitle":"...","icon":"...","badge":"...","copyText":"...","openURL":"...","commandArgs":["..."]}]}` (gracefully degrades to plain text if stdout is non-JSON).
    """

    public static let specV3Markdown: String = """
    # Lumakey Plugin Specification (v3.1)

    Lumakey is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution Only**: Plugins are spawned when triggered, emit stdout, and exit immediately. Swift Task cancellation terminates the entire child process group cleanly.
    3. **Mandatory Permission & Resource Declaration on Registration**: Every plugin MUST explicitly declare BOTH `"capabilities"` (Host Bridge capabilities or `[]`) AND `"resourceScopes"` (`network`, `filesystem`, `subprocess`, or `[]`). Omitting either fails strict validation.
    4. **Keychain Secrets & Gated Context**: `type: "secret"` fields are stored in macOS Keychain (never in `plugin-state.json`). `stdin.clipboard` is injected ONLY when `"clipboard"` is both declared and granted.
    5. **Code/State Separation**: Put immutable code in `Plugins/<id>/` and write caches/`search-index.json` into `LUMAKEY_DATA_DIR` (`stdin.dataDir` -> `Application Support/Lumakey/PluginData/<id>/`).

    ## Directory & `plugin.json` v3.1 Schema
    Path: `~/Library/Application Support/Lumakey/Plugins/<id>/plugin.json`
    ```json
    {
      "schemaVersion": 3,
      "id": "my-tool",
      "name": "My Tool",
      "version": "1.0.0",
      "description": "Short summary",
      "mode": "view",
      "keywords": ["mytool"],
      "entry": "run.sh",
      "author": "Author",
      "icon": "sparkles",
      "hotkey": "⌥⇧M",
      "capabilities": ["displayInfo", "systemControl"],
      "resourceScopes": ["subprocess"],
      "config": [
        { "key": "limit", "label": "Max Items", "type": "text", "defaultValue": "10" }
      ]
    }
    ```
    - `id` must match `[a-z0-9-]+` and MUST NOT start with `builtin-` (reserved for in-process native plugins).
    - `entry` must be an executable relative path inside the plugin directory (no `..` traversal).
    - Optional `search-index.json` inside `PluginData/<id>/` (or plugin directory fallback) enables zero-subprocess prefix-free search in the main launcher.
    - View items support multi-actions `actions: [{id, label, style: "primary|secondary|destructive", commandArgs, confirmMessage, promptFields}]` and top-level `effect: {toast, closeOverlay, reloadSearchIndex}`.

    ## Capabilities & Ephemeral Host Bridge Protocol
    Declared capabilities default to **DENIED** until toggled ON in Lumakey Plugin Center (`plugin-state.json` `grantedCapabilities`).
    When `capabilities` is non-empty, Lumakey creates an ephemeral `0600` Unix Domain Socket inside a `0700` user-private directory and injects:
    - Env vars: `LUMAKEY_BRIDGE_SOCK`, `LUMAKEY_BRIDGE_TOKEN`, and `LUMAKEY_DATA_DIR`
    - `stdin` JSON: `{"query":"...","mode":"...","config":{...},"clipboard":"...","dataDir":"...","bridge":{"socket":"...","token":"...","grantedCapabilities":[...]}}`

    Send one newline-terminated JSON request per UDS connection and read one JSON response line:
    Request: `{"token":"$LUMAKEY_BRIDGE_TOKEN","capability":"<cap>","action":"<act>","params":{...}}`
    Success: `{"ok":true,"capability":"<cap>","action":"<act>","data":{...}}`
    Denied/Error: `{"ok":false,"error":"capability_not_granted|capability_not_declared|invalid_token|...","message":"..."}`

    ### Available Capabilities & Actions
    - `clipboard`: `read` (`params:{}`) -> `{text}`; `write` (`params:{"text":"..."}`) -> `{written,length}`
    - `selection`: `read` (`params:{}`) -> `{text,sourceApp,bundleIdentifier}` (captures frontmost selection via host Accessibility before overlay steals focus)
    - `audio`: `play` (`params:{"path":"/abs/file.mp3"}`) -> `{playing,mode,path,duration}`; `speak` (`params:{"text":"...","language":"en-US"}`) -> `{playing,mode,length}`; `stop` (`params:{}`) -> `{stopped}`
    - `ocr`: `recognize` (`params:{"imagePath":"/abs/path.png"}`) -> `{text,barcodes}`
    - `everythingSearch`: `search` (`params:{"query":"ext:md","limit":20}`) -> `{indexLoaded,count,hits:[{name,path,relativeParent,isDirectory,sizeBytes}]}`
    - `displayInfo`: `list` (`params:{}`) -> `{displays:[{displayID,name,isMain,currentModeKey,modes:[...]}]}`
    - `systemControl`: `status` -> `{volumePercent,isMuted,caffeineActive,curtainActive}`; `setVolume` (`{"percent":50}`); `setMute` (`{"muted":true|false|"toggle"}`); `setCaffeine` (`{"active":true|false}`)
    - `lumaLinkStatus`: `status` (`params:{}`) -> `{enabled,isListening,port,connectedDeviceCount,pairedDeviceCount,rdpEnabled,rdpRunning,localIPv4}`

    ## Copy-Paste `zsh` Host Bridge Example (`run.sh`)
    ```zsh
    #!/bin/zsh
    set -euo pipefail
    PAYLOAD="$(cat)"
    RESP=$(printf '{"token":"%s","capability":"displayInfo","action":"list","params":{}}\n' "$LUMAKEY_BRIDGE_TOKEN" | /usr/bin/nc -U "$LUMAKEY_BRIDGE_SOCK")
    echo "$RESP" | /usr/bin/python3 -c '
    import json, sys
    r = json.load(sys.stdin)
    if not r.get("ok"):
        print(json.dumps({"title":"需要授权","subtitle":r.get("message",""),"badge":"BRIDGE","items":[{"title":"请在插件中心授权 displayInfo","subtitle":r.get("error","")}]}))
        sys.exit(0)
    ds = r["data"]["displays"]
    print(json.dumps({"title":"显示器速览","badge":"VIEW","metrics":[{"key":"数量","value":str(len(ds))}],
      "items":[{"title":d["name"],"subtitle":d["currentModeKey"],"icon":"display","copyText":d["currentModeKey"]} for d in ds]}))
    '
    ```
    """
}
