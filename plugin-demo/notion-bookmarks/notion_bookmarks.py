#!/usr/bin/env python3
"""Lumakey Notion 书签收藏插件 (参考 lengsukq/nav-notion-lime)。"""

from __future__ import annotations

import html
import json
import os
import re
import shlex
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

NOTION_VERSION = "2022-06-28"
DEFAULT_API_BASE = "https://api.notion.com/v1"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

FIELD_CANDIDATES: dict[str, tuple[str, ...]] = {
    "title": ("name", "title", "名称", "标题"),
    "url": ("url", "link", "链接", "地址"),
    "description": ("description", "desc", "描述", "说明"),
    "tags": ("tag", "tags", "标签"),
    "category": ("category", "group", "分类", "分组"),
    "icon": ("icon", "图标"),
    "priority": ("priority", "sort", "优先级"),
    "pinned": ("pinned", "pin", "is_top", "置顶"),
}

TITLE_SUFFIX_RE = re.compile(
    r"\s*[-_|—–·]\s*(?:哔哩哔哩|bilibili|知乎|GitHub|百度百科|官方网站|Official Site|主页).*$",
    re.IGNORECASE,
)
URL_RE = re.compile(r"(https?://[^\s<>\"'\]\)]+)", re.IGNORECASE)
HEX32_RE = re.compile(r"([0-9a-fA-F]{32})")
UUID_RE = re.compile(r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})")


class NotionAPIError(RuntimeError):
    """封装 Notion HTTP 错误状态码与说明。"""

    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def normalize_database_id(raw: str) -> str:
    """支持 32 位 ID、UUID 或完整 Notion 数据库 URL，返回标准 UUID 格式。"""
    cleaned = raw.strip()
    if not cleaned:
        return ""
    uuid_match = UUID_RE.search(cleaned)
    if uuid_match:
        return uuid_match.group(1).lower()
    # 去掉连字符后再匹配 32 位十六进制 ID（兼容路径或查询串）
    compact = cleaned.split("?")[0].replace("-", "")
    hex_match = HEX32_RE.search(compact)
    if hex_match:
        h = hex_match.group(1).lower()
        return f"{h[0:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:32]}"
    return cleaned


def extract_first_url(text: str) -> str:
    """从文本或剪贴板中提取首个 http/https URL。"""
    if not text:
        return ""
    m = URL_RE.search(text.strip())
    return m.group(1).rstrip(".,;!?，。；！？") if m else ""


def normalize_target_url(raw: str) -> str:
    """补全协议头并清理空白。"""
    candidate = extract_first_url(raw) or raw.strip()
    if not candidate:
        return ""
    if not re.match(r"^https?://", candidate, re.IGNORECASE):
        candidate = f"https://{candidate}"
    return candidate


def safe_int(value: Any, default: int) -> int:
    try:
        return int(str(value).strip())
    except (ValueError, TypeError):
        return default


def is_truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on", "是"}


def parse_tags_csv(raw: str) -> list[str]:
    parts = [p.strip() for p in re.split(r"[,，、]+", raw or "") if p.strip()]
    seen: set[str] = set()
    out: list[str] = []
    for tag in parts:
        if tag not in seen:
            seen.add(tag)
            out.append(tag)
    return out


def fetch_url_metadata(target_url: str, timeout: float = 2.5) -> dict[str, str]:
    """参考 nav-notion-lime /api/url-info 抓取网页 title 与 description。"""
    parsed = urllib.parse.urlparse(target_url)
    hostname = (parsed.hostname or target_url).removeprefix("www.")
    title = ""
    description = ""

    req = urllib.request.Request(
        target_url,
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            ctype = (resp.headers.get("Content-Type") or "").lower()
            if "html" in ctype or not ctype:
                raw_bytes = resp.read(262_144)
                charset = resp.headers.get_content_charset() or "utf-8"
                body = raw_bytes.decode(charset, errors="replace")
                title = _extract_html_title(body)
                description = _extract_html_description(body)
    except Exception:
        pass

    return {
        "title": title or hostname,
        "description": description,
    }


def _extract_meta_content(body: str, attr: str, value: str) -> str:
    p1 = re.compile(
        rf'<meta[^>]+{attr}\s*=\s*["\']{re.escape(value)}["\'][^>]+content\s*=\s*["\']([^"\']*)["\']',
        re.IGNORECASE,
    )
    p2 = re.compile(
        rf'<meta[^>]+content\s*=\s*["\']([^"\']*)["\'][^>]+{attr}\s*=\s*["\']{re.escape(value)}["\']',
        re.IGNORECASE,
    )
    m = p1.search(body) or p2.search(body)
    if not m:
        return ""
    return re.sub(r"[\r\n\t]+", " ", html.unescape(m.group(1))).strip()


def _extract_html_title(body: str) -> str:
    og_title = _extract_meta_content(body, "property", "og:title")
    raw_title = ""
    if not og_title:
        m = re.search(r"<title[^>]*>(.*?)</title>", body, re.IGNORECASE | re.DOTALL)
        if m:
            raw_title = re.sub(r"[\r\n\t]+", " ", html.unescape(m.group(1))).strip()
    title = (og_title or raw_title).strip()
    if title:
        cleaned = TITLE_SUFFIX_RE.sub("", title).strip()
        if cleaned:
            return cleaned
    return title


def _extract_html_description(body: str) -> str:
    return (
        _extract_meta_content(body, "property", "og:description")
        or _extract_meta_content(body, "name", "description")
    )


class NotionClient:
    """轻量 Notion REST API 客户端（标准库 urllib，适配 2022-06-28）。"""

    def __init__(self, token: str, database_id: str, api_base: str | None = None) -> None:
        self.token = token.strip()
        self.database_id = normalize_database_id(database_id)
        base = (api_base or os.environ.get("LUMAKEY_NOTION_API_BASE") or DEFAULT_API_BASE).rstrip("/")
        self.api_base = base

    def _request(self, method: str, path: str, body: dict[str, Any] | None = None, timeout: float = 4.5) -> dict[str, Any]:
        url = f"{self.api_base}{path}"
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Notion-Version": NOTION_VERSION,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8")
                return json.loads(raw) if raw.strip() else {}
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            code = f"http_{exc.code}"
            msg = err_body or exc.reason
            try:
                parsed = json.loads(err_body)
                code = str(parsed.get("code") or code)
                msg = str(parsed.get("message") or msg)
            except Exception:
                pass
            raise NotionAPIError(exc.code, code, msg) from exc
        except urllib.error.URLError as exc:
            raise NotionAPIError(0, "network_error", f"网络请求失败：{exc.reason}") from exc

    def retrieve_database_info(self) -> tuple[str, dict[str, tuple[str, str]]]:
        """读取数据库标题与字段 schema 映射。"""
        db = self._request("GET", f"/databases/{self.database_id}")
        db_title = "".join(t.get("plain_text", "") for t in db.get("title", [])).strip() or "Notion 书签库"
        props = db.get("properties") or {}
        schema_map = resolve_schema_map(props)
        return db_title, schema_map

    def query_all_bookmarks(self, max_pages: int = 3) -> list[dict[str, Any]]:
        """分页拉取 Notion 书签条目并按置顶、优先级、名称排序。"""
        items: list[dict[str, Any]] = []
        cursor: str | None = None
        for _ in range(max_pages):
            payload: dict[str, Any] = {"page_size": 100}
            if cursor:
                payload["start_cursor"] = cursor
            res = self._request("POST", f"/databases/{self.database_id}/query", payload)
            for page in res.get("results", []):
                if not page.get("archived", False):
                    items.append(transform_page(page))
            if not res.get("has_more"):
                break
            cursor = res.get("next_cursor")
            if not cursor:
                break
        return sort_bookmarks(items)

    def create_bookmark(self, payload: dict[str, Any], schema_map: dict[str, tuple[str, str]]) -> dict[str, Any]:
        props = build_notion_properties(payload, schema_map, is_update=False)
        page = self._request(
            "POST",
            "/pages",
            {"parent": {"database_id": self.database_id}, "properties": props},
        )
        return transform_page(page)

    def update_bookmark(self, page_id: str, payload: dict[str, Any], schema_map: dict[str, tuple[str, str]]) -> dict[str, Any]:
        props = build_notion_properties(payload, schema_map, is_update=True)
        page = self._request("PATCH", f"/pages/{page_id}", {"properties": props})
        return transform_page(page)

    def archive_bookmark(self, page_id: str) -> None:
        self._request("PATCH", f"/pages/{page_id}", {"archived": True})


