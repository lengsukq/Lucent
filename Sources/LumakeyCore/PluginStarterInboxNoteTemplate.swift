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
                placeholder: "~/Documents/Lumakey-Notes.md", section: "存储与标签"
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
        exec /usr/bin/python3 - "$@" <<'PY'
        import datetime as dt, hashlib, json, os, re, sys, urllib.parse
        from pathlib import Path

        LINE_RE = re.compile(r"^- \[(?P<done>[ xX])\] (?P<pin>⭐ )?\[(?P<ts>[^\]]+)\] (?P<body>.*?)(?:\s*<!--\s*id:(?P<id>[a-f0-9]+)\s*-->)?$")

        def parse_notes(md_path: Path):
            if not md_path.exists():
                return ["# Lumakey Quick Capture Inbox", ""], []
            header, notes = [], []
            for raw_line in md_path.read_text(encoding="utf-8", errors="replace").splitlines():
                m = LINE_RE.match(raw_line.strip())
                if m:
                    body = m.group("body").strip()
                    ts = m.group("ts").strip()
                    nid = m.group("id") or hashlib.sha1(f"{ts}:{body}".encode("utf-8")).hexdigest()[:8]
                    notes.append({
                        "id": nid,
                        "done": m.group("done").lower() == "x",
                        "pinned": bool(m.group("pin")),
                        "ts": ts,
                        "body": body
                    })
                elif not notes:
                    header.append(raw_line)
            if not header:
                header = ["# Lumakey Quick Capture Inbox", ""]
            return header, notes

        def save_notes(md_path: Path, header, notes, data_dir: str):
            md_path.parent.mkdir(parents=True, exist_ok=True)
            lines = list(header)
            if lines and lines[-1].strip() != "":
                lines.append("")
            for n in notes:
                mark = "x" if n["done"] else " "
                pin = "⭐ " if n["pinned"] else ""
                lines.append(f"- [{mark}] {pin}[{n['ts']}] {n['body']} <!-- id:{n['id']} -->")
            md_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

            if data_dir:
                try:
                    dd = Path(data_dir)
                    dd.mkdir(parents=True, exist_ok=True)
                    reader_url = "lumakey://reader?path=" + urllib.parse.quote(str(md_path), safe="/")
                    idx_items = [{
                        "id": n["id"],
                        "title": ("⭐ " if n["pinned"] else "") + n["body"],
                        "subtitle": f"{n['ts']} · {'已完成' if n['done'] else '待办速记'}",
                        "keywords": re.findall(r"#([\w\u4e00-\u9fff-]+)", n["body"]),
                        "icon": "checkmark.circle.fill" if n["done"] else ("pin.fill" if n["pinned"] else "note.text"),
                        "url": reader_url,
                        "copyText": n["body"],
                        "pinned": n["pinned"],
                        "priority": 60 if n["pinned"] else 15
                    } for n in notes[:60]]
                    (dd / "search-index.json").write_text(json.dumps({"items": idx_items}, ensure_ascii=False), encoding="utf-8")
                    (dd / "status.json").write_text(json.dumps({"summary": f"{len(notes)} notes", "badge": f"{len(notes)}"}, ensure_ascii=False), encoding="utf-8")
                except OSError:
                    pass

        raw = sys.stdin.read()
        payload = json.loads(raw) if raw.strip().startswith("{") else {}
        cfg = payload.get("config") or {}
        query = str(payload.get("query") or "").strip()
        ctx = payload.get("context") if isinstance(payload.get("context"), dict) else {}
        ctx_text = str(ctx.get("url") or ctx.get("text") or "").strip()
        locale = str(payload.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
        is_en = locale.lower().startswith("en")
        data_dir = str(payload.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")

        raw_path = str(cfg.get("notesPath") or "~/Documents/Lumakey-Notes.md")
        md_path = Path(os.path.expanduser(raw_path)).resolve()
        def_tag = str(cfg.get("defaultTag") or "#idea").strip()
        if def_tag and not def_tag.startswith("#"):
            def_tag = "#" + def_tag
        try:
            max_items = int(cfg.get("maxShownNotes") or 15)
        except ValueError:
            max_items = 15

        args = sys.argv[1:]
        header, notes = parse_notes(md_path)
        toast = None
        open_reader = False

        if "--open-reader" in args:
            if not md_path.exists():
                save_notes(md_path, header, notes, data_dir)
            open_reader = True
        elif len(args) >= 2 and args[0] == "--pin":
            for n in notes:
                if n["id"] == args[1]:
                    n["pinned"] = not n["pinned"]
                    toast = "Updated pin state" if is_en else ("已置顶该条速记" if n["pinned"] else "已取消置顶")
            save_notes(md_path, header, notes, data_dir)
        elif len(args) >= 2 and args[0] == "--done":
            for n in notes:
                if n["id"] == args[1]:
                    n["done"] = not n["done"]
                    toast = "Toggled completion" if is_en else ("已标记完成" if n["done"] else "已恢复为未完成")
            save_notes(md_path, header, notes, data_dir)
        elif len(args) >= 2 and args[0] == "--delete":
            before = len(notes)
            notes = [n for n in notes if n["id"] != args[1]]
            if len(notes) != before:
                toast = "Deleted note" if is_en else "已删除该条速记"
                save_notes(md_path, header, notes, data_dir)
        elif "--browse" not in args:
            capture_body = ""
            if query.startswith("+"):
                capture_body = query[1:].strip()
            elif ctx_text and not query:
                capture_body = ctx_text
            elif query and not query.startswith("?") and not query.startswith("#"):
                capture_body = query
            if capture_body:
                clean = " ".join(capture_body.splitlines()).strip()
                if def_tag and "#" not in clean:
                    clean = f"{def_tag} {clean}"
                ts = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
                nid = hashlib.sha1(f"{ts}:{clean}:{len(notes)}".encode("utf-8")).hexdigest()[:8]
                notes.insert(0, {"id": nid, "done": False, "pinned": False, "ts": ts, "body": clean})
                save_notes(md_path, header, notes, data_dir)
                toast = "Saved to Markdown Inbox" if is_en else "已写入灵感收件箱并同步免前缀索引"
                query = ""

        filter_q = query.lstrip("?").strip().lower() if ("--browse" in args or query.startswith("?") or query.startswith("#")) else ""
        ordered = sorted(notes, key=lambda x: (0 if x["pinned"] else 1, 1 if x["done"] else 0))
        if filter_q:
            ordered = [n for n in ordered if filter_q in n["body"].lower() or filter_q in n["ts"].lower()]

        reader_link = "lumakey://reader?path=" + urllib.parse.quote(str(md_path), safe="/")
        items = [{
            "id": "open-inbox-file",
            "title": "Open Full Markdown Inbox in Reader" if is_en else "在原生 Markdown 阅读窗打开完整收件箱",
            "subtitle": str(md_path),
            "icon": "book.pages",
            "badge": "READER",
            "openURL": reader_link
        }]

        for n in ordered[:max_items]:
            nid = n["id"]
            prefix = "⭐ " if n["pinned"] else ""
            items.append({
                "id": f"note-{nid}",
                "title": f"{prefix}{n['body']}",
                "subtitle": f"{n['ts']} · {'Done' if n['done'] else 'Inbox'}" if is_en else f"{n['ts']} · {'已完成' if n['done'] else '收件箱'}",
                "icon": "checkmark.circle.fill" if n["done"] else ("pin.circle.fill" if n["pinned"] else "note.text"),
                "badge": "DONE" if n["done"] else ("PIN" if n["pinned"] else "NOTE"),
                "copyText": n["body"],
                "actions": [
                    {"id": f"done-{nid}", "label": ("Undo" if n["done"] else "Done") if is_en else ("取消完成" if n["done"] else "完成"), "commandArgs": ["--done", nid]},
                    {"id": f"pin-{nid}", "label": ("Unpin" if n["pinned"] else "Pin") if is_en else ("取消置顶" if n["pinned"] else "置顶"), "commandArgs": ["--pin", nid]},
                    {
                        "id": f"del-{nid}",
                        "label": "Delete" if is_en else "删除",
                        "style": "destructive",
                        "commandArgs": ["--delete", nid],
                        "confirmMessage": "Delete this note from your Markdown inbox?" if is_en else "确认从 Markdown 收件箱中删除这条速记吗？"
                    }
                ]
            })

        pinned_cnt = sum(1 for n in notes if n["pinned"])
        open_cnt = sum(1 for n in notes if not n["done"])
        tags_all = {t for n in notes for t in re.findall(r"#[\w\u4e00-\u9fff-]+", n["body"])}
        effect = {"reloadSearchIndex": True, "statusSummary": f"{len(notes)} notes", "statusBadge": str(len(notes))}
        if toast:
            effect["toast"] = toast
        if open_reader:
            effect["openReaderPath"] = str(md_path)

        print(json.dumps({
            "schemaVersion": 2,
            "title": "Quick Capture & Markdown Inbox" if is_en else "灵感速记与 Markdown 收件箱",
            "subtitle": (
                f"Direct input appends note · Prefix '?' or '#tag' filters ({len(ordered)}/{len(notes)})"
                if is_en else f"直接输入即追加速记 · 以 ? 或 #标签 开头可检索筛选（{len(ordered)}/{len(notes)} 条）"
            ),
            "badge": f"{len(notes)} NOTES",
            "effect": effect,
            "metrics": [
                {"key": "Total" if is_en else "累计速记", "value": str(len(notes))},
                {"key": "Open" if is_en else "待处理", "value": str(open_cnt)},
                {"key": "Pinned" if is_en else "置顶星标", "value": str(pinned_cnt)},
                {"key": "Tags" if is_en else "活跃标签", "value": str(len(tags_all))}
            ],
            "items": items
        }, ensure_ascii=False))
        PY
        """#
    )
}
