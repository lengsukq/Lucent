import Foundation

extension HomeLayoutConfig {
    public static let specV1Markdown: String = """
    # Lucent Home Layout & Multi-Profile Specification (v1.0)

    Lucent's Launcher Home Page (`OverlayBentoHomeView`, `880 × 544` constant Liquid Glass frame) is fully declarative, modular, and customizable by both users and AI agents via `lucent-mcp`.

    ## 1. Storage, Live Reload & Backup Integration
    - Persisted atomically at `~/Library/Application Support/Lucent/home-layout.json`.
    - Automatically included in `.lucentbackup` v2 encrypted archives and WebDAV cloud sync (`rawConfigFiles`).
    - When modified via `lucent-mcp`, a zero-polling `DistributedNotificationCenter` signal (`app.lucent.macos.homeLayoutDidChange.distributed`) triggers instant live reload in the running `Lucent.app` process.
    - Every mutating operation snapshots `lastUndoProfile` so changes can be reverted in one call (`undoLastChange: true`).

    ## 2. Multi-Scene Profiles & Built-in Presets
    - Supports up to **8 named profiles** (e.g., `default`, `work`, `personal`), with instant switching via `selectProfileID`.
    - Built-in presets (`applyPreset` or `resetPreset`):
      - `balanced`: 3×2 core Bento tiles + 1-row smart hybrid Omni Dock + Quick Shelf + Utility Strip.
      - `minimal`: Hides Bento & Utility Strip; shows clean 2-row (16-slot) smart hybrid Omni Dock + Quick Shelf.
      - `developer`: Workspace, Capture/Pin, OCR, Network, System Pulse & Reclaim RAM tiles + Dev Plugin & Bookmark shelves.
      - `creatorBookmarks`: 4-column compact Bento tiles + dedicated Pinned Bookmarks & Custom Apps shelves.

    ## 3. Four Modular Sections (`HomeSectionKind`)
    1. `bentoGrid` (`section: "bento"`): Large glass tiles (`bentoColumns`: `2`, `3`, or `4`; max `16` items). Supports `⌘1..⌘9` instant keyboard launch when the search query is empty.
    2. `omniDock` (`section: "dock"`): 8-column icon dock (`dockRows`: `1` = 8 slots, `2` = 16 slots; `dockFillMode`: `"smartHybrid"` fills remaining slots with top-used native apps, or `"manualOnly"`). Accepts ANY launch item type (native apps, custom plugins, bookmarks, folders).
    3. `pillShelves` (`section: "shelf"`, `shelfID`): Up to `6` named horizontal capsule shelves (max `24` items each) for bookmarks, plugin sub-commands, and query triggers.
    4. `utilityStrip` (`section: "utilityChips"` / `"utilityRight"`): Search example chips on the left + quick utility pills on the right (can be hidden cleanly via `hiddenSections: ["utilityStrip"]`).
    - `compactFooterBar` (`Bool`): Hides duplicate quick buttons and redundant maintenance icons in the bottom status bar.

    ## 4. Unified Launch Item Schema (`HomeLaunchItem`)
    Every item across Bento, Dock, Shelves, and Utility Strip shares one unified schema:
    - Optional visual overrides: `id`, `customTitle`, `customSubtitle`, `customIcon` (SF Symbol), `accentColor` (`cyan`, `blue`, `indigo`, `purple`, `mint`, `teal`, `green`, `orange`, `pink`, `red`, `slate`, or `#RRGGBB`), `hotkeyHint`.
    - `kind` (`HomeLaunchTarget`):
      - `"builtin"`: requires `builtinID` in `["files", "clipboard", "screenshotPin", "gifRecord", "ocr", "networkMonitor", "fileWorkspace", "systemPulse", "toggleMos", "pluginsList", "scripts", "snippets", "backupSync", "cacheCleanup", "reclaimMemory", "settingsCenter"]`.
      - `"nativeApp"`: requires absolute `.app` bundle `path` (e.g. `"/Applications/Visual Studio Code.app"`), optional `bundleID`.
      - `"plugin"`: requires `pluginID`, optional `behavior` (`"auto"` | `"scoped"` | `"runInline"` | `"openWindow"`).
      - `"pluginCommand"`: requires `pluginID` and `commandID`, optional `arguments` (`[String]`).
      - `"script"`: requires `scriptID` referencing a Quick Script in `ScriptLibraryStore` (renders its custom SVG icon or SF Symbol automatically).
      - `"bookmark"`: requires `url` with an allowed safe scheme (`http`, `https`, `lucent`, `mailto`, `vscode`, `vscode-insiders`, `cursor`, `zed`, `obsidian`, `notion`, `raycast`, `things`, `bear`, `x-apple.systempreferences`), optional `browserAppPath` (`.app` path) and `sourcePluginID`. Arbitrary shell strings or `javascript:`/`file:` URLs are strictly rejected.
      - `"localPath"`: requires local folder or file `path` (opens folders in Dual-Pane Workspace and Markdown/images/videos in native viewers).
      - `"queryChip"`: requires `query` (`1..160` chars), optional `filter` (`"all"` | `"files"` | `"clipboard"` | `"plugins"`).

    ## 5. Recommended MCP Workflow
    1. Read `lucent://specs/home-layout-v1` and call `lucent_get_home_layout` to inspect active profiles, current items, installed plugins, and indexed bookmarks.
    2. Use `lucent_update_home_layout` to create/switch profiles, apply presets, reorder/hide sections, adjust grid columns/dock rows, or manage shelves.
    3. Use `lucent_upsert_home_item` and `lucent_remove_home_item` to add, update, reorder, or remove individual tiles, dock pins, and bookmarks.
    """
}