def resolve_schema_map(db_properties: dict[str, Any]) -> dict[str, tuple[str, str]]:
    """根据 Notion 数据库真实属性列表推断各逻辑字段的名称与类型。"""
    lowered = {k.lower(): (k, str(v.get("type") or "")) for k, v in db_properties.items() if isinstance(v, dict)}
    resolved: dict[str, tuple[str, str]] = {}

    for logical, candidates in FIELD_CANDIDATES.items():
        for cand in candidates:
            hit = lowered.get(cand.lower())
            if hit:
                resolved[logical] = hit
                break

    if "title" not in resolved:
        for prop_name, prop_meta in db_properties.items():
            if isinstance(prop_meta, dict) and prop_meta.get("type") == "title":
                resolved["title"] = (prop_name, "title")
                break
    return resolved


def infer_schema_from_page(page: dict[str, Any]) -> dict[str, tuple[str, str]]:
    """当未提前获取 database schema 时，从单条页面属性结构推断字段映射。"""
    props = page.get("properties") or {}
    return resolve_schema_map(props)


def _find_prop(props: dict[str, Any], logical: str) -> dict[str, Any] | None:
    lowered = {k.lower(): v for k, v in props.items()}
    for cand in FIELD_CANDIDATES[logical]:
        if cand.lower() in lowered:
            return lowered[cand.lower()]
    if logical == "title":
        for v in props.values():
            if isinstance(v, dict) and v.get("type") == "title":
                return v
    return None


def _extract_title(prop: dict[str, Any] | None) -> str:
    if not prop or prop.get("type") != "title":
        return "Untitled"
    text = "".join(item.get("plain_text", "") for item in prop.get("title") or []).strip()
    return text or "Untitled"


def _extract_url(prop: dict[str, Any] | None) -> str:
    if not prop:
        return ""
    ptype = prop.get("type")
    if ptype == "url":
        return str(prop.get("url") or "").strip()
    if ptype == "rich_text":
        items = prop.get("rich_text") or []
        if items:
            first = items[0]
            link_url = ((first.get("text") or {}).get("link") or {}).get("url")
            if link_url:
                return str(link_url).strip()
            return "".join(x.get("plain_text", "") for x in items).strip()
    return ""


def _extract_rich_text(prop: dict[str, Any] | None) -> str:
    if not prop or prop.get("type") != "rich_text":
        return ""
    return "".join(item.get("plain_text", "") for item in prop.get("rich_text") or []).strip()


def _extract_tags(prop: dict[str, Any] | None) -> list[str]:
    if not prop:
        return []
    ptype = prop.get("type")
    if ptype == "multi_select":
        return [str(x.get("name")).strip() for x in (prop.get("multi_select") or []) if x.get("name")]
    if ptype == "select" and (prop.get("select") or {}).get("name"):
        return [str(prop["select"]["name"]).strip()]
    if ptype == "rich_text":
        raw = _extract_rich_text(prop)
        return [s.strip() for s in re.split(r"[,，、\s]+", raw) if s.strip()]
    return []


def _extract_category(prop: dict[str, Any] | None) -> str:
    if not prop:
        return ""
    ptype = prop.get("type")
    if ptype == "select" and (prop.get("select") or {}).get("name"):
        return str(prop["select"]["name"]).strip()
    if ptype == "rich_text":
        return _extract_rich_text(prop)
    return ""


def _extract_icon(prop: dict[str, Any] | None) -> str:
    if not prop:
        return ""
    ptype = prop.get("type")
    if ptype == "phone_number" and prop.get("phone_number"):
        return str(prop["phone_number"]).strip()
    if ptype == "url" and prop.get("url"):
        return str(prop["url"]).strip()
    if ptype == "rich_text":
        return _extract_rich_text(prop)
    return ""


