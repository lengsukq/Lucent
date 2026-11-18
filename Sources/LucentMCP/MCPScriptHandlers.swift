import Foundation
import LucentCore

extension MCPServer {
    var resolvedScriptStore: ScriptLibraryStore {
        let paths = ScriptLibraryStore.scopedPaths(forPluginsRoot: pluginsDirectory)
        return ScriptLibraryStore(scriptsDirectory: paths.scriptsDir, indexFileURL: paths.indexURL)
    }

    func scriptToolSchemas() -> [[String: Any]] {
        let runtimes = ScriptRuntime.allCases.map(\.rawValue)
        let outputs = ScriptOutputMode.allCases.map(\.rawValue)
        let scopes = PluginResourceScope.allCases.map(\.rawValue)

        return [
            schema(
                "lucent_list_scripts",
                "List Quick Scripts in Lucent's Script Library (`scripts-library.json` + `Scripts/`), including bilingual names, custom SVG icon status, trigger keywords, runtime, output mode, hotkeys, and quick action mounts.",
                [
                    "includeDisabled": ["type": "boolean", "description": "Include disabled scripts (default true)."],
                    "includeCode": ["type": "boolean", "description": "Include full script code and custom SVG markup (default false)."]
                ],
                []
            ),
            schema(
                "lucent_upsert_script",
                "Create or update a Quick Script in Lucent's Script Library, craft its bilingual names (`title` / `englishTitle`), draw a bespoke 64x64 `<svg>` icon (`iconSvg`) or assign an SF Symbol + `accentColor`, and configure runtime (`zsh`, `bash`, `python3`, `appleScript`, `swift`, or `customShebang` for Node/Deno/Ruby), output mode, hotkey, and sandbox scopes.",
                [
                    "id": ["type": "string", "description": "Optional lowercase slug (`[a-z0-9-_]+`). Auto-generated from title/englishTitle if omitted."],
                    "title": ["type": "string", "description": "Primary display name (Chinese or current UI language)."],
                    "englishTitle": ["type": "string", "description": "Optional English display name for live bilingual switching."],
                    "subtitle": ["type": "string", "description": "Short action description shown in Launcher and Home tiles."],
                    "englishSubtitle": ["type": "string", "description": "Optional English subtitle."],
                    "keywords": ["type": "array", "items": ["type": "string"], "description": "Launcher trigger keywords (e.g. `['!json', 'fmt']`)."],
                    "category": ["type": "string", "description": "Category badge (e.g. '开发', '效率', '系统')."],
                    "runtime": ["type": "string", "enum": runtimes, "description": "Interpreter runtime (`zsh`, `bash`, `python3`, `appleScript`, `swift`, `customShebang`)."],
                    "fileExtension": ["type": "string", "description": "Optional file extension (e.g. `mjs`, `ts`, `rb`, `py`, `sh`) especially for `customShebang`."],
                    "code": ["type": "string", "description": "Complete executable script source code (include `#!` shebang on line 1 when `runtime == 'customShebang'`)."],
                    "outputMode": ["type": "string", "enum": outputs, "description": "Post-run behavior (`toast`, `inlinePreview`, `copyToClipboard`, `pasteToFrontApp`, `openReader`)."],
                    "icon": ["type": "string", "description": "SF Symbol name (e.g. `wand.and.stars`, `terminal.fill`) when not using `iconSvg`."],
                    "iconSvg": ["type": "string", "description": "Optional bespoke `<svg viewBox=\"0 0 64 64\" xmlns=\"http://www.w3.org/2000/svg\">...</svg>` markup (<=64KB, no `<script>`/`<foreignObject>`) saved as `Scripts/icons/<id>.svg`."],
                    "clearCustomIconSvg": ["type": "boolean", "description": "If true, remove existing custom SVG icon and revert to SF Symbol `icon`."],
                    "accentColor": ["type": "string", "description": "Palette token (`cyan`, `blue`, `indigo`, `purple`, `mint`, `teal`, `green`, `orange`, `pink`, `red`, `slate`) or `#RRGGBB`."],
                    "hotKey": ["type": "string", "description": "Optional global hotkey chord (e.g. `⌃⌥J`, `⌘⇧K`; pass empty string to clear)."],
                    "pinnedInQuickBar": ["type": "boolean", "description": "Mount in Launcher bottom quick bar (default false)."],
                    "showInMenuBar": ["type": "boolean", "description": "Mount in top macOS menu bar (default false)."],
                    "includeInGlobalSearch": ["type": "boolean", "description": "Include in `⌥Space` global search (default true)."],
                    "allowedScopes": ["type": "array", "items": ["type": "string", "enum": scopes], "description": "Seatbelt resource scopes (`network`, `filesystem`, `subprocess`). Include `subprocess` for Homebrew/Node/Deno/Ruby shebangs."],
                    "passClipboard": ["type": "boolean", "description": "Inject current clipboard text into `LUCENT_CLIPBOARD` (default false)."],
                    "timeoutSeconds": ["type": "number", "description": "Execution timeout in seconds (3..30, default 10)."],
                    "isEnabled": ["type": "boolean", "description": "Enable or disable the script (default true)."]
                ],
                ["title"]
            ),
            schema(
                "lucent_run_script_test",
                "Execute a Quick Script inside Lucent's Seatbelt sandbox with optional `query`, `clipboardText`, and `selectedText` to verify its exitCode, stdout, stderr, and execution time.",
                [
                    "id": ["type": "string", "description": "Script ID to execute."],
                    "query": ["type": "string", "description": "Optional query/argument passed via `$1`, `stdin`, and `LUCENT_QUERY`."],
                    "clipboardText": ["type": "string", "description": "Simulated clipboard text (injected when `passClipboard` is enabled on the script)."],
                    "selectedText": ["type": "string", "description": "Simulated frontmost selected text (`LUCENT_SELECTED_TEXT`)."]
                ],
                ["id"]
            ),
            schema(
                "lucent_remove_script",
                "Delete a Quick Script and its custom SVG icon from Lucent's Script Library.",
                ["id": ["type": "string", "description": "Script ID to remove."]],
                ["id"]
            )
        ]
    }

