import Foundation
import SQLite3

struct ConversationSummaryMeta {
    let title: String
    let projectName: String
    let workspacePath: String
    let isRunning: Bool
    let isIdle: Bool
    let nestingDepth: Int
}

private func extractProjectFromWorkspaceURIs(_ raw: String) -> (name: String, path: String) {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
          let uris = try? JSONDecoder().decode([String].self, from: data) else {
        return ("", "")
    }
    for item in uris {
        let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { continue }
        if let url = URL(string: cleaned), url.isFileURL {
            let path = url.path
            let name = url.lastPathComponent
            if !name.isEmpty && name != "/" {
                return (name, path)
            }
        } else {
            let url = URL(fileURLWithPath: cleaned)
            let name = url.lastPathComponent
            if !name.isEmpty && name != "/" {
                return (name, cleaned)
            }
        }
    }
    return ("", "")
}

private func columnText(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
    guard let cstr = sqlite3_column_text(stmt, idx) else { return "" }
    return String(cString: cstr)
}

private func readSummariesFromDB(path: String, into map: inout [String: ConversationSummaryMeta]) {
    guard FileManager.default.fileExists(atPath: path) else { return }
    var db: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let handle = db else {
        if db != nil { sqlite3_close(db) }
        return
    }
    defer { sqlite3_close(handle) }
    sqlite3_busy_timeout(handle, 80)

    let sql = """
        SELECT conversation_id, title, workspace_uris, status, not_fully_idle, nesting_depth, parent_conversation_id
        FROM conversation_summaries
        """
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let query = stmt else {
        return
    }
    defer { sqlite3_finalize(query) }

    while sqlite3_step(query) == SQLITE_ROW {
        let cid = columnText(query, 0).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { continue }
        let rawTitle = columnText(query, 1).trimmingCharacters(in: .whitespacesAndNewlines)
        let workspaceRaw = columnText(query, 2)
        let statusRaw = columnText(query, 3).uppercased()
        let notFullyIdle = sqlite3_column_int(query, 4) != 0
        let rawDepth = Int(sqlite3_column_int(query, 5))
        let parentId = columnText(query, 6).trimmingCharacters(in: .whitespacesAndNewlines)
        let depth = (rawDepth > 0 || !parentId.isEmpty) ? max(1, rawDepth) : 0

        let project = extractProjectFromWorkspaceURIs(workspaceRaw)
        let running = statusRaw.contains("RUNNING") || notFullyIdle
        let idle = !running && statusRaw.contains("IDLE")

        if map[cid] == nil || (!rawTitle.isEmpty && map[cid]?.title.isEmpty == true) {
            map[cid] = ConversationSummaryMeta(
                title: rawTitle,
                projectName: project.name,
                workspacePath: project.path,
                isRunning: running,
                isIdle: idle,
                nestingDepth: depth
            )
        }
    }
}

func loadConversationSummaries(includeCliLogs: Bool) -> [String: ConversationSummaryMeta] {
    let home = pulseUserHomePath()
    var result: [String: ConversationSummaryMeta] = [:]
    readSummariesFromDB(path: "\(home)/.gemini/antigravity/conversation_summaries.db", into: &result)
    if includeCliLogs {
        readSummariesFromDB(path: "\(home)/.gemini/antigravity-cli/conversation_summaries.db", into: &result)
    }
    return result
}
