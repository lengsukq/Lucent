import LucentFoundation
import Foundation

extension ScriptLibraryStore {
    public func match(query: String, requireGlobalSearch: Bool = true, allowEmptyQuery: Bool = false) -> [ScriptMatch] {
        Self.match(scripts: allScripts(includeDisabled: false), query: query, requireGlobalSearch: requireGlobalSearch, allowEmptyQuery: allowEmptyQuery)
    }

    public static func match(
        scripts: [ScriptRecord],
        query: String,
        requireGlobalSearch: Bool = true,
        allowEmptyQuery: Bool = false
    ) -> [ScriptMatch] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let needle = trimmed.lowercased()
        let pool = scripts.filter { $0.isEnabled && (!requireGlobalSearch || $0.includeInGlobalSearch) }
        if needle.isEmpty {
            guard allowEmptyQuery else { return [] }
            return pool.enumerated().map { idx, item in
                ScriptMatch(script: item, trailingQuery: "", score: 6_150 - idx)
            }
        }

        var hits: [ScriptMatch] = []
        for item in pool {
            var bestScore = 0
            var trailing = ""
            for kw in item.keywords {
                let kwLo = kw.lowercased()
                if kwLo == needle {
                    bestScore = max(bestScore, 9_720)
                } else if needle.hasPrefix(kwLo + " ") {
                    bestScore = max(bestScore, 9_700)
                    trailing = String(trimmed.dropFirst(kw.count + 1)).trimmingCharacters(in: .whitespaces)
                } else if kwLo.hasPrefix(needle) {
                    bestScore = max(bestScore, 9_250)
                }
            }
            if bestScore == 0 {
                let titleLo = item.title.lowercased()
                let enLo = (item.englishTitle ?? "").lowercased()
                let (pyFull, pyInit) = PinyinHelper.convert(item.title)
                if titleLo == needle || (!enLo.isEmpty && enLo == needle) {
                    bestScore = 9_150
                } else if titleLo.hasPrefix(needle) || (!enLo.isEmpty && enLo.hasPrefix(needle)) || pyInit.hasPrefix(needle) {
                    bestScore = 8_550
                } else if pyFull.hasPrefix(needle) || titleLo.contains(needle) || (!enLo.isEmpty && enLo.contains(needle))
                    || item.subtitle.lowercased().contains(needle) || item.category.lowercased().contains(needle) {
                    bestScore = 7_650
                }
            }
            if bestScore > 0 {
                hits.append(ScriptMatch(script: item, trailingQuery: trailing, score: bestScore))
            }
        }
        return hits.sorted { $0.score != $1.score ? $0.score > $1.score : $0.script.id < $1.script.id }
    }

    static func resolveSafeFileName(preferred: String, id: String, runtime: ScriptRuntime) -> String {
        let trimmed = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        let ext = URL(fileURLWithPath: trimmed).pathExtension
        let safeExt = ext.filter { $0.isLetter || $0.isNumber }.lowercased()
        let finalExt = safeExt.isEmpty ? runtime.defaultFileExtension : safeExt
        return "\(id).\(finalExt)"
    }

    func syncWithDiskUnlocked() -> [ScriptRecord] {
        let fm = FileManager.default
        let legacyStrayDir = scriptsDirectory.appendingPathComponent(".lucent-plugin-data", isDirectory: true)
        if fm.fileExists(atPath: legacyStrayDir.path) {
            try? fm.removeItem(at: legacyStrayDir)
        }

        var index = loadIndexUnlocked()
        if !index.seededDefaults && index.scripts.isEmpty {
            let existingFiles = (try? fm.contentsOfDirectory(atPath: scriptsDirectory.path)) ?? []
            let hasUserScripts = existingFiles.contains { !$0.hasPrefix(".") && $0 != "icons" }
            if !hasUserScripts {
                index = bootstrapDefaultsUnlocked()
                return index.scripts
            }
            index.seededDefaults = true
        }

        try? fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        let entries = (try? fm.contentsOfDirectory(
            at: scriptsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var diskFiles: [String: URL] = [:]
        for url in entries {
            let name = url.lastPathComponent
            if name == "icons" || name.hasPrefix(".") { continue }
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  vals.isRegularFile == true, vals.isSymbolicLink != true else { continue }
            let ext = url.pathExtension.lowercased()
            let firstLine = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").components(separatedBy: .newlines).first ?? ""
            guard ScriptHeaderParser.recognizedExtensions.contains(ext) || firstLine.hasPrefix("#!") else { continue }
            diskFiles[name] = url
        }

        var mutated = false
        let beforeCount = index.scripts.count
        index.scripts.removeAll { diskFiles[$0.fileName] == nil }
        if index.scripts.count != beforeCount { mutated = true }

        var knownFiles = Set(index.scripts.map(\.fileName))
        for idx in index.scripts.indices {
            guard let url = diskFiles[index.scripts[idx].fileName],
                  let code = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let diskHash = ScriptHeaderParser.contentSHA256(code)
            guard diskHash != index.scripts[idx].lastSyncedHash else { continue }

            let parsed = ScriptHeaderParser.parse(code: code, fileExtension: url.pathExtension)
            var updated = index.scripts[idx]
            if let t = parsed.title, t != updated.title { updated.title = t }
            if let en = parsed.englishTitle, en != updated.englishTitle { updated.englishTitle = en }
            if let sub = parsed.subtitle, sub != updated.subtitle { updated.subtitle = sub }
            if let enSub = parsed.englishSubtitle, enSub != updated.englishSubtitle { updated.englishSubtitle = enSub }
            if let kws = parsed.keywords, kws != updated.keywords { updated.keywords = kws }
            if let cat = parsed.category, cat != updated.category { updated.category = cat }
            if let out = parsed.outputMode, out != updated.outputMode { updated.outputMode = out }
            if let ic = parsed.icon, ic != updated.icon { updated.icon = ic }
            if let col = parsed.accentColor, col != updated.accentColor { updated.accentColor = col }
            if let sc = parsed.scopes, sc != updated.allowedScopes { updated.allowedScopes = sc }
            if let pc = parsed.passClipboard, pc != updated.passClipboard { updated.passClipboard = pc }
            if parsed.runtime != updated.runtime { updated.runtime = parsed.runtime }
            updated.lastSyncedHash = diskHash
            if updated != index.scripts[idx] {
                index.scripts[idx] = updated
                mutated = true
            }
        }

        for (fileName, url) in diskFiles.sorted(by: { $0.key < $1.key }) where !knownFiles.contains(fileName) {
            guard let code = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let baseStem = url.deletingPathExtension().lastPathComponent
            let parsed = ScriptHeaderParser.parse(code: code, fileExtension: url.pathExtension)
            var candidateID = parsed.id ?? ScriptHeaderParser.sanitizeSlug(baseStem)
            if index.scripts.contains(where: { $0.id == candidateID }) {
                candidateID = "\(candidateID)-\(UUID().uuidString.prefix(4).lowercased())"
            }
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            let defaultScopes: Set<PluginResourceScope> = parsed.runtime == .customShebang ? [.subprocess] : []
            let created = ScriptRecord(
                id: candidateID,
                title: parsed.title ?? baseStem,
                englishTitle: parsed.englishTitle,
                subtitle: parsed.subtitle ?? L10n.pick("从 Scripts 目录自动同步", "Synced from Scripts folder"),
                englishSubtitle: parsed.englishSubtitle,
                keywords: parsed.keywords ?? ["!\(candidateID)"],
                category: parsed.category ?? "脚本",
                fileName: fileName,
                runtime: parsed.runtime,
                outputMode: parsed.outputMode ?? .inlinePreview,
                icon: parsed.icon ?? "terminal.fill",
                accentColor: parsed.accentColor ?? "teal",
                allowedScopes: parsed.scopes ?? defaultScopes,
                passClipboard: parsed.passClipboard ?? false,
                lastSyncedHash: ScriptHeaderParser.contentSHA256(code)
            )
            index.scripts.append(created)
            knownFiles.insert(fileName)
            mutated = true
        }

        if mutated { try? saveIndexUnlocked(index) }
        return index.scripts
    }

    func bootstrapDefaultsUnlocked() -> ScriptLibraryIndex {
        let fm = FileManager.default
        try? fm.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        var records: [ScriptRecord] = []
        for (tpl, code, svg) in Self.starterTemplates() {
            let url = scriptsDirectory.appendingPathComponent(tpl.fileName)
            try? Data(code.utf8).write(to: url, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            var rec = tpl
            rec.lastSyncedHash = ScriptHeaderParser.contentSHA256(code)
            if let svg {
                let iconsDir = scriptsDirectory.appendingPathComponent("icons", isDirectory: true)
                try? fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)
                try? Data(svg.utf8).write(to: iconsDir.appendingPathComponent("\(tpl.id).svg"), options: .atomic)
                rec.icon = "icons/\(tpl.id).svg"
            }
            records.append(rec)
        }
        let index = ScriptLibraryIndex(schemaVersion: 1, seededDefaults: true, scripts: records)
        try? saveIndexUnlocked(index)
        return index
    }
}
