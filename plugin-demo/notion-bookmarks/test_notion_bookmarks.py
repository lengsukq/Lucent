#!/usr/bin/env python3
"""针对 notion_bookmarks.py 的全流程 Mock HTTP 端到端测试。"""

from __future__ import annotations

import http.server
import json
import os
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from typing import Any

PLUGIN_DIR = Path(__file__).resolve().parent
RUN_SH = PLUGIN_DIR / "run.sh"


class MockState:
    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.db_title = "Lime 书签测试库"
        self.schema_properties: dict[str, Any] = {
            "name": {"id": "title", "type": "title", "title": {}},
            "url": {"id": "url", "type": "rich_text", "rich_text": {}},
            "description": {"id": "desc", "type": "rich_text", "rich_text": {}},
            "tag": {"id": "tag", "type": "multi_select", "multi_select": {"options": []}},
            "priority": {"id": "prio", "type": "number", "number": {}},
            "pinned": {"id": "pin", "type": "checkbox", "checkbox": {}},
        }
        self.pages: list[dict[str, Any]] = [
            {
                "id": "11111111-1111-1111-1111-111111111111",
                "url": "https://www.notion.so/page1",
                "archived": False,
                "created_time": "2026-11-01T00:00:00.000Z",
                "last_edited_time": "2026-11-02T00:00:00.000Z",
                "properties": {
                    "name": {"type": "title", "title": [{"plain_text": "GitHub"}]},
                    "url": {
                        "type": "rich_text",
                        "rich_text": [{"plain_text": "https://github.com", "text": {"link": {"url": "https://github.com"}}}],
                    },
                    "description": {"type": "rich_text", "rich_text": [{"plain_text": "代码托管平台"}]},
                    "tag": {"type": "multi_select", "multi_select": [{"name": "开发"}]},
                    "priority": {"type": "number", "number": 10},
                    "pinned": {"type": "checkbox", "checkbox": True},
                },
            },
            {
                "id": "22222222-2222-2222-2222-222222222222",
                "url": "https://www.notion.so/page2",
                "archived": False,
                "created_time": "2026-11-01T00:00:00.000Z",
                "last_edited_time": "2026-11-02T00:00:00.000Z",
                "properties": {
                    "name": {"type": "title", "title": [{"plain_text": "Apple Developer"}]},
                    "url": {
                        "type": "rich_text",
                        "rich_text": [{"plain_text": "https://developer.apple.com", "text": {"link": {"url": "https://developer.apple.com"}}}],
                    },
                    "description": {"type": "rich_text", "rich_text": [{"plain_text": "Swift 与 macOS 文档"}]},
                    "tag": {"type": "multi_select", "multi_select": [{"name": "文档"}]},
                    "priority": {"type": "number", "number": 0},
                    "pinned": {"type": "checkbox", "checkbox": False},
                },
            },
        ]
        self.query_calls = 0


STATE = MockState()


class MockHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: Any) -> None:
        return

    def _send_json(self, status: int, body: dict[str, Any]) -> None:
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self) -> None:
        if self.path == "/site/sample":
            html = (
                "<html><head>"
                '<meta property="og:title" content="Example AI Hub - 官方网站">'
                '<meta name="description" content="高效率 AI 工具导航站">'
                "</head><body>ok</body></html>"
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
            return

        if self.path.startswith("/v1/databases/"):
            self._send_json(
                200,
                {
                    "object": "database",
                    "title": [{"plain_text": STATE.db_title}],
                    "properties": STATE.schema_properties,
                },
            )
            return

        self._send_json(404, {"code": "object_not_found", "message": "not found"})

    def do_POST(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")

        if self.path.endswith("/query"):
            STATE.query_calls += 1
            self._send_json(200, {"results": STATE.pages, "has_more": False, "next_cursor": None})
            return

        if self.path == "/v1/pages":
            new_id = f"33333333-3333-3333-3333-{len(STATE.pages) + 1:012d}"
            props = body.get("properties") or {}
            page = {
                "id": new_id,
                "url": f"https://www.notion.so/{new_id}",
                "archived": False,
                "created_time": "2026-11-14T12:00:00.000Z",
                "last_edited_time": "2026-11-14T12:00:00.000Z",
                "properties": _hydrate_created_props(props),
            }
            STATE.pages.append(page)
            self._send_json(200, page)
            return

        self._send_json(404, {"code": "object_not_found", "message": "unknown POST"})

    def do_PATCH(self) -> None:
        length = int(self.headers.get("Content-Length") or "0")
        body = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
        page_id = self.path.rsplit("/", 1)[-1]
        for page in STATE.pages:
            if page["id"] == page_id:
                if "archived" in body:
                    page["archived"] = bool(body["archived"])
                if "properties" in body:
                    hydrated = _hydrate_created_props(body["properties"])
                    page["properties"].update(hydrated)
                self._send_json(200, page)
                return
        self._send_json(404, {"code": "object_not_found", "message": "page missing"})


def _hydrate_created_props(props: dict[str, Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for k, v in props.items():
        if "title" in v:
            out[k] = {
                "type": "title",
                "title": [{"plain_text": x["text"]["content"]} for x in v["title"]],
            }
        elif "rich_text" in v:
            out[k] = {
                "type": "rich_text",
                "rich_text": [
                    {
                        "plain_text": x["text"]["content"],
                        "text": x["text"],
                    }
                    for x in v["rich_text"]
                ],
            }
        elif "multi_select" in v:
            out[k] = {"type": "multi_select", "multi_select": v["multi_select"]}
        elif "checkbox" in v:
            out[k] = {"type": "checkbox", "checkbox": v["checkbox"]}
        elif "number" in v:
            out[k] = {"type": "number", "number": v["number"]}
        elif "url" in v:
            out[k] = {"type": "url", "url": v["url"]}
    return out


class NotionBookmarksPluginTests(unittest.TestCase):
    server: http.server.ThreadingHTTPServer
    thread: threading.Thread
    base_url: str
    cache_dir: tempfile.TemporaryDirectory[str]

    @classmethod
    def setUpClass(cls) -> None:
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MockHandler)
        port = cls.server.server_address[1]
        cls.base_url = f"http://127.0.0.1:{port}"
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self) -> None:
        STATE.reset()
        self.cache_dir = tempfile.TemporaryDirectory()

    def tearDown(self) -> None:
        self.cache_dir.cleanup()

    def run_plugin(
        self,
        query: str = "",
        clipboard: str = "",
        args: list[str] | None = None,
        config: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        default_cfg = {
            "notionToken": "ntn_test_secret",
            "databaseId": "https://www.notion.so/ws/0123456789abcdef0123456789abcdef?v=999",
            "defaultTags": "书签,默认",
            "autoFetchMeta": "true",
            "cacheTtlSeconds": "120",
            "maxItems": "15",
        }
        if config is not None:
            default_cfg.update(config)
        stdin_obj = {
            "query": query,
            "mode": "view",
            "config": default_cfg,
            "clipboard": clipboard,
        }
        env = os.environ.copy()
        env["LUMAKEY_NOTION_API_BASE"] = f"{self.base_url}/v1"
        env["LUMAKEY_NOTION_CACHE_DIR"] = self.cache_dir.name
        env["LUMAKEY_PLUGIN_INDEX_PATH"] = str(Path(self.cache_dir.name) / "search-index.json")
        proc = subprocess.run(
            [str(RUN_SH), *(args or [])],
            input=json.dumps(stdin_obj, ensure_ascii=False),
            text=True,
            capture_output=True,
            env=env,
            check=False,
        )
        self.assertEqual(proc.returncode, 0, f"stderr={proc.stderr}")
        return json.loads(proc.stdout)

    def test_missing_config_shows_setup_card(self) -> None:
        out = self.run_plugin(config={"notionToken": "", "databaseId": ""})
        self.assertEqual(out["badge"], "SETUP")
        self.assertEqual(out["items"][0]["openURL"], "lumakey://settings/plugins")

    def test_list_cache_and_search_filter(self) -> None:
        out = self.run_plugin(query="", clipboard="Check https://github.com/lengsukq/Lumakey")
        self.assertEqual(out["badge"], "BOOKMARKS")
        self.assertEqual(STATE.query_calls, 1)
        titles_all = [x["title"] for x in out["items"]]
        self.assertTrue(any("新增书签" in t for t in titles_all))
        self.assertTrue(any("一键收藏剪贴板链接" in t for t in titles_all))
        self.assertTrue(any("📌 GitHub" in t for t in titles_all))

        # 第二次查询应命中本地缓存，不再调用 Notion query API
        filtered = self.run_plugin(query="#文档")
        self.assertEqual(STATE.query_calls, 1)
        titles = [x["title"] for x in filtered["items"]]
        self.assertIn("Apple Developer", titles)
        self.assertNotIn("📌 GitHub", titles)

        # 验证已导出 search-index.json 供 Lumakey 主搜索免前缀检索
        idx_file = Path(self.cache_dir.name) / "search-index.json"
        self.assertTrue(idx_file.exists())
        idx_data = json.loads(idx_file.read_text(encoding="utf-8"))
        self.assertEqual(len(idx_data["items"]), 2)
        self.assertEqual(idx_data["items"][0]["title"], "GitHub")
        self.assertEqual(idx_data["items"][0]["commandArgs"], ["--detail", "11111111-1111-1111-1111-111111111111"])

    def test_add_with_auto_meta_and_clipboard(self) -> None:
        sample_url = f"{self.base_url}/site/sample"
        out = self.run_plugin(query="add #AI工具", clipboard=sample_url)
        self.assertEqual(out["badge"], "SAVED")
        self.assertEqual(out["items"][0]["title"], "Example AI Hub")
        self.assertEqual(out["items"][0]["openURL"], sample_url)

        # 验证缓存已同步新条目，并包含抓取到的描述
        listed = self.run_plugin(query="Example AI Hub")
        self.assertEqual(listed["items"][0]["title"], "Example AI Hub")
        self.assertIn("高效率 AI 工具导航站", listed["items"][0]["subtitle"])

    def test_detail_pin_priority_edit_and_archive(self) -> None:
        target_id = "22222222-2222-2222-2222-222222222222"
        detail = self.run_plugin(args=["--detail", target_id])
        self.assertEqual(detail["badge"], "BOOKMARK")

        pinned = self.run_plugin(args=["--set-pin", target_id, "true"])
        self.assertEqual(pinned["badge"], "PINNED")

        prio = self.run_plugin(args=["--set-priority", target_id, "25"])
        self.assertIn("25", [m["value"] for m in prio["metrics"]])

        edited = self.run_plugin(query='edit "Apple Developer" title="Apple Docs" tags=Swift,macOS')
        self.assertEqual(edited["badge"], "UPDATED")
        self.assertIn("Apple Docs", edited["subtitle"])

        archived = self.run_plugin(args=["--archive", target_id])
        self.assertEqual(archived["badge"], "ARCHIVED")
        listed = self.run_plugin(query="Apple Docs")
        self.assertTrue(any("未匹配" in item["title"] for item in listed["items"]))

    def test_v31_prompt_form_confirm_and_data_dir(self) -> None:
        sample_url = f"{self.base_url}/site/sample"
        form_json = json.dumps({"url": sample_url, "title": "Form Added", "tags": "AI,Nav"})
        added = self.run_plugin(args=["--add-form", "--input-json", form_json])
        self.assertEqual(added["badge"], "SAVED")
        self.assertEqual(added["items"][0]["title"], "Form Added")

        created_id = added["items"][0]["commandArgs"][1]
        detail = self.run_plugin(args=["--detail", created_id])
        archive_item = next(x for x in detail["items"] if x.get("title") == "归档删除此书签")
        self.assertEqual(archive_item["actions"][0]["style"], "destructive")
        self.assertIn("废纸篓", archive_item["actions"][0]["confirmMessage"])

        edit_json = json.dumps({"title": "Form Edited", "tags": "V31", "description": "Updated via sheet"})
        edited = self.run_plugin(args=["--edit-form", created_id, "--input-json", edit_json])
        self.assertEqual(edited["title"], "Form Edited")
        self.assertTrue(edited["effect"]["reloadSearchIndex"])


if __name__ == "__main__":
    unittest.main()