    func handleListScripts(arguments: [String: Any]) -> [String: Any] {
        let store = resolvedScriptStore
        let includeDisabled = arguments["includeDisabled"] as? Bool ?? true
        let includeCode = arguments["includeCode"] as? Bool ?? false
        let items = store.allScripts(includeDisabled: includeDisabled).map { item -> [String: Any] in
            var dict = serializeScriptRecord(item, store: store)
            if includeCode {
                dict["code"] = store.readCode(for: item)
                dict["iconSvg"] = store.readCustomIconSVG(for: item) ?? NSNull()
            }
            return dict
        }
        return textResult(prettyJSON([
            "scriptsDirectory": store.scriptsDirectory.path,
            "indexPath": store.indexFileURL.path,
            "count": items.count,
            "scripts": items
        ]))
    }

    func handleUpsertScript(arguments: [String: Any]) -> [String: Any] {
        let store = resolvedScriptStore
        let existingList = store.allScripts(includeDisabled: true)
        let rawID = (arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawTitle = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawTitle.isEmpty || !rawID.isEmpty else {
            return textResult("Missing required argument 'title'.", isError: true)
        }
        let seedSlug = !rawID.isEmpty ? rawID : ((arguments["englishTitle"] as? String) ?? rawTitle)
        let resolvedID = ScriptHeaderParser.isSafeScriptID(rawID) ? rawID : ScriptHeaderParser.sanitizeSlug(seedSlug)
        let existing = existingList.first { $0.id == resolvedID }

        let runtime: ScriptRuntime
        if let rtRaw = arguments["runtime"] as? String {
            guard let parsed = ScriptRuntime(rawValue: rtRaw) else {
                return textResult("Unknown runtime '\(rtRaw)'.", isError: true)
            }
            runtime = parsed
        } else {
            runtime = existing?.runtime ?? .zsh
        }

        let outputMode: ScriptOutputMode
        if let outRaw = arguments["outputMode"] as? String {
            guard let parsed = ScriptOutputMode(rawValue: outRaw) else {
                return textResult("Unknown outputMode '\(outRaw)'.", isError: true)
            }
            outputMode = parsed
        } else {
            outputMode = existing?.outputMode ?? .inlinePreview
        }

        var scopes = existing?.allowedScopes ?? (runtime == .customShebang ? [.subprocess] : [])
        if let rawScopes = arguments["allowedScopes"] as? [String] {
            var parsedScopes = Set<PluginResourceScope>()
            for raw in rawScopes {
                guard let sc = PluginResourceScope(rawValue: raw) else {
                    return textResult("Unknown scope '\(raw)'. Expected network, filesystem, or subprocess.", isError: true)
                }
                parsedScopes.insert(sc)
            }
            scopes = parsedScopes
        }

        var resolvedHotKey = existing?.hotKey
        if let hkRaw = arguments["hotKey"] as? String {
            let trimmedHK = hkRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedHK.isEmpty {
                resolvedHotKey = nil
            } else {
                guard let chord = HotKeyChord.parse(trimmedHK), chord.validationError == nil else {
                    return textResult("Invalid hotKey '\(trimmedHK)'. Example valid chord: '⌃⌥J' or '⌘⇧K'.", isError: true)
                }
                resolvedHotKey = chord.displayString
            }
        }

        let ext = (arguments["fileExtension"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredFileName: String = if let ext, !ext.isEmpty {
            "\(resolvedID).\(ext)"
        } else if let existing, existing.runtime == runtime {
            existing.fileName
        } else {
            "\(resolvedID).\(runtime.defaultFileExtension)"
        }

        let resolvedCode = (arguments["code"] as? String)
            ?? existing.map { store.readCode(for: $0) }
            ?? runtime.defaultTemplateCode

        let draft = ScriptRecord(
            id: resolvedID,
            title: rawTitle.isEmpty ? (existing?.title ?? resolvedID) : rawTitle,
            englishTitle: (arguments["englishTitle"] as? String) ?? existing?.englishTitle,
            subtitle: (arguments["subtitle"] as? String) ?? existing?.subtitle ?? "",
            englishSubtitle: (arguments["englishSubtitle"] as? String) ?? existing?.englishSubtitle,
            keywords: (arguments["keywords"] as? [String]) ?? existing?.keywords ?? ["!\(resolvedID)"],
            category: (arguments["category"] as? String) ?? existing?.category ?? "效率",
            fileName: preferredFileName,
            runtime: runtime,
            outputMode: outputMode,
            icon: (arguments["icon"] as? String) ?? existing?.icon ?? "terminal.fill",
            accentColor: (arguments["accentColor"] as? String) ?? existing?.accentColor ?? "teal",
            isEnabled: (arguments["isEnabled"] as? Bool) ?? existing?.isEnabled ?? true,
            includeInGlobalSearch: (arguments["includeInGlobalSearch"] as? Bool) ?? existing?.includeInGlobalSearch ?? true,
            pinnedInQuickBar: (arguments["pinnedInQuickBar"] as? Bool) ?? existing?.pinnedInQuickBar ?? false,
            showInMenuBar: (arguments["showInMenuBar"] as? Bool) ?? existing?.showInMenuBar ?? false,
            hotKey: resolvedHotKey,
            allowedScopes: scopes,
            passClipboard: (arguments["passClipboard"] as? Bool) ?? existing?.passClipboard ?? false,
            timeoutSeconds: (arguments["timeoutSeconds"] as? NSNumber)?.doubleValue ?? existing?.timeoutSeconds ?? 10.0
        )

        do {
            let saved = try store.upsert(
                draft,
                code: resolvedCode,
                iconSvg: arguments["iconSvg"] as? String,
                clearCustomIconSvg: arguments["clearCustomIconSvg"] as? Bool ?? false,
                notifyInProcess: false,
                notifyCrossProcess: true
            )
            return textResult(prettyJSON([
                "upserted": true,
                "script": serializeScriptRecord(saved, store: store)
            ]))
        } catch {
            return textResult("Error: \(error.localizedDescription)", isError: true)
        }
    }

    func handleRunScriptTest(arguments: [String: Any]) -> [String: Any] {
        let store = resolvedScriptStore
        let id = (arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let script = store.allScripts(includeDisabled: true).first(where: { $0.id == id }) else {
            return textResult("Script not found: \(id)", isError: true)
        }
        do {
            let outcome = try ScriptRunner.runSync(
                script,
                query: arguments["query"] as? String ?? "",
                clipboardText: arguments["clipboardText"] as? String ?? "",
                selectedText: arguments["selectedText"] as? String ?? "",
                store: store
            )
            return textResult(prettyJSON([
                "id": script.id,
                "title": script.displayTitle,
                "runtime": script.runtime.rawValue,
                "outputMode": script.outputMode.rawValue,
                "exitCode": outcome.exitCode,
                "durationMs": outcome.durationMs,
                "stdout": outcome.stdout,
                "stderr": outcome.stderr
            ]))
        } catch {
            return textResult("Run error: \(error.localizedDescription)", isError: true)
        }
    }

    func handleRemoveScript(arguments: [String: Any]) -> [String: Any] {
        let store = resolvedScriptStore
        let id = (arguments["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard store.allScripts(includeDisabled: true).contains(where: { $0.id == id }) else {
            return textResult("Script not found: \(id)", isError: true)
        }
        do {
            try store.delete(id: id, notifyInProcess: false, notifyCrossProcess: true)
            return textResult(prettyJSON(["id": id, "removed": true]))
        } catch {
            return textResult("Remove error: \(error.localizedDescription)", isError: true)
        }
    }

    private func serializeScriptRecord(_ item: ScriptRecord, store: ScriptLibraryStore) -> [String: Any] {
        [
            "id": item.id,
            "title": item.title,
            "englishTitle": item.englishTitle ?? NSNull(),
            "subtitle": item.subtitle,
            "englishSubtitle": item.englishSubtitle ?? NSNull(),
            "keywords": item.keywords,
            "category": item.category,
            "fileName": item.fileName,
            "scriptPath": store.scriptURL(for: item).path,
            "runtime": item.runtime.rawValue,
            "outputMode": item.outputMode.rawValue,
            "icon": item.icon,
            "hasCustomSvgIcon": item.customIconURL(in: store.scriptsDirectory) != nil,
            "accentColor": item.accentColor,
            "hotKey": item.hotKey ?? NSNull(),
            "pinnedInQuickBar": item.pinnedInQuickBar,
            "showInMenuBar": item.showInMenuBar,
            "includeInGlobalSearch": item.includeInGlobalSearch,
            "allowedScopes": item.allowedScopes.map(\.rawValue).sorted(),
            "passClipboard": item.passClipboard,
            "timeoutSeconds": item.timeoutSeconds,
            "enabled": item.isEnabled
        ]
    }
}
