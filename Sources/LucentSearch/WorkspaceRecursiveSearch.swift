import Darwin
import Foundation
import LucentFoundation

public enum WorkspaceSearchMatcher {
    private static let skippedFolders: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", ".Spotlight-V100",
        ".Trashes", "$RECYCLE.BIN", "System Volume Information", ".fseventsd",
        ".TemporaryItems", ".venv", "venv", "__pycache__", "Pods", ".gradle", ".cargo"
    ]

    public static func matchesEntry(
        name: String,
        extensionLower: String,
        isDirectory: Bool,
        relativeSubpath: String = "",
        rawQuery: String,
        allowPinyin: Bool = true
    ) -> Bool {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let tokens = EverythingQuery.tokenize(Substring(trimmed))
        guard !tokens.isEmpty else { return true }

        for rawToken in tokens {
            var tok = rawToken
            var negated = false
            if tok.first == "!" && tok.count > 1 {
                negated = true
                tok = tok.dropFirst()
            }
            let lower = tok.lowercased()
            let hit: Bool
            if lower.hasPrefix("ext:") {
                let allowed = Set(
                    lower.dropFirst(4)
                        .split(whereSeparator: { $0 == ";" || $0 == "," })
                        .map { String($0.drop(while: { $0 == "." })) }
                        .filter { !$0.isEmpty }
                )
                hit = !isDirectory && !allowed.isEmpty && allowed.contains(extensionLower)
            } else if lower.first == "." && lower.count > 1 && !lower.dropFirst().contains(".") {
                let ext = String(lower.dropFirst())
                hit = (!isDirectory && extensionLower == ext) || name.localizedStandardContains(lower)
            } else if lower == "video:" {
                hit = !isDirectory && MediaClassifier.videoExtensions.contains(extensionLower)
            } else if lower == "pic:" || lower == "image:" {
                hit = !isDirectory && MediaClassifier.imageExtensions.contains(extensionLower)
            } else if lower == "audio:" {
                hit = !isDirectory && MediaClassifier.audioExtensions.contains(extensionLower)
            } else if lower == "folder:" {
                hit = isDirectory
            } else {
                let needle = QueryNeedle(lower)
                hit = needle.matches(in: name, allowPinyin: allowPinyin)
                    || (!extensionLower.isEmpty && extensionLower.contains(lower))
                    || (!relativeSubpath.isEmpty && needle.matches(in: relativeSubpath, allowPinyin: false))
            }
            if negated ? hit : !hit { return false }
        }
        return true
    }

    public static func searchDirectoryRecursively(
        rootURL: URL,
        queryText: String,
        mediaFilter: WorkspaceMediaFilter = .all,
        includeHidden: Bool = false,
        maxDepth: Int = 7,
        maxVisitedNodes: Int = 50_000,
        limit: Int = 260
    ) -> [FileEntry] {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }

        let rootPath = rootURL.standardizedFileURL.path
        var queue: [(path: String, relPrefix: String, depth: Int)] = [(rootPath, "", 0)]
        var head = 0
        var visited = 0
        var pinyinBudget = 1_600
        var matched: [(entry: FileEntry, rank: Int, depth: Int)] = []
        matched.reserveCapacity(min(limit, 128))
        let primaryNeedle = QueryNeedle(trimmed.split(whereSeparator: \.isWhitespace).first.map { $0.lowercased() } ?? trimmed.lowercased())

        while head < queue.count && visited < maxVisitedNodes {
            if Task.isCancelled { return [] }
            let current = queue[head]
            head += 1

            guard let dir = current.path.withCString({ opendir($0) }) else { continue }
            defer { closedir(dir) }

            while let rawEntry = readdir(dir) {
                if Task.isCancelled { return [] }
                let len = Int(rawEntry.pointee.d_namlen) + 1
                let name: String = withUnsafePointer(to: rawEntry.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: len) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                let isHidden = name.hasPrefix(".")
                if !includeHidden && isHidden { continue }

                visited += 1
                if visited > maxVisitedNodes { break }

                let childPath = current.path == "/" ? "/\(name)" : "\(current.path)/\(name)"
                let rawIsDir: Bool
                switch Int32(rawEntry.pointee.d_type) {
                case DT_DIR:
                    rawIsDir = true
                case DT_UNKNOWN:
                    var st = stat()
                    rawIsDir = childPath.withCString { lstat($0, &st) == 0 } && ((st.st_mode & S_IFMT) == S_IFDIR)
                default:
                    rawIsDir = false
                }

                let isPackage = rawIsDir && EverythingIndex.hasPackageSuffix(name)
                let isDirectory = rawIsDir && !isPackage

                if isDirectory && current.depth < maxDepth {
                    let shouldSkipSubtree = !includeHidden && (skippedFolders.contains(name) || (current.depth == 0 && name == "Library"))
                    if !shouldSkipSubtree {
                        let nextRel = current.relPrefix.isEmpty ? name : "\(current.relPrefix)/\(name)"
                        queue.append((childPath, nextRel, current.depth + 1))
                    }
                }

                // Depth 0 items are already in PaneState.entries; still include or deduplicate cleanly upstream.
                let extLower = EverythingIndex.extractExtensionLower(fromName: name)
                let mediaKind = MediaClassifier.classifyExtension(extLower, isDirectory: isDirectory)
                let candidateStub = FileEntry(
                    url: URL(fileURLWithPath: childPath, isDirectory: rawIsDir),
                    name: name,
                    isDirectory: rawIsDir,
                    isPackage: isPackage,
                    isHidden: isHidden,
                    sizeBytes: 0,
                    modifiedAt: .distantPast,
                    extensionLowercased: extLower,
                    mediaKind: mediaKind
                )
                guard mediaFilter.matches(candidateStub) else { continue }

                let canPinyin: Bool
                if pinyinBudget > 0 && PinyinHelper.containsCJK(name) {
                    pinyinBudget -= 1
                    canPinyin = true
                } else {
                    canPinyin = false
                }

                guard matchesEntry(
                    name: name,
                    extensionLower: extLower,
                    isDirectory: isDirectory,
                    relativeSubpath: current.relPrefix,
                    rawQuery: trimmed,
                    allowPinyin: canPinyin
                ) else { continue }

                var st = stat()
                let hasStat = childPath.withCString { stat($0, &st) == 0 }
                let sizeBytes: Int64 = (!hasStat || isDirectory) ? 0 : Int64(st.st_size)
                let modDate = hasStat ? Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec)) : .distantPast
                let crtDate = hasStat ? Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec)) : modDate

                let entry = FileEntry(
                    url: URL(fileURLWithPath: childPath, isDirectory: rawIsDir),
                    name: name,
                    isDirectory: rawIsDir,
                    isPackage: isPackage,
                    isHidden: isHidden,
                    sizeBytes: sizeBytes,
                    modifiedAt: modDate,
                    createdAt: crtDate,
                    extensionLowercased: extLower,
                    mediaKind: mediaKind
                )
                let rank = max(1, primaryNeedle.matchRank(in: name, allowPinyin: canPinyin))
                matched.append((entry, rank, current.depth))
                if matched.count >= limit * 2 { break }
            }
        }

        matched.sort { lhs, rhs in
            if lhs.depth == 0 && rhs.depth > 0 { return true }
            if rhs.depth == 0 && lhs.depth > 0 { return false }
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
        }
        return Array(matched.prefix(limit).map(\.entry))
    }
}
