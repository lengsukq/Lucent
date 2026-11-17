#!/usr/bin/env python3
"""Lumakey Official Store Plugin: Translate Hub (View Card, Host Bridge & Vocabulary)."""

from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import os
import socket
import sys
from pathlib import Path
from typing import Any

from translators import detect_language, parse_target_override, run_parallel_translation

TTS_VOICES = {
    "zh-Hans": "zh-CN",
    "en": "en-US",
    "ja": "ja-JP",
    "ko": "ko-KR",
    "fr": "fr-FR",
    "de": "de-DE",
    "es": "es-ES",
}

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".heic", ".tiff", ".bmp"}


def call_host_bridge(sock_path: str, token: str, capability: str, action: str, params: dict[str, Any]) -> dict[str, Any]:
    if not sock_path or not token:
        return {"ok": False, "error": "bridge_unavailable", "message": "Host Bridge socket not injected"}
    req = json.dumps({"token": token, "capability": capability, "action": action, "params": params}, ensure_ascii=False) + "\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
            client.settimeout(4.0)
            client.connect(sock_path)
            client.sendall(req.encode("utf-8"))
            chunks: list[bytes] = []
            while True:
                buf = client.recv(16384)
                if not buf:
                    break
                chunks.append(buf)
                if b"\n" in buf:
                    break
        raw = b"".join(chunks).decode("utf-8", errors="replace").strip()
        return json.loads(raw) if raw else {"ok": False, "message": "Empty Host Bridge response"}
    except Exception as exc:  # noqa: BLE001
        return {"ok": False, "error": "socket_error", "message": str(exc)}


def make_entry_id(source_text: str, target_lang: str) -> str:
    return hashlib.sha1(f"{target_lang}:{source_text.strip()}".encode("utf-8")).hexdigest()[:10]


