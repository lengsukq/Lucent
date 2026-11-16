#!/usr/bin/env python3
"""Lumakey Official Store Plugin: Browser Bookmarks & History Hub (`browser-hub`).

Directly connects to local macOS browser data stores without requiring browser
extensions or cloud logins:
- Microsoft Edge (`~/Library/Application Support/Microsoft Edge/*`)
- Google Chrome (`~/Library/Application Support/Google/Chrome/*`)
- Apple Safari (`~/Library/Safari/Bookmarks.plist` & `History.db`)

Key engineering guarantees:
1. Lock-free SQLite WAL snapshotting: copies `History` / `History.db` (+ `-wal`
   and `-shm` sidecars) into an isolated scratch folder before querying with
   `PRAGMA query_only=ON`, so running browsers are never locked or blocked.
2. Multi-profile discovery: parses Chromium `Local State` (`profile.info_cache`)
   to surface human-readable profile labels across `Default` and `Profile *`.
3. Zero-subprocess 0ms global search: exports up to 450 deduplicated bookmarks &
   frequent history items into `PluginData/browser-hub/search-index.json`.
4. Graceful macOS TCC Full Disk Access diagnostics when `~/Library/Safari`
   raises `PermissionError`, while keeping Edge & Chrome fully operational.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import json
import math
import os
import plistlib
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path
from typing import Any

WEBKIT_EPOCH_OFFSET_SEC = 11_644_473_600  # Seconds between 1601-01-01 and 1970-01-01
COREDATA_EPOCH_OFFSET_SEC = 978_307_200   # Seconds between 1970-01-01 and 2001-01-01

BROWSER_SPECS: dict[str, dict[str, str]] = {
    "edge": {
        "label": "Edge",
        "bundle_id": "com.microsoft.edgemac",
        "icon": "globe",
        "rel_root": "Library/Application Support/Microsoft Edge",
    },
    "chrome": {
        "label": "Chrome",
        "bundle_id": "com.google.Chrome",
        "icon": "globe.americas.fill",
        "rel_root": "Library/Application Support/Google/Chrome",
    },
    "safari": {
        "label": "Safari",
        "bundle_id": "com.apple.Safari",
        "icon": "safari.fill",
        "rel_root": "Library/Safari",
    },
}


def webkit_to_unix(raw_val: Any) -> float:
    try:
        us = int(raw_val or 0)
    except (ValueError, TypeError):
        return 0.0
    if us <= 0:
        return 0.0
    unix_ts = (us / 1_000_000.0) - WEBKIT_EPOCH_OFFSET_SEC
    return max(0.0, unix_ts)


def coredata_to_unix(raw_val: Any) -> float:
    try:
        sec = float(raw_val or 0.0)
    except (ValueError, TypeError):
        return 0.0
    if sec <= 0:
        return 0.0
    return max(0.0, sec + COREDATA_EPOCH_OFFSET_SEC)


def parse_enabled_browsers(raw_cfg: str) -> list[str]:
    tokens = [t.strip().lower() for t in re.split(r"[,，\s]+", raw_cfg or "") if t.strip()]
    if not tokens:
        return ["edge", "chrome", "safari"]
    selected: list[str] = []
    for tok in tokens:
        if "edge" in tok and "edge" not in selected:
            selected.append("edge")
        elif "chrome" in tok and "chrome" not in selected:
            selected.append("chrome")
        elif "safari" in tok and "safari" not in selected:
            selected.append("safari")
    return selected or ["edge", "chrome", "safari"]


def resolve_browser_roots(user_home: Path | None = None) -> dict[str, Path]:
    home = user_home or Path(os.environ.get("LUMAKEY_BROWSER_HOME") or Path.home())
    roots: dict[str, Path] = {}
    for key, spec in BROWSER_SPECS.items():
        env_override = os.environ.get(f"LUMAKEY_{key.upper()}_DIR", "").strip()
        roots[key] = Path(env_override) if env_override else (home / spec["rel_root"])
    return roots


def discover_chromium_profiles(browser_root: Path) -> list[tuple[Path, str]]:
    if not browser_root.is_dir():
        return []
    name_map: dict[str, str] = {}
    local_state = browser_root / "Local State"
    if local_state.is_file():
        try:
            state_obj = json.loads(local_state.read_text(encoding="utf-8", errors="replace"))
            info_cache = ((state_obj.get("profile") or {}).get("info_cache")) or {}
            if isinstance(info_cache, dict):
                for dir_name, meta in info_cache.items():
                    if isinstance(meta, dict) and meta.get("name"):
                        name_map[str(dir_name)] = str(meta["name"]).strip()
        except Exception:
            pass

    candidates: list[Path] = []
    default_dir = browser_root / "Default"
    if default_dir.is_dir():
        candidates.append(default_dir)
    try:
        for child in sorted(browser_root.iterdir(), key=lambda p: p.name):
            if child.is_dir() and child.name.startswith("Profile "):
                candidates.append(child)
    except OSError:
        pass

    profiles: list[tuple[Path, str]] = []
    for prof_dir in candidates:
        if (prof_dir / "Bookmarks").is_file() or (prof_dir / "History").is_file():
            label = name_map.get(prof_dir.name) or prof_dir.name
            profiles.append((prof_dir, label))
    return profiles


def _walk_chromium_bookmark_node(
    node: dict[str, Any],
    browser_key: str,
    profile_label: str,
    folder_chain: list[str],
    out: list[dict[str, Any]],
) -> None:
    ntype = str(node.get("type") or "")
    if ntype == "url":
        url_val = str(node.get("url") or "").strip()
        if not url_val or url_val.startswith("javascript:") or url_val.startswith("place:"):
            return
        title = str(node.get("name") or "").strip() or _FallbackTitle(url_val)
        added_ts = webkit_to_unix(node.get("date_last_used")) or webkit_to_unix(node.get("date_added"))
        folder_str = " / ".join(folder_chain)
        out.append(
            {
                "kind": "bookmark",
                "browser": browser_key,
                "profile": profile_label,
                "title": title,
                "url": url_val,
                "folder": folder_str,
                "visitCount": 1,
                "timestamp": added_ts,
            }
        )
        return

    children = node.get("children")
    if isinstance(children, list):
        name = str(node.get("name") or "").strip()
        next_chain = [*folder_chain, name] if name else folder_chain
        for child in children:
            if isinstance(child, dict):
                _walk_chromium_bookmark_node(child, browser_key, profile_label, next_chain, out)


def _FallbackTitle(url_val: str) -> str:
    parsed = urllib.parse.urlparse(url_val)
    return (parsed.hostname or url_val).removeprefix("www.")


def read_chromium_bookmarks(bookmarks_file: Path, browser_key: str, profile_label: str) -> list[dict[str, Any]]:
    if not bookmarks_file.is_file():
        return []
    try:
        data = json.loads(bookmarks_file.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return []
    roots = data.get("roots") or {}
    if not isinstance(roots, dict):
        return []
    out: list[dict[str, Any]] = []
    for root_key in ("bookmark_bar", "other", "synced"):
        root_node = roots.get(root_key)
        if isinstance(root_node, dict):
            _walk_chromium_bookmark_node(root_node, browser_key, profile_label, [], out)
    return out


def _query_sqlite_snapshot(db_file: Path, sql: str, params: tuple[Any, ...]) -> list[tuple[Any, ...]]:
    if not db_file.is_file():
        return []
    scratch_root = Path(tempfile.mkdtemp(prefix="lk-bh-db-"))
    try:
        staged_db = scratch_root / db_file.name
        shutil.copy2(db_file, staged_db)
        for suffix in ("-wal", "-shm"):
            sidecar = Path(str(db_file) + suffix)
            if sidecar.is_file():
                try:
                    shutil.copy2(sidecar, Path(str(staged_db) + suffix))
                except OSError:
                    pass
        conn = sqlite3.connect(str(staged_db), timeout=2.5)
        try:
            conn.execute("PRAGMA query_only = ON;")
            cur = conn.execute(sql, params)
            return cur.fetchall()
        finally:
            conn.close()
    finally:
        shutil.rmtree(scratch_root, ignore_errors=True)


def read_chromium_history(
    history_db: Path,
    browser_key: str,
    profile_label: str,
    cutoff_unix: float,
    limit: int = 400,
) -> list[dict[str, Any]]:
    min_webkit_us = int((cutoff_unix + WEBKIT_EPOCH_OFFSET_SEC) * 1_000_000)
    sql = """
        SELECT url, title, visit_count, last_visit_time
        FROM urls
        WHERE hidden = 0 AND last_visit_time >= ?
        ORDER BY last_visit_time DESC
        LIMIT ?
    """
    try:
        rows = _query_sqlite_snapshot(history_db, sql, (min_webkit_us, limit))
    except sqlite3.Error:
        return []

    out: list[dict[str, Any]] = []
    for raw_url, raw_title, vcount, last_vt in rows:
        url_val = str(raw_url or "").strip()
        if not url_val or url_val.startswith(("chrome://", "edge://", "about:", "devtools://", "chrome-extension://", "extension://")):
            continue
        title = str(raw_title or "").strip() or _FallbackTitle(url_val)
        out.append(
            {
                "kind": "history",
                "browser": browser_key,
                "profile": profile_label,
                "title": title,
                "url": url_val,
                "folder": "",
                "visitCount": max(1, int(vcount or 1)),
                "timestamp": webkit_to_unix(last_vt),
            }
        )
    return out


def _walk_safari_plist_node(
    node: dict[str, Any],
    folder_chain: list[str],
    out: list[dict[str, Any]],
) -> None:
    btype = str(node.get("WebBookmarkType") or "")
    if btype == "WebBookmarkTypeLeaf":
        url_val = str(node.get("URLString") or "").strip()
        if not url_val or url_val.startswith("javascript:"):
            return
        uri_dict = node.get("URIDictionary") if isinstance(node.get("URIDictionary"), dict) else {}
        reading = node.get("ReadingList") if isinstance(node.get("ReadingList"), dict) else {}
        title = (
            str(uri_dict.get("title") or "").strip()
            or str(node.get("Title") or "").strip()
            or _FallbackTitle(url_val)
        )
        added_dt = reading.get("DateAdded")
        if isinstance(added_dt, dt.datetime):
            ts = (added_dt.replace(tzinfo=dt.timezone.utc) if added_dt.tzinfo is None else added_dt).timestamp()
        else:
            ts = 0.0
        folder_label = " / ".join(folder_chain)
        out.append(
            {
                "kind": "bookmark",
                "browser": "safari",
                "profile": "Reading List" if "Reading List" in folder_chain else "Default",
                "title": title,
                "url": url_val,
                "folder": folder_label,
                "visitCount": 1,
                "timestamp": ts,
            }
        )
        return

    children = node.get("Children")
    if isinstance(children, list):
        raw_title = str(node.get("Title") or "").strip()
        friendly = {
            "BookmarksBar": "个人收藏",
            "BookmarksMenu": "书签菜单",
            "com.apple.ReadingList": "Reading List",
        }.get(raw_title, raw_title)
        next_chain = [*folder_chain, friendly] if (friendly and friendly != "Root") else folder_chain
        for child in children:
            if isinstance(child, dict):
                _walk_safari_plist_node(child, next_chain, out)


def read_safari_store(safari_dir: Path, cutoff_unix: float, limit: int = 400) -> tuple[list[dict[str, Any]], bool]:
    """Return `(records, permission_denied)`."""
    if not safari_dir.exists():
        return ([], False)

    records: list[dict[str, Any]] = []
    permission_denied = False

    plist_path = safari_dir / "Bookmarks.plist"
    try:
        if plist_path.exists():
            with plist_path.open("rb") as fp:
                plist_root = plistlib.load(fp)
            if isinstance(plist_root, dict):
                _walk_safari_plist_node(plist_root, [], records)
    except PermissionError:
        permission_denied = True
    except Exception:
        pass

    hist_db = safari_dir / "History.db"
    min_cd = cutoff_unix - COREDATA_EPOCH_OFFSET_SEC
    sql = """
        SELECT hi.url, COALESCE(MAX(hv.title), ''), hi.visit_count, MAX(hv.visit_time) AS last_vt
        FROM history_items hi
        JOIN history_visits hv ON hv.history_item = hi.id
        WHERE hv.visit_time >= ?
        GROUP BY hi.id
        ORDER BY last_vt DESC
        LIMIT ?
    """
    try:
        if hist_db.exists():
            rows = _query_sqlite_snapshot(hist_db, sql, (min_cd, limit))
            for raw_url, raw_title, vcount, last_vt in rows:
                url_val = str(raw_url or "").strip()
                if not url_val or url_val.startswith(("safari-resource:", "about:")):
                    continue
                title = str(raw_title or "").strip() or _FallbackTitle(url_val)
                records.append(
                    {
                        "kind": "history",
                        "browser": "safari",
                        "profile": "Default",
                        "title": title,
                        "url": url_val,
                        "folder": "",
                        "visitCount": max(1, int(vcount or 1)),
                        "timestamp": coredata_to_unix(last_vt),
                    }
                )
    except PermissionError:
        permission_denied = True
    except sqlite3.Error:
        pass

    return (records, permission_denied)


def aggregate_records(
    raw_records: list[dict[str, Any]],
    pinned_urls: set[str],
) -> list[dict[str, Any]]:
    """Merge duplicate URLs across bookmarks & history while preserving rich metadata."""
    merged: dict[str, dict[str, Any]] = {}
    for rec in raw_records:
        url_val = str(rec.get("url") or "").strip()
        if not url_val:
            continue
        norm_key = url_val.rstrip("/") if url_val.count("/") >= 3 else url_val
        existing = merged.get(norm_key)
        is_bm = rec["kind"] == "bookmark"
        if existing is None:
            uid = hashlib.sha1(norm_key.encode("utf-8")).hexdigest()[:12]
            merged[norm_key] = {
                "id": uid,
                "url": url_val,
                "title": rec["title"],
                "hasBookmark": is_bm,
                "hasHistory": not is_bm,
                "browsers": [rec["browser"]],
                "primaryBrowser": rec["browser"],
                "profiles": [f"{BROWSER_SPECS[rec['browser']]['label']}({rec['profile']})" if rec["profile"] != "Default" else BROWSER_SPECS[rec["browser"]]["label"]],
                "folders": [rec["folder"]] if rec.get("folder") else [],
                "visitCount": int(rec.get("visitCount") or 1),
                "timestamp": float(rec.get("timestamp") or 0.0),
                "pinned": url_val in pinned_urls or norm_key in pinned_urls,
            }
        else:
            if is_bm and not existing["hasBookmark"]:
                existing["title"] = rec["title"] or existing["title"]
                existing["primaryBrowser"] = rec["browser"]
            existing["hasBookmark"] = existing["hasBookmark"] or is_bm
            existing["hasHistory"] = existing["hasHistory"] or (not is_bm)
            if rec["browser"] not in existing["browsers"]:
                existing["browsers"].append(rec["browser"])
            prof_tag = (
                f"{BROWSER_SPECS[rec['browser']]['label']}({rec['profile']})"
                if rec["profile"] != "Default"
                else BROWSER_SPECS[rec["browser"]]["label"]
            )
            if prof_tag not in existing["profiles"]:
                existing["profiles"].append(prof_tag)
            if rec.get("folder") and rec["folder"] not in existing["folders"]:
                existing["folders"].append(rec["folder"])
            existing["visitCount"] = max(existing["visitCount"], int(rec.get("visitCount") or 1))
            existing["timestamp"] = max(existing["timestamp"], float(rec.get("timestamp") or 0.0))

    now = time.time()
    items = list(merged.values())

    def rank_key(item: dict[str, Any]) -> tuple[int, float]:
        age_hours = max(0.0, (now - item["timestamp"]) / 3600.0) if item["timestamp"] > 0 else 720.0
        recency = 40.0 / (1.0 + age_hours / 24.0)
        freq = math.log2(max(1, item["visitCount"]) + 1) * 12.0
        bm_bonus = 35.0 if item["hasBookmark"] else 0.0
        return (0 if item["pinned"] else 1, -(bm_bonus + recency + freq))

    items.sort(key=rank_key)
    return items


def load_pinned_urls(data_dir: Path | None) -> set[str]:
    if not data_dir:
        return set()
    pin_file = data_dir / "pinned-urls.json"
    if not pin_file.is_file():
        return set()
    try:
        arr = json.loads(pin_file.read_text(encoding="utf-8"))
        return {str(x) for x in arr if str(x).strip()} if isinstance(arr, list) else set()
    except Exception:
        return set()


def toggle_pinned_url(data_dir: Path | None, target_url: str) -> bool:
    if not data_dir or not target_url:
        return False
    data_dir.mkdir(parents=True, exist_ok=True)
    pins = load_pinned_urls(data_dir)
    if target_url in pins:
        pins.remove(target_url)
        now_pinned = False
    else:
        pins.add(target_url)
        now_pinned = True
    (data_dir / "pinned-urls.json").write_text(
        json.dumps(sorted(pins), ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return now_pinned


def export_launcher_search_index(
    items: list[dict[str, Any]],
    data_dir: Path | None,
    safari_denied: bool,
) -> None:
    if not data_dir:
        return
    data_dir.mkdir(parents=True, exist_ok=True)
    idx_entries: list[dict[str, Any]] = []
    for item in items[:420]:
        url_val = item["url"]
        if not url_val.startswith(("http://", "https://")):
            continue
        domain = (urllib.parse.urlparse(url_val).hostname or "").removeprefix("www.")
        b_badges = "/".join(BROWSER_SPECS[b]["label"] for b in item["browsers"])
        folder_part = item["folders"][0] if item["folders"] else ""
        sub_parts = [p for p in (b_badges, folder_part, domain) if p]
        tags = list(item["browsers"])
        tags.append("bookmark" if item["hasBookmark"] else "history")
        for f in item["folders"]:
            for seg in f.split("/"):
                clean_seg = seg.strip()
                if clean_seg and clean_seg not in tags:
                    tags.append(clean_seg)

        prio = 85 if item["pinned"] else (55 if item["hasBookmark"] else min(45, 10 + item["visitCount"] * 2))
        primary_b = item["primaryBrowser"]
        idx_entries.append(
            {
                "id": item["id"],
                "title": ("⭐ " if item["pinned"] else "") + item["title"][:90],
                "subtitle": " · ".join(sub_parts),
                "url": url_val,
                "copyText": url_val,
                "icon": "pin.fill" if item["pinned"] else ("bookmark.fill" if item["hasBookmark"] else BROWSER_SPECS[primary_b]["icon"]),
                "badge": f"{b_badges} · {'BM' if item['hasBookmark'] else 'HIS'}"[:18],
                "tags": tags[:8],
                "pinned": bool(item["pinned"]),
                "priority": int(prio),
            }
        )

    tmp_idx = data_dir / "search-index.json.tmp"
    tmp_idx.write_text(json.dumps({"version": 1, "items": idx_entries}, ensure_ascii=False), encoding="utf-8")
    tmp_idx.replace(data_dir / "search-index.json")

    bm_cnt = sum(1 for x in items if x["hasBookmark"])
    his_cnt = sum(1 for x in items if x["hasHistory"])
    summary = f"书签 {bm_cnt} · 历史 {his_cnt}" + (" (Safari 待授磁盘权限)" if safari_denied else "")
    (data_dir / "status.json").write_text(
        json.dumps({"summary": summary, "badge": f"{len(items)}"}, ensure_ascii=False),
        encoding="utf-8",
    )


def collect_or_load_snapshot(
    enabled_browsers: list[str],
    history_days: int,
    ttl_seconds: int,
    data_dir: Path | None,
    user_home: Path | None = None,
    force_refresh: bool = False,
) -> tuple[list[dict[str, Any]], dict[str, int], bool, str]:
    cache_file = (data_dir / "snapshot-cache.json") if data_dir else None
    pins = load_pinned_urls(data_dir)
    cache_sig = f"{','.join(enabled_browsers)}:{history_days}"

    if not force_refresh and ttl_seconds > 0 and cache_file and cache_file.is_file():
        try:
            cached = json.loads(cache_file.read_text(encoding="utf-8"))
            age = time.time() - float(cached.get("savedAt") or 0)
            if age <= ttl_seconds and cached.get("sig") == cache_sig and isinstance(cached.get("items"), list):
                items = cached["items"]
                for it in items:
                    it["pinned"] = (it.get("url") in pins)
                return (
                    items,
                    cached.get("browserCounts") or {},
                    bool(cached.get("safariDenied")),
                    f"{int(age)}s cache",
                )
        except Exception:
            pass

    roots = resolve_browser_roots(user_home=user_home)
    cutoff_unix = time.time() - (max(1, history_days) * 86400.0)
    raw_records: list[dict[str, Any]] = []
    browser_counts: dict[str, int] = {"edge": 0, "chrome": 0, "safari": 0}
    safari_denied = False

    for b_key in enabled_browsers:
        if b_key in ("edge", "chrome"):
            profiles = discover_chromium_profiles(roots[b_key])
            b_recs: list[dict[str, Any]] = []
            for prof_dir, prof_label in profiles:
                b_recs.extend(read_chromium_bookmarks(prof_dir / "Bookmarks", b_key, prof_label))
                b_recs.extend(read_chromium_history(prof_dir / "History", b_key, prof_label, cutoff_unix))
            browser_counts[b_key] = len(b_recs)
            raw_records.extend(b_recs)
        elif b_key == "safari":
            s_recs, denied = read_safari_store(roots["safari"], cutoff_unix)
            safari_denied = denied
            browser_counts["safari"] = len(s_recs)
            raw_records.extend(s_recs)

    items = aggregate_records(raw_records, pins)
    export_launcher_search_index(items, data_dir, safari_denied)

    if cache_file:
        try:
            cache_file.parent.mkdir(parents=True, exist_ok=True)
            cache_file.write_text(
                json.dumps(
                    {
                        "savedAt": time.time(),
                        "sig": cache_sig,
                        "safariDenied": safari_denied,
                        "browserCounts": browser_counts,
                        "items": items[:1500],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
        except OSError:
            pass

    return (items, browser_counts, safari_denied, "live")


def parse_query_filters(
    raw_query: str,
    forced_browser: str = "",
    forced_kind: str = "",
) -> tuple[str, str, list[str], list[str]]:
    """Return `(browser_filter, kind_filter, folder_tags, text_tokens)`."""
    b_filter = forced_browser.lower().strip()
    k_filter = forced_kind.lower().strip()
    folder_tags: list[str] = []
    text_tokens: list[str] = []

    for tok in raw_query.strip().split():
        low = tok.lower()
        if low in {"@edge", "edge:"}:
            b_filter = "edge"
        elif low in {"@chrome", "chrome:"}:
            b_filter = "chrome"
        elif low in {"@safari", "safari:"}:
            b_filter = "safari"
        elif low in {"@bm", "@bookmark", "@bookmarks", "bm:", "书签:"}:
            k_filter = "bookmarks"
        elif low in {"@his", "@history", "his:", "历史:"}:
            k_filter = "history"
        elif low.startswith("#") and len(low) > 1:
            folder_tags.append(low[1:])
        else:
            text_tokens.append(low)
    return (b_filter, k_filter, folder_tags, text_tokens)


def filter_aggregated_items(
    items: list[dict[str, Any]],
    browser_filter: str,
    kind_filter: str,
    folder_tags: list[str],
    text_tokens: list[str],
) -> list[dict[str, Any]]:
    matched: list[dict[str, Any]] = []
    for it in items:
        if browser_filter and browser_filter not in it["browsers"]:
            continue
        if kind_filter == "bookmarks" and not it["hasBookmark"]:
            continue
        if kind_filter == "history" and not it["hasHistory"]:
            continue
        if folder_tags:
            folders_low = " ".join(it.get("folders") or []).lower()
            if not all(ft in folders_low for ft in folder_tags):
                continue
        if text_tokens:
            hay = f"{it['title']} {it['url']} {' '.join(it.get('folders') or [])} {' '.join(it.get('profiles') or [])}".lower()
            if not all(tok in hay for tok in text_tokens):
                continue
        matched.append(it)
    return matched


def format_relative_time(unix_ts: float, is_en: bool) -> str:
    if unix_ts <= 0:
        return ""
    delta = max(0.0, time.time() - unix_ts)
    if delta < 60:
        return "just now" if is_en else "刚刚"
    if delta < 3600:
        m = int(delta // 60)
        return f"{m}m ago" if is_en else f"{m} 分钟前"
    if delta < 86400:
        h = int(delta // 3600)
        return f"{h}h ago" if is_en else f"{h} 小时前"
    d = int(delta // 86400)
    if d <= 30:
        return f"{d}d ago" if is_en else f"{d} 天前"
    return dt.datetime.fromtimestamp(unix_ts).strftime("%Y-%m-%d")


def open_url_in_browser(browser_key: str, target_url: str) -> bool:
    if not target_url.startswith(("http://", "https://")):
        return False
    spec = BROWSER_SPECS.get(browser_key)
    cmd = ["/usr/bin/open"]
    if spec:
        cmd.extend(["-b", spec["bundle_id"]])
    cmd.append(target_url)
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=3.0)
        if res.returncode == 0:
            return True
        fallback = subprocess.run(["/usr/bin/open", target_url], capture_output=True, text=True, timeout=3.0)
        return fallback.returncode == 0
    except Exception:
        return False


def build_view_card(
    items: list[dict[str, Any]],
    filtered: list[dict[str, Any]],
    browser_counts: dict[str, int],
    safari_denied: bool,
    browser_filter: str,
    kind_filter: str,
    cache_state: str,
    locale: str = "zh-Hans",
    open_in_source: bool = False,
    max_rows: int = 25,
    toast_msg: str | None = None,
) -> dict[str, Any]:
    is_en = locale.lower().startswith("en")
    rows: list[dict[str, Any]] = []

    if safari_denied and (not browser_filter or browser_filter == "safari"):
        rows.append(
            {
                "id": "safari-fda-guide",
                "title": (
                    "Grant Full Disk Access to Unlock Safari Bookmarks & History"
                    if is_en
                    else "授予「完全磁盘访问权限」以解锁 Safari 书签与历史记录"
                ),
                "subtitle": (
                    "macOS protects ~/Library/Safari via TCC. Edge & Chrome work without extra permissions."
                    if is_en
                    else "macOS 对 ~/Library/Safari 启用了隐私保护（Edge 与 Chrome 已正常直连，无需额外权限）"
                ),
                "icon": "lock.shield.fill",
                "badge": "SAFARI TCC",
                "openURL": "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            }
        )

    for it in filtered[:max_rows]:
        url_val = it["url"]
        primary_b = it["primaryBrowser"]
        b_label = BROWSER_SPECS[primary_b]["label"]
        domain = (urllib.parse.urlparse(url_val).hostname or "").removeprefix("www.")
        profiles_txt = " / ".join(it["profiles"][:2])
        folder_txt = f"📁 {it['folders'][0]}" if it.get("folders") else ""
        visits_txt = (
            (f"{it['visitCount']} visits" if is_en else f"访问 {it['visitCount']} 次")
            if it["hasHistory"] and it["visitCount"] > 1
            else ""
        )
        time_txt = format_relative_time(it["timestamp"], is_en)
        sub_parts = [p for p in (profiles_txt, folder_txt, domain, visits_txt, time_txt) if p]

        kind_tag = "BM+HIS" if (it["hasBookmark"] and it["hasHistory"]) else ("BM" if it["hasBookmark"] else "HIS")
        row: dict[str, Any] = {
            "id": f"bh-{it['id']}",
            "title": ("⭐ " if it["pinned"] else "") + it["title"][:88],
            "subtitle": " · ".join(sub_parts),
            "icon": "pin.fill" if it["pinned"] else ("bookmark.fill" if it["hasBookmark"] else BROWSER_SPECS[primary_b]["icon"]),
            "badge": f"{b_label} · {kind_tag}",
            "copyText": url_val,
            "actions": [
                {
                    "id": f"open-src-{it['id']}",
                    "label": f"Open in {b_label}" if is_en else f"用 {b_label} 打开",
                    "style": "primary",
                    "commandArgs": ["--open-in", primary_b, url_val],
                },
                {
                    "id": f"pin-{it['id']}",
                    "label": ("Unpin" if it["pinned"] else "Pin") if is_en else ("取消置顶" if it["pinned"] else "星标置顶"),
                    "commandArgs": ["--toggle-pin", url_val],
                },
            ],
        }
        if open_in_source:
            row["commandArgs"] = ["--open-in", primary_b, url_val]
        else:
            row["openURL"] = url_val
        rows.append(row)

    if not rows:
        rows.append(
            {
                "id": "empty-browser-hits",
                "title": "No matching bookmarks or history found" if is_en else "未匹配到符合条件的书签或历史记录",
                "subtitle": (
                    "Tip: use @edge, @chrome, @safari, @bm, @his, or #FolderName to filter"
                    if is_en
                    else "提示：可使用 @edge / @chrome / @safari / @bm / @his 或 #收藏夹名 组合筛选"
                ),
                "icon": "magnifyingglass",
                "badge": "EMPTY",
                "commandArgs": ["--sync"],
            }
        )

    bm_total = sum(1 for x in items if x["hasBookmark"])
    his_total = sum(1 for x in items if x["hasHistory"])
    scope_bits = []
    if browser_filter:
        scope_bits.append(BROWSER_SPECS.get(browser_filter, {}).get("label", browser_filter))
    if kind_filter:
        scope_bits.append(kind_filter.upper())
    scope_prefix = f"[{' · '.join(scope_bits)}] " if scope_bits else ""

    subtitle = (
        f"{scope_prefix}Matched {len(filtered)}/{len(items)} · {cache_state} · Filter: @edge @chrome @safari @bm @his #folder"
        if is_en
        else f"{scope_prefix}命中 {len(filtered)} / {len(items)} 条（{cache_state}）· 支持 @edge @chrome @safari @bm @his #目录"
    )

    effect: dict[str, Any] = {
        "reloadSearchIndex": True,
        "statusSummary": f"书签 {bm_total} · 历史 {his_total}",
        "statusBadge": str(len(items)),
    }
    if toast_msg:
        effect["toast"] = toast_msg

    return {
        "schemaVersion": 2,
        "title": "Browser Bookmarks & History Hub" if is_en else "三端浏览器书签与历史中枢",
        "subtitle": subtitle,
        "badge": (browser_filter.upper() if browser_filter else "3 BROWSERS"),
        "effect": effect,
        "metrics": [
            {"key": "Bookmarks" if is_en else "书签总数", "value": str(bm_total)},
            {"key": "History" if is_en else "近期历史", "value": str(his_total)},
            {"key": "Edge / Chrome", "value": f"{browser_counts.get('edge', 0)} / {browser_counts.get('chrome', 0)}"},
            {
                "key": "Safari",
                "value": ("Need FDA" if is_en else "待授磁盘权限")
                if safari_denied
                else str(browser_counts.get("safari", 0)),
            },
        ],
        "items": rows,
    }


def dispatch(stdin_payload: dict[str, Any], argv: list[str], user_home: Path | None = None) -> dict[str, Any]:
    cfg = stdin_payload.get("config") if isinstance(stdin_payload.get("config"), dict) else {}
    query = str(stdin_payload.get("query") or "").strip()
    locale = str(stdin_payload.get("locale") or os.environ.get("LUMAKEY_LOCALE") or "zh-Hans")
    is_en = locale.lower().startswith("en")
    raw_dd = str(stdin_payload.get("dataDir") or os.environ.get("LUMAKEY_DATA_DIR") or "").strip()
    data_dir = Path(raw_dd) if raw_dd else None

    enabled_browsers = parse_enabled_browsers(str(cfg.get("enabledBrowsers") or "Edge, Chrome, Safari"))
    try:
        history_days = max(1, min(90, int(cfg.get("historyDays") or 14)))
    except ValueError:
        history_days = 14
    try:
        ttl_seconds = max(0, min(1800, int(cfg.get("cacheTtlSeconds") or 120)))
    except ValueError:
        ttl_seconds = 120
    try:
        max_rows = max(5, min(50, int(cfg.get("maxCardItems") or 25)))
    except ValueError:
        max_rows = 25
    open_in_source = str(cfg.get("openInSourceBrowser", "false")).lower() == "true"

    forced_browser = ""
    forced_kind = ""
    force_refresh = False
    toast_msg: str | None = None

    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--browser" and i + 1 < len(argv):
            forced_browser = argv[i + 1].lower()
            i += 2
            continue
        if arg == "--kind" and i + 1 < len(argv):
            forced_kind = argv[i + 1].lower()
            i += 2
            continue
        if arg == "--sync":
            force_refresh = True
            toast_msg = "Browser search index refreshed" if is_en else "已同步刷新三端浏览器免前缀检索索引"
            i += 1
            continue
        if arg == "--toggle-pin" and i + 1 < len(argv):
            pinned_now = toggle_pinned_url(data_dir, argv[i + 1])
            force_refresh = True
            toast_msg = (
                ("Pinned to top" if pinned_now else "Unpinned")
                if is_en
                else ("已星标置顶该网页" if pinned_now else "已取消置顶")
            )
            i += 2
            continue
        if arg == "--open-in" and i + 2 < len(argv):
            b_target, target_url = argv[i + 1].lower(), argv[i + 2]
            ok = open_url_in_browser(b_target, target_url)
            b_name = BROWSER_SPECS.get(b_target, {}).get("label", b_target)
            return {
                "schemaVersion": 2,
                "title": f"Opened in {b_name}" if is_en else f"已在 {b_name} 中打开",
                "subtitle": target_url,
                "badge": "OPENED" if ok else "ERROR",
                "effect": {
                    "closeOverlay": ok,
                    "toast": (f"Opened in {b_name}" if is_en else f"已调用 {b_name} 打开链接")
                    if ok
                    else ("Failed to launch browser" if is_en else "调用浏览器打开失败"),
                },
                "items": [],
            }
        i += 1

    if forced_browser and forced_browser not in enabled_browsers:
        enabled_browsers = [*enabled_browsers, forced_browser]

    items, b_counts, safari_denied, cache_state = collect_or_load_snapshot(
        enabled_browsers=enabled_browsers,
        history_days=history_days,
        ttl_seconds=ttl_seconds,
        data_dir=data_dir,
        user_home=user_home,
        force_refresh=force_refresh,
    )
    b_filter, k_filter, folder_tags, text_tokens = parse_query_filters(query, forced_browser, forced_kind)
    filtered = filter_aggregated_items(items, b_filter, k_filter, folder_tags, text_tokens)

    return build_view_card(
        items=items,
        filtered=filtered,
        browser_counts=b_counts,
        safari_denied=safari_denied,
        browser_filter=b_filter,
        kind_filter=k_filter,
        cache_state=cache_state,
        locale=locale,
        open_in_source=open_in_source,
        max_rows=max_rows,
        toast_msg=toast_msg,
    )


def main() -> int:
    raw_stdin = sys.stdin.read()
    stdin_obj: dict[str, Any] = {}
    if raw_stdin.strip():
        try:
            stdin_obj = json.loads(raw_stdin)
        except json.JSONDecodeError:
            stdin_obj = {"query": raw_stdin.strip()}
    payload = dispatch(stdin_obj, sys.argv[1:])
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
