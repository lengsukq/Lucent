import Foundation

extension PluginSystem {
    public static let specStoreV1Markdown: String = """
    # Lucent Plugin & Custom Store Distribution Specification (v1)

    Lucent provides a **single unified Smart URL Bar** (`PluginStoreSniffer`) in the Marketplace. Users paste ANY address (a plugin store, a repository root, a JSON manifest, or a `.zip` archive) and Lucent automatically classifies whether it is a **Multi-Plugin Store Registry** or a **Standalone Single Plugin**.

    ## 1. Smart URL Auto-Detection Priority Rules
    1. **Direct Archive (`.zip` / `.lucentplugin`)**: Identified as a **Single Plugin**. Unpacked inside an isolated `0700` temp directory, validated against Plugin Spec v3, and shown in a permission preview sheet before installing.
    2. **GitHub Repository (`github.com/{owner}/{repo}` or `/tree/{branch}`)**:
       - First probes raw `{branch}/lucent-registry.json` (`main` -> `master`). If found, registers as a **Custom Plugin Store**.
       - Otherwise probes raw `{branch}/plugin.json` + archive (`releases/latest/download/{id}.zip` or `{branch}/dist/{id}.zip`). If found, previews as a **Single Plugin**.
    3. **Direct `.json` Manifest Address**:
       - Top-level `"storeId"` + `"plugins"` array -> **Custom Plugin Store** (`lucent-registry.json`).
       - Top-level `"id"` + `"entry"` -> **Single Plugin** (uses optional `"downloadURL"`, sibling `{id}.zip`, or `dist/{id}.zip`).
    4. **Static Site / Local Directory Base Address**: Probes `{base}/lucent-registry.json`, then `{base}/plugin.json`.
    - **Transport Security**: Remote addresses MUST use `https` (`localhost` / `127.0.0.1` and local `file` paths are allowed for local development). Symlinks and `..` path traversal inside archives are strictly rejected.

    ## 2. Custom Plugin Store Format (`lucent-registry.json`)
    Place `lucent-registry.json` at the root of a repository or static HTTPS directory:
    ```json
    {
      "schemaVersion": 1,
      "storeId": "my-team-store",
      "storeName": "团队效率插件源",
      "description": "团队内部维护的常用效率扩展合集",
      "maintainer": "Your Name",
      "updatedAt": "2026-11-15T12:00:00Z",
      "plugins": [
        {
          "id": "notion-bookmarks",
          "name": "Notion 书签收藏",
          "version": "1.3.0",
          "minAppVersion": "0.8.8",
          "description": "一键收藏剪贴板链接并检索书签",
          "author": "Your Name",
          "icon": "bookmark.fill",
          "accentColor": "teal",
          "categoryTag": "书签",
          "mode": "view",
          "keywords": ["bm", "bookmark"],
          "capabilities": ["clipboard"],
          "resourceScopes": ["network", "filesystem"],
          "downloadURL": "./dist/notion-bookmarks.zip",
          "sha256": "<64-hex-sha256-of-zip>",
          "sizeBytes": 18432
        }
      ]
    }
    ```
    - **Anti-Spoofing Enforcement**: On install, Lucent verifies the downloaded `.zip` matches `sha256`, and checks that the archive's internal `plugin.json` does NOT request any `capabilities` or `resourceScopes` omitted from the store's `lucent-registry.json` entry.
    - **Lossless Updates**: Updating an installed plugin replaces `Plugins/{id}/` while preserving `plugin-state.json` user overrides (`customKeywords`, `customHotKey`, `grantedCapabilities`) and encrypted secrets.

    ## 3. Recommended Packaging Workflow (via `lucent-mcp`)
    Call the MCP tool `lucent_package_plugin_for_store` with `id` and `outputDir` (plus optional `registryPath`, `storeId`, `storeName`, `downloadURL`). It validates the plugin against Spec v3, builds a clean `{id}.zip` (stripping `.DS_Store` & symlinks), computes the exact 64-char `sha256`, and creates or updates `lucent-registry.json` automatically.
    """
}
