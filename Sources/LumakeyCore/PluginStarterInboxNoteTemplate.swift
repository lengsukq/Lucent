import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginStarterGallery {
    static let inboxNoteStarterTemplate = PluginStarterTemplate(
        id: "shell-note",
        name: "灵感速记与 Markdown 收件箱",
        subtitle: "结构化速记 · #标签检索 · 待办勾选/置顶/删除 · 免前缀索引同步",
        description: "支持从搜索框、剪贴板链接或 OCR 选区极速追加带时间戳的 Markdown 速记，内置 #标签过滤、置顶、完成勾选、二次确认删除及一键唤起原生阅读窗。",
        mode: .view,
        icon: "note.text.badge.plus",
        accentColor: "teal",
        categoryTag: "速记收件箱",
        keywords: ["note", "memo", "inbox", "速记", "灵感", "笔记"],
        config: [
            PluginConfigField(
                key: "notesPath", label: "Markdown 收件箱文件路径", type: .path,
                defaultValue: "~/Documents/Lumakey-Notes.md",
                placeholder: "~/Documents/Lumakey-Notes.md", section: "存储与标签",
                includeInBackup: true
            ),
            PluginConfigField(
                key: "defaultTag", label: "未带标签时的默认分类标签", type: .text,
                defaultValue: "#idea", placeholder: "#idea", section: "存储与标签"
            ),
            PluginConfigField(
                key: "maxShownNotes", label: "卡片最多展示记录条数", type: .select,
                defaultValue: "15", options: ["10", "15", "25", "40"], section: "存储与标签"
            )
        ],
        capabilities: [],
        resourceScopes: [.filesystem],
        accepts: [.text, .url],
        commands: [
            PluginCommandSpec(
                id: "recent-notes", title: "浏览与检索灵感收件箱",
                subtitle: "打开结构化速记卡片，支持按关键词/#标签筛选、置顶、勾选完成或阅读窗全文预览",
                keywords: ["notetail", "最近笔记", "收件箱", "notes"], icon: "tray.full.fill",
                arguments: ["--browse"], passQuery: true
            ),
            PluginCommandSpec(
                id: "open-notes-reader", title: "在独立阅读窗打开灵感笔记全文",
                subtitle: "直接唤起 Lumakey 原生 Markdown 阅读器查看完整收件箱文档",
                keywords: ["readnotes", "打开笔记"], icon: "book.pages.fill",
                arguments: ["--open-reader"], passQuery: false
            )
        ],
        locales: [
            "en": PluginLocaleStrings(
                name: "Quick Capture & Markdown Inbox",
                description: "Capture timestamped thoughts, URLs & OCR text into a local Markdown inbox with #tag filtering, pinning, check-off, zero-prefix search index & native Reader view.",
                categoryTag: "Notes",
                commands: [
                    "recent-notes": PluginCommandLocaleStrings(title: "Browse & Search Markdown Inbox", subtitle: "Filter notes by #tag, pin, toggle done, or delete with confirmation"),
                    "open-notes-reader": PluginCommandLocaleStrings(title: "Open Full Inbox in Markdown Reader", subtitle: "Launch Lumakey native Markdown reader for your inbox file")
                ]
            )
        ],
        scriptBody: #"""
        #!/bin/zsh
        set -euo pipefail
        PAYLOAD="$(cat || true)"
        Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
        RAW_PATH="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.notesPath raw -o - - 2>/dev/null || echo '~/Documents/Lumakey-Notes.md')"
        TAG="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract config.defaultTag raw -o - - 2>/dev/null || echo '#idea')"
        DATA_DIR="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract dataDir raw -o - - 2>/dev/null || echo "${LUMAKEY_DATA_DIR:-}")"
        MD_PATH="${RAW_PATH/#\~/$HOME}"
        mkdir -p "$(dirname "$MD_PATH")"
        if [[ -n "$Q" && "${1:-}" != "--browse" ]]; then
          TS="$(/bin/date '+%Y-%m-%d %H:%M')"
          BODY="$Q"
          [[ "$BODY" != *"#"* && -n "$TAG" ]] && BODY="$TAG $BODY"
          printf -- '- [ ] [%s] %s <!-- id:note1 -->\n' "$TS" "$BODY" >> "$MD_PATH"
          if [[ -n "$DATA_DIR" ]]; then
            mkdir -p "$DATA_DIR"
            BODY_SAFE="${BODY//\"/\\\"}"
            printf '{"items":[{"id":"note1","title":"%s","subtitle":"%s","icon":"note.text","copyText":"%s"}]}\n' "$BODY_SAFE" "$TS" "$BODY_SAFE" > "$DATA_DIR/search-index.json"
          fi
        fi
        cat <<EOF
        {"schemaVersion":2,"title":"灵感速记与 Markdown 收件箱","subtitle":"${MD_PATH}","badge":"NOTES","metrics":[{"key":"存储路径","value":"${MD_PATH}"}],"items":[{"id":"open-inbox","title":"打开灵感收件箱","subtitle":"${MD_PATH}","icon":"book.pages","badge":"READER","copyText":"${MD_PATH}"}]}
        EOF
        """#
    )
}