def load_json_list(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception:  # noqa: BLE001
        return []


def save_store_and_sync_index(data_dir: str, vocab: list[dict[str, Any]], history: list[dict[str, Any]]) -> None:
    if not data_dir:
        return
    dd = Path(data_dir)
    dd.mkdir(parents=True, exist_ok=True)
    (dd / "vocab.json").write_text(json.dumps(vocab[:300], ensure_ascii=False, indent=2), encoding="utf-8")
    (dd / "history.json").write_text(json.dumps(history[:80], ensure_ascii=False, indent=2), encoding="utf-8")

    idx_items = []
    for v in vocab[:120]:
        vid = str(v.get("id") or "")
        src_txt = str(v.get("source") or "")
        dst_txt = str(v.get("translation") or "")
        note = str(v.get("phonetic") or "")
        idx_items.append(
            {
                "id": f"vocab-{vid}",
                "title": f"📖 {src_txt} → {dst_txt}",
                "subtitle": note or f"Vocabulary · {v.get('savedAt', '')}",
                "keywords": [src_txt.lower(), "vocab", "生词"],
                "icon": "character.book.closed.fill",
                "copyText": dst_txt,
                "commandArgs": ["--vocab", src_txt],
                "pinned": True,
                "priority": 45,
            }
        )
    (dd / "search-index.json").write_text(json.dumps({"items": idx_items}, ensure_ascii=False), encoding="utf-8")
    (dd / "status.json").write_text(
        json.dumps({"summary": f"{len(vocab)} saved · {len(history)} history", "badge": f"{len(vocab)} WORDS"}, ensure_ascii=False),
        encoding="utf-8",
    )


def export_vocab_files(vocab: list[dict[str, Any]], export_dir_raw: str) -> tuple[Path, Path]:
    out_dir = Path(os.path.expanduser(export_dir_raw or "~/Downloads")).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    anki_path = out_dir / "Lumakey-Vocab-Anki.tsv"
    csv_path = out_dir / "Lumakey-Vocab.csv"

    tsv_lines = ["#separator:tab", "#html:false", "#tags column:4"]
    for item in vocab:
        front = str(item.get("source") or "").replace("\t", " ").replace("\n", " ")
        back = str(item.get("translation") or "").replace("\t", " ").replace("\n", " / ")
        notes = str(item.get("phonetic") or "").replace("\t", " ").replace("\n", " ")
        lang_tag = f"lumakey::{item.get('targetLang', 'vocab')}"
        tsv_lines.append(f"{front}\t{back}\t{notes}\t{lang_tag}")
    anki_path.write_text("\n".join(tsv_lines) + "\n", encoding="utf-8")

    with csv_path.open("w", encoding="utf-8-sig", newline="") as fp:
        writer = csv.writer(fp)
        writer.writerow(["Source", "Translation", "Dictionary/Notes", "TargetLang", "SavedAt"])
        for item in vocab:
            writer.writerow([
                item.get("source", ""),
                item.get("translation", ""),
                item.get("phonetic", ""),
                item.get("targetLang", ""),
                item.get("savedAt", ""),
            ])
    return anki_path, csv_path


def resolve_input_text(
    argv: list[str], query: str, ctx: dict[str, Any], sock_path: str, token: str
) -> tuple[str, str]:
    flag = argv[0] if argv else ""
    if flag == "--selection":
        sel = call_host_bridge(sock_path, token, "selection", "read", {})
        if sel.get("ok") and str((sel.get("data") or {}).get("text") or "").strip():
            d = sel["data"]
            return str(d["text"]).strip(), str(d.get("sourceApp") or "Selection")
        clip = call_host_bridge(sock_path, token, "clipboard", "read", {})
        if clip.get("ok") and str((clip.get("data") or {}).get("text") or "").strip():
            return str(clip["data"]["text"]).strip(), "Clipboard Fallback"
        return "", "Selection"

    if flag == "--clipboard":
        clip = call_host_bridge(sock_path, token, "clipboard", "read", {})
        if clip.get("ok"):
            return str((clip.get("data") or {}).get("text") or "").strip(), "Clipboard"
        return "", "Clipboard"

    img_path = str(ctx.get("imagePath") or "")
    if not img_path and ctx.get("path"):
        cand = str(ctx["path"])
        if Path(cand).suffix.lower() in IMAGE_EXTS:
            img_path = cand
    if img_path:
        ocr = call_host_bridge(sock_path, token, "ocr", "recognize", {"imagePath": img_path})
        if ocr.get("ok"):
            return str((ocr.get("data") or {}).get("text") or "").strip(), "Vision OCR"

    if query.strip():
        return query.strip(), "Input"
    if str(ctx.get("text") or "").strip():
        return str(ctx["text"]).strip(), str(ctx.get("source") or "Context")
    return "", "Idle"


def build_vocab_or_history_card(
    mode: str,
    entries: list[dict[str, Any]],
    vocab_ids: set[str],
    filter_q: str,
    is_en: bool,
    toast: str | None = None,
) -> dict[str, Any]:
    q = filter_q.strip().lower()
    filtered = [
        e for e in entries
        if not q or q in str(e.get("source", "")).lower() or q in str(e.get("translation", "")).lower()
    ]
    is_vocab = mode == "vocab"
    items: list[dict[str, Any]] = [
        {
            "id": "export-anki-row",
            "title": "Export Vocabulary to Anki (.tsv) & CSV →" if is_en else "一键导出生词本为 Anki 卡片 (.tsv) 与 CSV 表格 →",
            "subtitle": f"{len(vocab_ids)} saved item(s)" if is_en else f"当前共收藏 {len(vocab_ids)} 条生词/短语",
            "icon": "square.and.arrow.up",
            "badge": "ANKI / CSV",
            "commandArgs": ["--export"],
        }
    ]
    for e in filtered[:25]:
        eid = str(e.get("id") or "")
        src_txt = str(e.get("source") or "")
        dst_txt = str(e.get("translation") or "")
        t_lang = str(e.get("targetLang") or "en")
        saved = eid in vocab_ids
        actions = [
            {
                "id": f"tts-{eid}",
                "label": "Speak" if is_en else "朗读",
                "commandArgs": ["--speak", TTS_VOICES.get(t_lang, "en-US"), dst_txt, f"--{mode}"],
            }
        ]
        if is_vocab or saved:
            actions.append({
                "id": f"rm-{eid}",
                "label": "Remove" if is_en else "移出生词本",
                "style": "destructive",
                "commandArgs": ["--remove-vocab", eid, f"--{mode}"],
            })
        else:
            actions.append({
                "id": f"save-{eid}",
                "label": "Save Word" if is_en else "加入生词本",
                "commandArgs": ["--save-from-history", eid],
            })
        items.append({
            "id": f"row-{eid}",
            "title": f"{'⭐ ' if saved else ''}{src_txt}  →  {dst_txt}",
            "subtitle": str(e.get("phonetic") or e.get("savedAt") or ""),
            "icon": "star.fill" if saved else "clock",
            "badge": t_lang.upper(),
            "copyText": dst_txt,
            "actions": actions,
        })

    effect: dict[str, Any] = {"reloadSearchIndex": True}
    if toast:
        effect["toast"] = toast
    return {
        "schemaVersion": 2,
        "title": ("Vocabulary Book" if is_vocab else "Translation History") if is_en else ("流光译站 · 生词本" if is_vocab else "流光译站 · 最近翻译历史"),
        "subtitle": f"{len(filtered)} item(s) · Press Return to copy translation" if is_en else f"共 {len(filtered)} 条 · 回车直接复制译文，支持朗读与导出 Anki",
        "badge": f"{len(filtered)} ITEMS",
        "effect": effect,
        "items": items,
    }


def execute_plugin(
    argv: list[str],
    stdin_obj: dict[str, Any],
    sock_path: str = "",
    token: str = "",
    fetcher_override: Any = None,
) -> dict[str, Any]:
    cfg = stdin_obj.get("config") if isinstance(stdin_obj.get("config"), dict) else {}
    query = str(stdin_obj.get("query") or "")
    ctx = stdin_obj.get("context") if isinstance(stdin_obj.get("context"), dict) else {}
    locale = str(stdin_obj.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    data_dir = str(stdin_obj.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "")

    vocab = load_json_list(Path(data_dir) / "vocab.json") if data_dir else []
    history = load_json_list(Path(data_dir) / "history.json") if data_dir else []
    vocab_ids = {str(v.get("id")) for v in vocab}

    flag = argv[0] if argv else ""
    toast: str | None = None

    if flag == "--speak" and len(argv) >= 3:
        call_host_bridge(sock_path, token, "audio", "speak", {"language": argv[1], "text": argv[2]})
        toast = "Speaking aloud…" if is_en else "正在朗读…"
        tail = argv[3] if len(argv) >= 4 else ""
        if tail in {"--vocab", "--history"}:
            return build_vocab_or_history_card(tail.lstrip("-"), vocab if tail == "--vocab" else history, vocab_ids, query, is_en, toast)
        argv = ["--translate-direct", argv[2]]
        flag = argv[0]

    if flag == "--remove-vocab" and len(argv) >= 2:
        rid = argv[1]
        vocab = [v for v in vocab if str(v.get("id")) != rid]
        vocab_ids.discard(rid)
        save_store_and_sync_index(data_dir, vocab, history)
        return build_vocab_or_history_card("vocab", vocab, vocab_ids, query, is_en, "Removed from Vocabulary" if is_en else "已移出生词本")

    if flag == "--save-from-history" and len(argv) >= 2:
        hid = argv[1]
        for h in history:
            if str(h.get("id")) == hid and hid not in vocab_ids:
                vocab.insert(0, dict(h))
                vocab_ids.add(hid)
                break
        save_store_and_sync_index(data_dir, vocab, history)
        return build_vocab_or_history_card("history", history, vocab_ids, query, is_en, "Saved to Vocabulary Book" if is_en else "已收藏至生词本")

    if flag == "--save-inline" and len(argv) >= 5:
        _, eid, src_txt, dst_txt, t_lang = argv[:5]
        phon = argv[5] if len(argv) >= 6 else ""
        if eid not in vocab_ids:
            vocab.insert(0, {
                "id": eid, "source": src_txt, "translation": dst_txt, "targetLang": t_lang,
                "phonetic": phon, "savedAt": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
            })
            vocab_ids.add(eid)
            save_store_and_sync_index(data_dir, vocab, history)
        return build_vocab_or_history_card("vocab", vocab, vocab_ids, "", is_en, "Saved to Vocabulary Book" if is_en else "已加入生词本并同步免前缀索引")

    if flag == "--vocab":
        filt = argv[1] if len(argv) >= 2 else query
        return build_vocab_or_history_card("vocab", vocab, vocab_ids, filt, is_en)

    if flag == "--history":
        return build_vocab_or_history_card("history", history, vocab_ids, query, is_en)

    if flag == "--export":
        anki_p, csv_p = export_vocab_files(vocab, str(cfg.get("exportDir") or "~/Downloads"))
        return {
            "schemaVersion": 2,
            "title": "Vocabulary Exported" if is_en else "生词本已导出（Anki TSV + CSV）",
            "subtitle": f"{len(vocab)} word(s) exported" if is_en else f"共导出 {len(vocab)} 条词条，可直接导入 Anki 或 Excel",
            "badge": "EXPORTED",
            "effect": {"toast": "Exported Anki TSV & CSV" if is_en else "已导出 Anki TSV 与 CSV 文件"},
            "items": [
                {
                    "id": "anki-file",
                    "title": f"Anki Flashcards: {anki_p.name}",
                    "subtitle": str(anki_p),
                    "icon": "rectangle.stack.badge.plus",
                    "badge": "TSV",
                    "copyText": str(anki_p),
                },
                {
                    "id": "csv-file",
                    "title": f"Spreadsheet Table: {csv_p.name}",
                    "subtitle": str(csv_p),
                    "icon": "tablecells.fill",
                    "badge": "CSV",
                    "copyText": str(csv_p),
                },
            ],
        }

    primary = str(cfg.get("primaryLang") or "zh-Hans")
    secondary = str(cfg.get("secondaryLang") or "en")
    if flag == "--translate-direct" and len(argv) >= 2:
        raw_text, src_origin = argv[1], "Speak"
    else:
        raw_text, src_origin = resolve_input_text(argv, query, ctx, sock_path, token)

    if not raw_text:
        return {
            "schemaVersion": 2,
            "title": "Translate Hub · Ready" if is_en else "流光译站 · 多源划词与截图翻译",
            "subtitle": "Type any word/sentence above, use '>ja text' to pick target language, or trigger Selection/OCR"
            if is_en
            else "直接在搜索框输入单词/长句互译（可用 '>ja 文本' 指定目标语言），或使用下方快捷入口",
            "badge": f"{len(vocab)} SAVED",
            "metrics": [
                {"key": "Lang Pair" if is_en else "默认互译", "value": f"{primary} ⇄ {secondary}"},
                {"key": "Vocabulary" if is_en else "生词本", "value": str(len(vocab))},
                {"key": "History" if is_en else "最近历史", "value": str(len(history))},
            ],
            "items": [
                {
                    "id": "act-sel",
                    "title": "Translate Frontmost Selection" if is_en else "翻译当前前台选中文本（划词即译）",
                    "subtitle": "Reads active app selection via Accessibility (or clipboard fallback)" if is_en else "读取前台应用选中文字（无选区时自动回退剪贴板）",
                    "icon": "text.cursor",
                    "badge": "SELECTION",
                    "commandArgs": ["--selection"],
                },
                {
                    "id": "act-clip",
                    "title": "Translate Current Clipboard" if is_en else "翻译当前剪贴板文本",
                    "subtitle": "Auto-detects language and translates immediately" if is_en else "自动识别语种并在第一/第二语言间互译",
                    "icon": "doc.on.clipboard",
                    "badge": "CLIPBOARD",
                    "commandArgs": ["--clipboard"],
                },
                {
                    "id": "act-vocab",
                    "title": f"Open Vocabulary Book ({len(vocab)}) →" if is_en else f"打开生词本与 Anki 导出 ({len(vocab)} 条) →",
                    "subtitle": "Review saved words, listen to pronunciation, or export Anki TSV" if is_en else "管理收藏词条、语音朗读或导出 Anki 背单词卡片",
                    "icon": "star.square.on.square.fill",
                    "badge": "VOCAB",
                    "commandArgs": ["--vocab"],
                },
                {
                    "id": "act-hist",
                    "title": f"Recent Translation History ({len(history)}) →" if is_en else f"查看最近翻译历史 ({len(history)} 条) →",
                    "subtitle": "Re-copy or star recent translations" if is_en else "回看最近查词与句子翻译记录",
                    "icon": "clock.arrow.circlepath",
                    "badge": "HISTORY",
                    "commandArgs": ["--history"],
                },
            ],
        }

    clean_text, src_lang, target_lang = parse_target_override(raw_text, primary, secondary)
    if fetcher_override is not None:
        results, dict_info = fetcher_override(clean_text, src_lang, target_lang, cfg)
    else:
        results, dict_info = run_parallel_translation(clean_text, src_lang, target_lang, cfg)

    primary_trans = results[0]["text"] if results else ("(Network unavailable or blocked)" if is_en else "（当前离线或未开启网络域，请检查插件权限）")
    phonetic_note = str((dict_info or {}).get("explain") or "")
    eid = make_entry_id(clean_text, target_lang)

    if results:
        record = {
            "id": eid,
            "source": clean_text,
            "translation": primary_trans,
            "sourceLang": src_lang,
            "targetLang": target_lang,
            "phonetic": phonetic_note,
            "savedAt": dt.datetime.now().strftime("%Y-%m-%d %H:%M"),
        }
        history = [h for h in history if str(h.get("id")) != eid]
        history.insert(0, record)
        save_store_and_sync_index(data_dir, vocab, history)

        if str(cfg.get("autoCopyResult", "false")).lower() == "true":
            call_host_bridge(sock_path, token, "clipboard", "write", {"text": primary_trans})
            toast = "Translated & copied" if is_en else "已翻译并自动复制译文"

    items: list[dict[str, Any]] = []
    for idx, res in enumerate(results):
        prov = res["provider"]
        txt = res["text"]
        items.append({
            "id": f"res-{idx}",
            "title": txt,
            "subtitle": f"{prov} · {src_lang} → {target_lang}" + (" · Return to Copy" if is_en else " · 回车复制译文"),
            "icon": "sparkles" if "LLM" in prov else "globe",
            "badge": prov.upper()[:12],
            "copyText": txt,
            "actions": [
                {
                    "id": f"speak-dst-{idx}",
                    "label": "Speak" if is_en else "朗读译文",
                    "commandArgs": ["--speak", TTS_VOICES.get(target_lang, "en-US"), txt],
                },
                {
                    "id": f"save-voc-{idx}",
                    "label": ("Saved ⭐" if eid in vocab_ids else ("Save Word" if is_en else "加入生词本")),
                    "commandArgs": ["--vocab"] if eid in vocab_ids else ["--save-inline", eid, clean_text[:200], txt[:300], target_lang, phonetic_note[:160]],
                },
            ],
        })

    if dict_info and dict_info.get("explain"):
        rel = " · ".join(dict_info.get("related") or [])
        items.append({
            "id": "dict-card",
            "title": f"📖 {dict_info.get('word', clean_text)} — {dict_info['explain']}",
            "subtitle": rel or ("Dictionary Definition" if is_en else "词典词性与核心释义"),
            "icon": "character.book.closed.fill",
            "badge": "DICT",
            "copyText": str(dict_info["explain"]),
            "actions": [
                {
                    "id": "speak-src",
                    "label": "Pronounce" if is_en else "原词发音",
                    "commandArgs": ["--speak", TTS_VOICES.get(src_lang, "en-US"), clean_text],
                }
            ],
        })

    md_lines = [f"> {clean_text}"]
    if dict_info and dict_info.get("explain"):
        md_lines.append(f"\n**{'Dictionary' if is_en else '词典释义'}**：{dict_info['explain']}")

    effect: dict[str, Any] = {
        "reloadSearchIndex": True,
        "statusSummary": f"{len(vocab)} saved · {len(history)} history",
        "statusBadge": f"{len(vocab)} WORDS",
    }
    if toast:
        effect["toast"] = toast

    return {
        "schemaVersion": 2,
        "title": primary_trans[:96],
        "subtitle": f"[{src_origin}] {src_lang} → {target_lang} · {len(results)} engine(s)",
        "badge": f"{src_lang.upper()}→{target_lang.upper()}",
        "markdown": "\n".join(md_lines),
        "effect": effect,
        "items": items,
    }


def main() -> int:
    raw = sys.stdin.read()
    stdin_obj = json.loads(raw) if raw.strip().startswith("{") else {}
    out = execute_plugin(
        sys.argv[1:],
        stdin_obj,
        sock_path=os.environ.get("LUMAKEY_BRIDGE_SOCK", ""),
        token=os.environ.get("LUMAKEY_BRIDGE_TOKEN", ""),
    )
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
