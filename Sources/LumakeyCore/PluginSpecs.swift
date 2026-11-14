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
    # Lumakey Plugin Specification (v3)

    Lumakey is a **lightweight macOS productivity hub** — NOT a background application server, gateway, or daemon runner.

    ## Strict Architecture Rules (MUST FOLLOW)
    1. **Zero Resident Daemons**: NEVER write `launchd` plists, infinite `while true` loops, background HTTP servers, or cron schedulers inside a plugin.
    2. **On-Demand Execution Only**: Plugins are spawned when triggered, execute in milliseconds (default 8s timeout), emit stdout, and exit immediately.
    3. **Mandatory Permission Declaration on Registration**: Every plugin MUST explicitly declare `"capabilities"` in `plugin.json` (use `[]` if pure sandboxed needing no host capabilities, or list required values from the enum below). Lumakey aggregates all declared plugin permissions into an app-wide permission audit matrix.
    4. **Host Permission Reuse via Ephemeral Bridge**: NEVER prompt users for separate Accessibility/Screen Recording/FDA permissions or bundle external privileged helpers. Declare `capabilities` in `plugin.json` and call the ephemeral UDS Host Bridge.
    5. **Prefer `view` Mode**: Output structured `PluginViewPayload` JSON so Lumakey renders native Liquid Glass cards.

    ## Directory & `plugin.json` v3 Schema
    Path: `~/Library/Application Support/Lumakey/Plugins/<id>/plugin.json`
    ```json
    {
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
      "config": [
        { "key": "limit", "label": "Max Items", "type": "text", "defaultValue": "10" }
      ]
    }
    ```
    - `id` must match `[a-z0-9-]+` and MUST NOT start with `builtin-` (reserved for in-process native plugins such as `builtin-mos`, `builtin-lumalink`, `builtin-system-pulse`).
    - `entry` must be an executable relative path inside the plugin directory (no `..` traversal).

    ## Capabilities & Ephemeral Host Bridge Protocol
    Declared capabilities default to **DENIED** (least privilege) until explicitly toggled ON by the user in Lumakey Plugin Center (`plugin-state.json` `grantedCapabilities`).
    When `capabilities` is non-empty, Lumakey creates an ephemeral `0600` Unix Domain Socket for the single run and injects:
    - Env vars: `LUMAKEY_BRIDGE_SOCK` and `LUMAKEY_BRIDGE_TOKEN`
    - `stdin` JSON: `{"query":"...","mode":"...","config":{...},"clipboard":"...","bridge":{"socket":"...","token":"...","grantedCapabilities":[...]}}`

    Send one newline-terminated JSON request per UDS connection and read one JSON response line:
    Request: `{"token":"$LUMAKEY_BRIDGE_TOKEN","capability":"<cap>","action":"<act>","params":{...}}`
    Success: `{"ok":true,"capability":"<cap>","action":"<act>","data":{...}}`
    Denied/Error: `{"ok":false,"error":"capability_not_granted|capability_not_declared|invalid_token|...","message":"..."}`

    ### Available Capabilities & Actions
    - `clipboard`: `read` (`params:{}`) -> `{text}`; `write` (`params:{"text":"..."}`) -> `{written,length}`
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
