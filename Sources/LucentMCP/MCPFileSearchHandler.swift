import Foundation
import LucentCore
import LucentSearch

extension MCPServer {
    func fileSearchToolSchemas() -> [[String: Any]] {
        [
            schema(
                "lucent_search_files",
                "Read-only millisecond file search over Lucent's local verified LCNTIDX3 Everything index snapshot (opt-in: requires 'Allow lucent-mcp read-only file search' enabled in Lucent Settings -> General; respects user excluded paths and runs zero background daemons). Supports Everything DSL: `ext:swift;md`, `folder:`, `file:`, `video:`, `pic:`, `path:substr`, `!exclude`, and `A | B`.",
                [
                    "query": [
                        "type": "string",
                        "description": "Filename keywords or Everything DSL expression (e.g. `ext:swift path:Sources !Tests`)."
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum number of hits to return (1..100, default 25)."
                    ]
                ],
                ["query"]
            )
        ]
    }

    func handleSearchFiles(arguments: [String: Any]) -> [String: Any] {
        let prefsURL = customGeneralPrefsURL ?? GeneralPreferences.defaultConfigURL()
        let prefs = GeneralPreferences.load(from: prefsURL)
        guard prefs.enableMcpFileSearch else {
            return textResult(
                prettyJSON([
                    "ok": false,
                    "error": "mcp_file_search_disabled",
                    "message": "Read-only MCP file search is disabled by default for privacy. Enable Settings -> General -> 'Allow lucent-mcp read-only file search' in Lucent to opt in."
                ]),
                isError: true
            )
        }

        let query = (arguments["query"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return textResult("Missing required non-empty 'query' parameter.", isError: true)
        }
        let limit = min(max(arguments["limit"] as? Int ?? 25, 1), 100)

        guard let index = EverythingSnapshotStore.loadNewestValid(
            cacheDirectory: customIndexCacheDirectory,
            maxAgeSeconds: 7 * 86_400
        ) else {
            return textResult(
                prettyJSON([
                    "ok": false,
                    "error": "index_snapshot_unavailable",
                    "message": "No valid local LCNTIDX3 index snapshot found yet. Open Lucent File Search (⌥F) once to build the snapshot."
                ]),
                isError: true
            )
        }

        let excludedSet = EverythingIndex.normalizedExcludedSet(prefs.excludedIndexPathSet)
        let rawHits = index.search(queryText: query, limit: min(limit * 2, 200))
        let filteredHits = rawHits.filter { hit in
            excludedSet.isEmpty || !EverythingIndex.isPathExcluded(hit.url.standardizedFileURL.path, excludedPaths: excludedSet)
        }.prefix(limit)

        let formatter = ISO8601DateFormatter()
        let items: [[String: Any]] = filteredHits.map { hit in
            [
                "name": hit.name,
                "path": hit.url.path,
                "relativeParent": hit.relativeParentPath,
                "isDirectory": hit.isDirectory,
                "sizeBytes": hit.sizeBytes,
                "mediaKind": hit.mediaKind.rawValue
            ]
        }
        return textResult(prettyJSON([
            "ok": true,
            "query": query,
            "indexedNodes": index.nodes.count,
            "roots": index.rootPaths,
            "snapshotBuiltAt": formatter.string(from: index.builtAt),
            "count": items.count,
            "hits": items
        ]))
    }
}