def _extract_number(prop: dict[str, Any] | None) -> int:
    if prop and prop.get("type") == "number" and isinstance(prop.get("number"), (int, float)):
        return int(prop["number"])
    return 0


def _extract_checkbox(prop: dict[str, Any] | None) -> bool:
    if not prop:
        return False
    ptype = prop.get("type")
    if ptype == "checkbox":
        return bool(prop.get("checkbox"))
    if ptype == "select" and prop.get("select"):
        return str(prop["select"].get("name") or "") in {"置顶", "Yes", "true", "True"}
    return False


def transform_page(page: dict[str, Any]) -> dict[str, Any]:
    """将 Notion Page 对象转换为与 nav-notion-lime 一致的书签结构。"""
    props = page.get("properties") or {}
    raw_category = _extract_category(_find_prop(props, "category"))
    tags = _extract_tags(_find_prop(props, "tags"))
    merged_tags = [raw_category, *tags] if (raw_category and raw_category not in tags) else tags
    primary_category = raw_category or (merged_tags[0] if merged_tags else "")
    priority = _extract_number(_find_prop(props, "priority"))
    pinned = _extract_checkbox(_find_prop(props, "pinned"))

    return {
        "id": str(page.get("id") or ""),
        "notionUrl": str(page.get("url") or ""),
        "title": _extract_title(_find_prop(props, "title")),
        "url": _extract_url(_find_prop(props, "url")),
        "description": _extract_rich_text(_find_prop(props, "description")),
        "tags": merged_tags,
        "category": primary_category,
        "icon": _extract_icon(_find_prop(props, "icon")),
        "priority": priority,
        "pinned": bool(pinned or priority > 0),
        "createdTime": str(page.get("created_time") or ""),
        "lastEditedTime": str(page.get("last_edited_time") or ""),
    }


def sort_bookmarks(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """排序规则与 nav-notion-lime 一致：置顶优先 -> 优先级降序 -> 标题升序。"""
    return sorted(
        items,
        key=lambda x: (
            0 if x.get("pinned") else 1,
            -int(x.get("priority") or 0),
            str(x.get("title") or "").lower(),
        ),
    )


def build_notion_properties(
    payload: dict[str, Any],
    schema_map: dict[str, tuple[str, str]],
    is_update: bool = False,
) -> dict[str, Any]:
    """根据数据库 schema 构造 Notion API properties 对象（兼容 nav-notion-lime 默认列）。"""
    props: dict[str, Any] = {}

    title_name, _ = schema_map.get("title", ("name", "title"))
    url_name, url_type = schema_map.get("url", ("url", "rich_text"))

    if "title" in payload and payload["title"] is not None:
        title_val = str(payload["title"]).strip()
        props[title_name] = {"title": [{"type": "text", "text": {"content": title_val}}]}
    elif not is_update:
        raise ValueError("title 为必填字段")

    if "url" in payload and payload["url"] is not None:
        url_val = str(payload["url"]).strip()
        if url_type == "url":
            props[url_name] = {"url": url_val or None}
        else:
            props[url_name] = {
                "rich_text": [{"type": "text", "text": {"content": url_val, "link": {"url": url_val}}}]
                if url_val
                else []
            }
    elif not is_update:
        raise ValueError("url 为必填字段")

    if "description" in payload and (not is_update or payload["description"] is not None):
        if not schema_map or "description" in schema_map:
            desc_name, _ = schema_map.get("description", ("description", "rich_text"))
            desc = str(payload.get("description") or "")
            props[desc_name] = {"rich_text": [{"type": "text", "text": {"content": desc[:1900]}}] if desc else []}

    if "tags" in payload and payload["tags"] is not None:
        if not schema_map or "tags" in schema_map:
            tag_name, tag_type = schema_map.get("tags", ("tag", "multi_select"))
            tags = [str(t).strip() for t in payload["tags"] if str(t).strip()]
            if tag_type == "select":
                props[tag_name] = {"select": {"name": tags[0]} if tags else None}
            elif tag_type == "rich_text":
                joined = ", ".join(tags)
                props[tag_name] = {"rich_text": [{"type": "text", "text": {"content": joined}}] if joined else []}
            else:
                props[tag_name] = {"multi_select": [{"name": t} for t in tags]}

    if "category" in payload and payload["category"] is not None and "category" in schema_map:
        cat_name, cat_type = schema_map["category"]
        cat_val = str(payload["category"]).strip()
        if cat_type == "select":
            props[cat_name] = {"select": {"name": cat_val} if cat_val else None}
        elif cat_type == "rich_text":
            props[cat_name] = {"rich_text": [{"type": "text", "text": {"content": cat_val}}] if cat_val else []}

    if "icon" in payload and payload["icon"] is not None and (not schema_map or "icon" in schema_map):
        icon_name, icon_type = schema_map.get("icon", ("icon", "phone_number"))
        icon_val = str(payload["icon"]).strip()
        if icon_type == "url":
            props[icon_name] = {"url": icon_val or None}
        elif icon_type == "rich_text":
            props[icon_name] = {"rich_text": [{"type": "text", "text": {"content": icon_val}}] if icon_val else []}
        else:
            props[icon_name] = {"phone_number": icon_val or None}

    if "priority" in payload and payload["priority"] is not None and "priority" in schema_map:
        prio_name, prio_type = schema_map["priority"]
        if prio_type == "number":
            props[prio_name] = {"number": int(payload["priority"])}

    if "pinned" in payload and payload["pinned"] is not None and "pinned" in schema_map:
        pin_name, pin_type = schema_map["pinned"]
        pin_bool = bool(payload["pinned"])
        if pin_type == "checkbox":
            props[pin_name] = {"checkbox": pin_bool}
        elif pin_type == "select":
            props[pin_name] = {"select": {"name": "置顶"} if pin_bool else None}

    return props


def _cache_file(database_id: str) -> Path:
    custom_dir = os.environ.get("LUMAKEY_NOTION_CACHE_DIR", "").strip()
    if custom_dir:
        cache_dir = Path(custom_dir)
    elif data_dir := os.environ.get("LUMAKEY_DATA_DIR", "").strip():
        cache_dir = Path(data_dir) / "cache"
    else:
        cache_dir = Path.home() / "Library" / "Caches" / "Lumakey" / "notion-bookmarks"
    cache_dir.mkdir(parents=True, exist_ok=True)
    safe_db = re.sub(r"[^a-zA-Z0-9_-]", "", database_id) or "default"
    return cache_dir / f"{safe_db}.json"


def load_cache(database_id: str, ttl_seconds: int) -> dict[str, Any] | None:
    if ttl_seconds <= 0:
        return None
    path = _cache_file(database_id)
    if not path.exists():
        return None
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        age = time.time() - float(data.get("fetchedAt") or 0)
        if age <= ttl_seconds and isinstance(data.get("items"), list):
            return data
    except Exception:
        return None
    return None


def load_cache_raw(database_id: str) -> dict[str, Any] | None:
    path = _cache_file(database_id)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def save_cache(database_id: str, db_title: str, schema_map: dict[str, tuple[str, str]], items: list[dict[str, Any]]) -> None:
    sorted_items = sort_bookmarks(items)
    path = _cache_file(database_id)
    payload = {
        "fetchedAt": time.time(),
        "dbTitle": db_title,
        "schema": {k: [v[0], v[1]] for k, v in schema_map.items()},
        "items": sorted_items,
    }
    path.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
    export_search_index(sorted_items)


def export_search_index(items: list[dict[str, Any]]) -> None:
    """导出 search-index.json 供 Lumakey 主搜索栏免前缀直搜（0 子进程开销）。"""
    override = os.environ.get("LUMAKEY_PLUGIN_INDEX_PATH", "").strip()
    if override:
        index_path = Path(override)
    elif data_dir := os.environ.get("LUMAKEY_DATA_DIR", "").strip():
        index_path = Path(data_dir) / "search-index.json"
    else:
        index_path = Path(__file__).resolve().parent / "search-index.json"
    index_path.parent.mkdir(parents=True, exist_ok=True)
    entries: list[dict[str, Any]] = []
    for bm in items[:400]:
        url_val = str(bm.get("url") or "").strip()
        tags = [str(t) for t in (bm.get("tags") or []) if str(t).strip()]
        domain = (urllib.parse.urlparse(url_val).hostname or "").removeprefix("www.")
        desc = str(bm.get("description") or "").strip()
        tag_str = " ".join(f"#{t}" for t in tags[:3])
        subtitle = " · ".join(p for p in (domain, tag_str, desc[:80]) if p)
        entries.append(
            {
                "id": bm.get("id") or "",
                "title": bm.get("title") or "Untitled",
                "subtitle": subtitle,
                "url": url_val if url_val.startswith(("http://", "https://")) else None,
                "copyText": url_val or bm.get("title") or "",
                "icon": "pin.fill" if bm.get("pinned") else "bookmark.fill",
                "badge": (tags[0] if tags else ("置顶" if bm.get("pinned") else "书签"))[:16],
                "tags": tags,
                "pinned": bool(bm.get("pinned")),
                "priority": int(bm.get("priority") or 0),
                "commandArgs": ["--detail", bm["id"]] if bm.get("id") else None,
            }
        )
    tmp_path = index_path.with_suffix(".json.tmp")
    tmp_path.write_text(json.dumps({"version": 1, "items": entries}, ensure_ascii=False), encoding="utf-8")
    tmp_path.replace(index_path)


def _schema_from_cache(raw: dict[str, Any] | None) -> dict[str, tuple[str, str]]:
    if not raw or not isinstance(raw.get("schema"), dict):
        return {}
    out: dict[str, tuple[str, str]] = {}
    for k, v in raw["schema"].items():
        if isinstance(v, list) and len(v) == 2:
            out[str(k)] = (str(v[0]), str(v[1]))
    return out


def sync_bookmarks(client: NotionClient, ttl_seconds: int, force: bool = False) -> tuple[str, dict[str, tuple[str, str]], list[dict[str, Any]], str]:
    """读取或刷新书签列表，返回 (db_title, schema_map, items, cache_label)。"""
    if not force:
        cached = load_cache(client.database_id, ttl_seconds)
        if cached is not None:
            age = max(0, int(time.time() - float(cached.get("fetchedAt") or 0)))
            return (
                str(cached.get("dbTitle") or "Notion 书签库"),
                _schema_from_cache(cached),
                list(cached.get("items") or []),
                f"缓存 ({age}s 前)",
            )

    db_title, schema_map = client.retrieve_database_info()
    items = client.query_all_bookmarks()
    save_cache(client.database_id, db_title, schema_map, items)
    return db_title, schema_map, items, "刚刚实时同步"


def ensure_schema(client: NotionClient, items: list[dict[str, Any]]) -> tuple[str, dict[str, tuple[str, str]]]:
    cached = load_cache_raw(client.database_id)
    schema = _schema_from_cache(cached)
    db_title = str((cached or {}).get("dbTitle") or "Notion 书签库")
    if schema:
        return db_title, schema
    db_title, schema = client.retrieve_database_info()
    if cached and isinstance(cached.get("items"), list):
        save_cache(client.database_id, db_title, schema, cached["items"])
    return db_title, schema


def emit_view(
    title: str,
    subtitle: str = "",
    badge: str = "NOTION",
    metrics: list[dict[str, str]] | None = None,
    items: list[dict[str, Any]] | None = None,
    markdown: str = "",
    effect: dict[str, Any] | None = None,
) -> int:
    payload: dict[str, Any] = {"schemaVersion": 2, "title": title, "badge": badge}
    if subtitle:
        payload["subtitle"] = subtitle
    if metrics:
        payload["metrics"] = metrics
    if items:
        payload["items"] = items
    if markdown:
        payload["markdown"] = markdown
    if effect:
        payload["effect"] = effect
    print(json.dumps(payload, ensure_ascii=False))
    return 0


def format_bookmark_item(bm: dict[str, Any], include_manage: bool = True) -> dict[str, Any]:
    tags = bm.get("tags") or []
    tag_text = " ".join(f"#{t}" for t in tags[:3])
    domain = urllib.parse.urlparse(bm.get("url") or "").hostname or ""
    domain = domain.removeprefix("www.")
    desc = (bm.get("description") or "").strip()
    sub_parts = [p for p in [domain, tag_text, desc[:60]] if p]
    item: dict[str, Any] = {
        "id": bm.get("id") or "",
        "title": ("📌 " if bm.get("pinned") else "") + (bm.get("title") or "Untitled")[:80],
        "subtitle": " · ".join(sub_parts) or (bm.get("url") or ""),
        "icon": "pin.fill" if bm.get("pinned") else "bookmark.fill",
        "badge": (tags[0] if tags else ("置顶" if bm.get("pinned") else "LINK"))[:16],
        "copyText": bm.get("url") or bm.get("title") or "",
    }
    if bm.get("url") and bm["url"].startswith(("http://", "https://")):
        item["openURL"] = bm["url"]
    if include_manage and bm.get("id"):
        item["commandArgs"] = ["--detail", bm["id"]]
    return item


def filter_bookmarks(items: list[dict[str, Any]], query: str) -> list[dict[str, Any]]:
    q = query.strip()
    if not q:
        return items
    tokens = [t.strip() for t in q.split() if t.strip()]
    results = items
    for tok in tokens:
        if tok.startswith("#") and len(tok) > 1:
            tag_q = tok[1:].lower()
            results = [
                bm
                for bm in results
                if any(tag_q in str(t).lower() for t in (bm.get("tags") or []))
                or tag_q in str(bm.get("category") or "").lower()
            ]
        else:
            kw = tok.lower()
            results = [
                bm
                for bm in results
                if kw in str(bm.get("title") or "").lower()
                or kw in str(bm.get("url") or "").lower()
                or kw in str(bm.get("description") or "").lower()
                or any(kw in str(t).lower() for t in (bm.get("tags") or []))
            ]
    return results


def parse_add_query(rest: str, clipboard_url: str, default_tags: list[str]) -> tuple[str, str, list[str]]:
    tokens = rest.split()
    tags: list[str] = []
    non_tags: list[str] = []
    for tok in tokens:
        if tok.startswith("#") and len(tok) > 1:
            tags.append(tok[1:])
        else:
            non_tags.append(tok)

    url_val = ""
    title_parts: list[str] = []
    for tok in non_tags:
        if not url_val and (URL_RE.match(tok) or ("." in tok and "/" not in tok[:1] and " " not in tok)):
            url_val = normalize_target_url(tok)
        else:
            title_parts.append(tok)

    if not url_val and clipboard_url:
        url_val = clipboard_url
    final_tags = tags if tags else default_tags
    return url_val, " ".join(title_parts).strip(), final_tags


def parse_edit_query(rest: str) -> tuple[str, dict[str, Any]]:
    try:
        tokens = shlex.split(rest)
    except ValueError:
        tokens = rest.split()
    updates: dict[str, Any] = {}
    target_parts: list[str] = []
    for tok in tokens:
        if "=" in tok and not tok.startswith("="):
            k, v = tok.split("=", 1)
            kl = k.strip().lower()
            if kl in {"title", "name", "标题", "名称"}:
                updates["title"] = v
            elif kl in {"url", "link", "链接"}:
                updates["url"] = normalize_target_url(v)
            elif kl in {"desc", "description", "描述", "说明"}:
                updates["description"] = v
            elif kl in {"tags", "tag", "标签"}:
                updates["tags"] = parse_tags_csv(v)
            elif kl in {"pin", "pinned", "置顶"}:
                updates["pinned"] = is_truthy(v)
            elif kl in {"priority", "prio", "优先级"}:
                updates["priority"] = safe_int(v, 0)
            else:
                target_parts.append(tok)
        else:
            target_parts.append(tok)
    return " ".join(target_parts).strip(), updates


def find_bookmark_target(items: list[dict[str, Any]], needle: str) -> dict[str, Any] | None:
    clean = needle.strip().lower()
    if not clean:
        return None
    for bm in items:
        if bm.get("id", "").lower() == clean or bm.get("id", "").replace("-", "").lower() == clean.replace("-", ""):
            return bm
    for bm in items:
        if str(bm.get("title") or "").lower() == clean:
            return bm
    hits = filter_bookmarks(items, needle)
    return hits[0] if hits else None


def handle_add_bookmark(
    client: NotionClient,
    url_val: str,
    explicit_title: str,
    tags: list[str],
    auto_fetch: bool,
    ttl_seconds: int,
) -> int:
    if not url_val:
        return emit_view(
            title="未检测到可收藏链接",
            subtitle="请在命令中附带网址，或先复制网页链接到剪贴板",
            badge="ADD",
            items=[
                {
                    "title": "用法：bm add https://example.com [自定义标题] [#标签]",
                    "subtitle": "也可先复制链接，再输入 bm 点击「一键收藏剪贴板链接」",
                    "icon": "link.badge.plus",
                    "copyText": "bm add https://example.com #常用",
                },
                {"title": "返回书签列表", "icon": "arrow.uturn.backward", "commandArgs": ["--list"]},
            ],
        )

    db_title, schema_map, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
    meta = fetch_url_metadata(url_val) if auto_fetch else {"title": "", "description": ""}
    title = explicit_title or meta["title"] or urllib.parse.urlparse(url_val).hostname or url_val
    desc = meta["description"]

    created = client.create_bookmark(
        {
            "title": title,
            "url": url_val,
            "description": desc,
            "tags": tags,
            "pinned": False,
            "priority": 0,
        },
        schema_map,
    )
    items = [bm for bm in items if bm.get("id") != created.get("id")]
    items.insert(0, created)
    save_cache(client.database_id, db_title, schema_map, items)

    view_items: list[dict[str, Any]] = [
        {
            "title": created["title"],
            "subtitle": created["url"],
            "icon": "checkmark.circle.fill",
            "badge": "已入库",
            "openURL": created["url"],
            "copyText": created["url"],
            "commandArgs": ["--detail", created["id"]],
        },
        {
            "title": "置顶此书签",
            "subtitle": "同步写入 Notion 置顶状态（Nav-Notion-Lime Dock 可见）",
            "icon": "pin.fill",
            "commandArgs": ["--set-pin", created["id"], "true"],
        },
        {"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]},
    ]
    if created.get("notionUrl"):
        view_items.append(
            {
                "title": "在 Notion 中查看页面",
                "subtitle": created["notionUrl"],
                "icon": "doc.text",
                "openURL": created["notionUrl"],
            }
        )
    return emit_view(
        title="已收藏到 Notion 书签库",
        subtitle=f"{db_title} · 标签：{', '.join(tags) if tags else '无'}",
        badge="SAVED",
        metrics=[
            {"key": "标题", "value": created["title"][:28]},
            {"key": "总书签数", "value": str(len(items))},
        ],
        items=view_items,
    )


def handle_detail_view(client: NotionClient, page_id: str, ttl_seconds: int, notice: str = "") -> int:
    db_title, _, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
    bm = find_bookmark_target(items, page_id)
    if not bm:
        db_title, _, items, _ = sync_bookmarks(client, ttl_seconds, force=True)
        bm = find_bookmark_target(items, page_id)
    if not bm:
        return emit_view(
            title="未找到该书签",
            subtitle="可能已被归档或移除",
            badge="404",
            items=[{"title": "刷新并回到书签列表", "icon": "arrow.clockwise", "commandArgs": ["--refresh"]}],
        )

    is_pinned = bool(bm.get("pinned"))
    prio = int(bm.get("priority") or 0)
    next_prio = prio + 10
    detail_items: list[dict[str, Any]] = []
    if bm.get("url"):
        detail_items.append(
            {
                "title": "在浏览器打开",
                "subtitle": bm["url"],
                "icon": "safari",
                "badge": "OPEN",
                "openURL": bm["url"],
                "copyText": bm["url"],
            }
        )
    detail_items.append(
        {
            "title": "取消置顶" if is_pinned else "设为置顶",
            "subtitle": "更新 Notion pinned / 置顶字段",
            "icon": "pin.slash" if is_pinned else "pin.fill",
            "badge": "PIN",
            "commandArgs": ["--set-pin", bm["id"], "false" if is_pinned else "true"],
        }
    )
    detail_items.append(
        {
            "title": f"提高优先级 ({prio} → {next_prio})",
            "subtitle": "调整 priority 排序权重",
            "icon": "arrow.up.circle",
            "badge": "PRIO",
            "commandArgs": ["--set-priority", bm["id"], str(next_prio)],
        }
    )
    detail_items.append(
        {
            "id": f"edit-form-{bm['id']}",
            "title": "表单修改标题、标签或说明",
            "subtitle": "通过原生表单直接提交到 Notion 数据库",
            "icon": "pencil.line",
            "actions": [
                {
                    "id": "edit-form",
                    "label": "编辑字段",
                    "style": "primary",
                    "commandArgs": ["--edit-form", bm["id"]],
                    "promptFields": [
                        {"key": "title", "label": "标题", "type": "text", "defaultValue": bm.get("title") or "", "required": True},
                        {"key": "tags", "label": "标签（逗号分隔）", "type": "text", "defaultValue": ", ".join(bm.get("tags") or [])},
                        {"key": "description", "label": "说明描述", "type": "text", "defaultValue": bm.get("description") or ""},
                    ],
                }
            ],
        }
    )
    if bm.get("notionUrl"):
        detail_items.append(
            {
                "title": "在 Notion 中编辑字段",
                "subtitle": "直达 Notion 原页面修改标题、标签与说明",
                "icon": "square.and.pencil",
                "openURL": bm["notionUrl"],
            }
        )
    detail_items.append(
        {
            "id": f"archive-{bm['id']}",
            "title": "归档删除此书签",
            "subtitle": "在 Notion 中设为 archived=true（可在废纸篓恢复）",
            "icon": "trash",
            "badge": "DEL",
            "actions": [
                {
                    "id": "confirm-archive",
                    "label": "归档删除",
                    "style": "destructive",
                    "commandArgs": ["--archive", bm["id"]],
                    "confirmMessage": f"确认将「{bm.get('title') or bm['id']}」移入 Notion 废纸篓？",
                }
            ],
        }
    )
    detail_items.append({"title": "返回书签列表", "icon": "arrow.uturn.backward", "commandArgs": ["--list"]})

    tags_str = ", ".join(bm.get("tags") or []) or "无标签"
    return emit_view(
        title=bm["title"],
        subtitle=notice or f"{db_title} · {bm.get('url') or ''}",
        badge="PINNED" if is_pinned else "BOOKMARK",
        metrics=[
            {"key": "置顶状态", "value": "已置顶" if is_pinned else "普通"},
            {"key": "优先级", "value": str(prio)},
            {"key": "标签", "value": tags_str[:24]},
        ],
        items=detail_items,
        markdown=bm.get("description") or "",
        effect={"reloadSearchIndex": True, "toast": notice} if notice else None,
    )


def handle_update_fields(
    client: NotionClient,
    page_id: str,
    updates: dict[str, Any],
    ttl_seconds: int,
    show_detail: bool = True,
) -> int:
    db_title, schema_map, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
    if not schema_map:
        db_title, schema_map = ensure_schema(client, items)

    updated = client.update_bookmark(page_id, updates, schema_map)
    new_items = [updated if bm.get("id") == page_id else bm for bm in items]
    if all(bm.get("id") != page_id for bm in new_items):
        new_items.append(updated)
    save_cache(client.database_id, db_title, schema_map, new_items)

    if show_detail:
        return handle_detail_view(client, page_id, ttl_seconds, notice="✅ 已同步更新到 Notion")
    return emit_view(
        title="书签已更新",
        subtitle=updated["title"],
        badge="UPDATED",
        items=[
            format_bookmark_item(updated),
            {"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]},
        ],
    )


def handle_archive_bookmark(client: NotionClient, page_id: str, ttl_seconds: int) -> int:
    db_title, schema_map, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
    target = find_bookmark_target(items, page_id)
    client.archive_bookmark(page_id)
    remaining = [bm for bm in items if bm.get("id") != page_id]
    save_cache(client.database_id, db_title, schema_map, remaining)
    return emit_view(
        title="已归档书签",
        subtitle=f"已将「{(target or {}).get('title', page_id)}」移入 Notion 废纸篓",
        badge="ARCHIVED",
        metrics=[{"key": "剩余书签", "value": str(len(remaining))}],
        items=[{"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]}],
    )


def handle_list_view(
    client: NotionClient,
    query: str,
    clipboard_url: str,
    max_items: int,
    ttl_seconds: int,
    force_refresh: bool = False,
) -> int:
    db_title, _, items, sync_status = sync_bookmarks(client, ttl_seconds, force=force_refresh)
    filtered = filter_bookmarks(items, query)
    pinned_count = sum(1 for x in items if x.get("pinned"))

    view_items: list[dict[str, Any]] = []
    if not query.strip():
        view_items.append(
            {
                "id": "add-bookmark-form",
                "title": "➕ 新增书签到 Notion",
                "subtitle": "弹窗填写网址、标题与标签（支持自动抓取网页元数据）",
                "icon": "plus.app.fill",
                "badge": "NEW",
                "actions": [
                    {
                        "id": "add-form",
                        "label": "填写表单",
                        "style": "primary",
                        "commandArgs": ["--add-form"],
                        "promptFields": [
                            {"key": "url", "label": "网页链接 URL", "type": "text", "placeholder": "https://...", "defaultValue": clipboard_url, "required": True},
                            {"key": "title", "label": "标题（留空则自动抓取）", "type": "text", "placeholder": "可选"},
                            {"key": "tags", "label": "标签（逗号分隔）", "type": "text", "defaultValue": "书签"},
                        ],
                    }
                ],
            }
        )
    if clipboard_url and not query.strip():
        view_items.append(
            {
                "title": f"⭐ 一键收藏剪贴板链接",
                "subtitle": clipboard_url,
                "icon": "plus.circle.fill",
                "badge": "CLIPBOARD",
                "copyText": clipboard_url,
                "commandArgs": ["--add-clipboard"],
            }
        )

    for bm in filtered[:max_items]:
        view_items.append(format_bookmark_item(bm))

    if not filtered:
        view_items.append(
            {
                "title": "未匹配到相关书签" if query.strip() else "书签库暂无数据",
                "subtitle": "可输入 bm add <网址> 新增，或点击下方强制刷新 Notion 缓存",
                "icon": "tray",
            }
        )

    view_items.append(
        {
            "title": "强制刷新 Notion 书签缓存",
            "subtitle": f"当前数据源状态：{sync_status}",
            "icon": "arrow.clockwise",
            "badge": "SYNC",
            "commandArgs": ["--refresh"],
        }
    )

    subtitle = f"{db_title} · {sync_status}"
    if query.strip():
        subtitle = f"筛选「{query.strip()}」命中 {len(filtered)} / {len(items)} 条 · {sync_status}"

    return emit_view(
        title="Notion 书签收藏",
        subtitle=subtitle,
        badge="BOOKMARKS",
        metrics=[
            {"key": "总书签", "value": str(len(items))},
            {"key": "已置顶", "value": str(pinned_count)},
            {"key": "当前展示", "value": f"{min(len(filtered), max_items)}/{len(filtered)}"},
        ],
        items=view_items,
    )


def handle_config_missing(has_token: bool, has_db: bool, clipboard_url: str) -> int:
    missing = []
    if not has_token:
        missing.append("Notion Secret Token (`notionToken`)")
    if not has_db:
        missing.append("Notion Database ID (`databaseId`)")
    items: list[dict[str, Any]] = [
        {
            "title": "打开 Lumakey 插件设置填写凭证",
            "subtitle": "填入 Token 与 Database ID 后点击「保存配置」即可使用",
            "icon": "gearshape.fill",
            "badge": "SETUP",
            "openURL": "lumakey://settings/plugins",
        },
        {
            "title": "获取 Notion Integration Token",
            "subtitle": "https://www.notion.so/my-integrations",
            "icon": "key.fill",
            "openURL": "https://www.notion.so/my-integrations",
            "copyText": "https://www.notion.so/my-integrations",
        },
    ]
    if clipboard_url:
        items.append(
            {
                "title": "已检测到剪贴板链接（配置完成后可一键收藏）",
                "subtitle": clipboard_url,
                "icon": "link",
                "copyText": clipboard_url,
            }
        )
    return emit_view(
        title="Notion 书签插件尚未配置",
        subtitle=f"缺少：{'、'.join(missing)}",
        badge="SETUP",
        items=items,
        markdown="兼容 `nav-notion-lime` 数据库字段（`name`、`url`、`description`、`tag`、`priority`、`pinned`），记得在 Notion 数据库右上角 `... -> Connect to` 授权你的 Integration。",
    )


def _extract_input_json(argv: list[str]) -> tuple[list[str], dict[str, Any]]:
    cleaned: list[str] = []
    form_data: dict[str, Any] = {}
    i = 0
    while i < len(argv):
        if argv[i] == "--input-json" and i + 1 < len(argv):
            try:
                parsed = json.loads(argv[i + 1])
                if isinstance(parsed, dict):
                    form_data = parsed
            except Exception:
                pass
            i += 2
            continue
        cleaned.append(argv[i])
        i += 1
    return cleaned, form_data


def dispatch(stdin_payload: dict[str, Any], argv: list[str]) -> int:
    data_dir = str(stdin_payload.get("dataDir") or "").strip()
    if data_dir and not os.environ.get("LUMAKEY_DATA_DIR"):
        os.environ["LUMAKEY_DATA_DIR"] = data_dir
    argv, form_data = _extract_input_json(argv)

    cfg = stdin_payload.get("config") or {}
    query = str(stdin_payload.get("query") or "").strip()
    clipboard_raw = str(stdin_payload.get("clipboard") or "")
    clipboard_url = extract_first_url(clipboard_raw)

    token = str(cfg.get("notionToken") or os.environ.get("NOTION_TOKEN") or "").strip()
    raw_db_id = str(cfg.get("databaseId") or os.environ.get("NOTION_DATABASE_ID") or "").strip()
    database_id = normalize_database_id(raw_db_id)

    if not token or not database_id:
        return handle_config_missing(bool(token), bool(database_id), clipboard_url)

    default_tags = parse_tags_csv(str(cfg.get("defaultTags") or "书签"))
    auto_fetch = is_truthy(cfg.get("autoFetchMeta", "true"))
    ttl_seconds = max(0, safe_int(cfg.get("cacheTtlSeconds"), 120))
    max_items = min(30, max(1, safe_int(cfg.get("maxItems"), 15)))
    client = NotionClient(token=token, database_id=database_id)

    # 1. 优先响应 Lumakey View Card 的 commandArgs / actions 交互按钮
    if argv:
        cmd = argv[0]
        if cmd == "--refresh":
            return handle_list_view(client, "", clipboard_url, max_items, ttl_seconds, force_refresh=True)
        if cmd == "--list":
            return handle_list_view(client, "", clipboard_url, max_items, ttl_seconds, force_refresh=False)
        if cmd == "--add-clipboard":
            return handle_add_bookmark(client, clipboard_url, "", default_tags, auto_fetch, ttl_seconds)
        if cmd == "--add-form":
            form_url = normalize_target_url(str(form_data.get("url") or ""))
            form_title = str(form_data.get("title") or "").strip()
            form_tags = parse_tags_csv(str(form_data.get("tags") or "")) or default_tags
            return handle_add_bookmark(client, form_url, form_title, form_tags, auto_fetch, ttl_seconds)
        if cmd == "--edit-form" and len(argv) >= 2:
            updates: dict[str, Any] = {}
            if t_val := str(form_data.get("title") or "").strip():
                updates["title"] = t_val
            if "description" in form_data:
                updates["description"] = str(form_data.get("description") or "").strip()
            if "tags" in form_data:
                updates["tags"] = parse_tags_csv(str(form_data.get("tags") or ""))
            return handle_update_fields(client, argv[1], updates, ttl_seconds, show_detail=True)
        if cmd == "--detail" and len(argv) >= 2:
            return handle_detail_view(client, argv[1], ttl_seconds)
        if cmd == "--set-pin" and len(argv) >= 3:
            return handle_update_fields(client, argv[1], {"pinned": is_truthy(argv[2])}, ttl_seconds, show_detail=True)
        if cmd == "--set-priority" and len(argv) >= 3:
            return handle_update_fields(
                client, argv[1], {"priority": safe_int(argv[2], 0)}, ttl_seconds, show_detail=True
            )
        if cmd == "--archive" and len(argv) >= 2:
            return handle_archive_bookmark(client, argv[1], ttl_seconds)

    # 2. 解析搜索框查询指令 (add / edit / pin / unpin / del / refresh / 搜索)
    lower = query.lower()
    if lower in {"refresh", "sync", "刷新"}:
        return handle_list_view(client, "", clipboard_url, max_items, ttl_seconds, force_refresh=True)

    for prefix in ("add ", "+ ", "save ", "收藏 "):
        if lower.startswith(prefix) or lower == prefix.strip():
            rest = query[len(prefix.strip()):].strip()
            url_val, explicit_title, tags = parse_add_query(rest, clipboard_url, default_tags)
            return handle_add_bookmark(client, url_val, explicit_title, tags, auto_fetch, ttl_seconds)

    if lower.startswith("edit ") or lower.startswith("修改 "):
        rest = query.split(None, 1)[1] if " " in query else ""
        target_q, updates = parse_edit_query(rest)
        _, _, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
        target = find_bookmark_target(items, target_q)
        if not target or not updates:
            return emit_view(
                title="编辑指令参数不足或未命中书签",
                subtitle="用法：bm edit <书签标题或ID> title=... desc=... tags=a,b pin=true priority=10",
                badge="EDIT",
                items=[{"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]}],
            )
        return handle_update_fields(client, target["id"], updates, ttl_seconds, show_detail=False)

    for prefix, pin_val in (("pin ", True), ("置顶 ", True), ("unpin ", False), ("取消置顶 ", False)):
        if lower.startswith(prefix):
            needle = query[len(prefix):].strip()
            _, _, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
            target = find_bookmark_target(items, needle)
            if not target:
                return emit_view(
                    title=f"未找到匹配「{needle}」的书签",
                    badge="404",
                    items=[{"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]}],
                )
            return handle_update_fields(client, target["id"], {"pinned": pin_val}, ttl_seconds, show_detail=False)

    for prefix in ("del ", "rm ", "delete ", "删除 "):
        if lower.startswith(prefix):
            needle = query[len(prefix):].strip()
            _, _, items, _ = sync_bookmarks(client, ttl_seconds, force=False)
            target = find_bookmark_target(items, needle)
            if not target:
                return emit_view(
                    title=f"未找到匹配「{needle}」的书签",
                    badge="404",
                    items=[{"title": "返回书签列表", "icon": "list.bullet", "commandArgs": ["--list"]}],
                )
            return handle_archive_bookmark(client, target["id"], ttl_seconds)

    return handle_list_view(client, query, clipboard_url, max_items, ttl_seconds, force_refresh=False)


def main() -> int:
    raw_stdin = sys.stdin.read()
    try:
        stdin_payload = json.loads(raw_stdin) if raw_stdin.strip() else {}
    except json.JSONDecodeError:
        stdin_payload = {"query": raw_stdin.strip()}

    try:
        return dispatch(stdin_payload, sys.argv[1:])
    except NotionAPIError as exc:
        hint = "请检查 Notion Token 与 Database ID 是否正确，并确认数据库已 Connect 到你的 Integration。"
        if exc.status == 401:
            hint = "Notion Token 无效或已过期，请在插件中心更新。"
        elif exc.status == 404:
            hint = "未找到对应数据库，请确认 Database ID 且已在 Notion 页面右上角 ... -> Connect to 授权。"
        return emit_view(
            title=f"Notion API 请求失败 ({exc.status})",
            subtitle=exc.message[:120],
            badge="ERROR",
            items=[
                {
                    "title": "打开 Lumakey 插件设置检查凭证",
                    "subtitle": hint,
                    "icon": "gearshape.fill",
                    "openURL": "lumakey://settings/plugins",
                },
                {"title": "重试刷新", "icon": "arrow.clockwise", "commandArgs": ["--refresh"]},
            ],
        )
    except Exception as exc:
        return emit_view(
            title="插件执行异常",
            subtitle=str(exc)[:140],
            badge="ERROR",
            items=[{"title": "返回书签列表", "icon": "arrow.uturn.backward", "commandArgs": ["--list"]}],
        )


if __name__ == "__main__":
    sys.exit(main())
