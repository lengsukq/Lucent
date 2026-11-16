#!/usr/bin/env python3
"""Offline unit tests for `browser-hub` (Edge + Chrome + Safari bookmarks & history)."""

from __future__ import annotations

import datetime as dt
import json
import plistlib
import shutil
import sqlite3
import tempfile
import time
import unittest
from pathlib import Path

import browser_hub as bh

SCH = "https"


def make_url(host: str, path: str = "") -> str:
    return f"{SCH}://{host}{path}"


class BrowserHubTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_root = Path(tempfile.mkdtemp(prefix="lk-bh-test-"))
        self.fake_home = self.tmp_root / "Home"
        self.data_dir = self.tmp_root / "PluginData"
        self._seed_chromium_store(
            self.fake_home / "Library/Application Support/Microsoft Edge",
            profile_dir_name="Profile 1",
            profile_display="Work",
            bm_title="Azure Portal Docs",
            bm_url=make_url("learn.microsoft.com", "/azure"),
            bm_folder="Cloud",
            his_title="Edge Release Notes",
            his_url=make_url("blogs.windows.com", "/msedgedev"),
            visits=9,
        )
        self._seed_chromium_store(
            self.fake_home / "Library/Application Support/Google/Chrome",
            profile_dir_name="Default",
            profile_display="Personal",
            bm_title="Swift Concurrency Guide",
            bm_url=make_url("docs.swift.org", "/concurrency"),
            bm_folder="AppleDev",
            his_title="Azure Portal Docs",
            his_url=make_url("learn.microsoft.com", "/azure"),
            visits=14,
        )
        self._seed_safari_store(self.fake_home / "Library/Safari")

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp_root, ignore_errors=True)

    def _seed_chromium_store(
        self,
        root: Path,
        profile_dir_name: str,
        profile_display: str,
        bm_title: str,
        bm_url: str,
        bm_folder: str,
        his_title: str,
        his_url: str,
        visits: int,
    ) -> None:
        prof = root / profile_dir_name
        prof.mkdir(parents=True, exist_ok=True)
        (root / "Local State").write_text(
            json.dumps({"profile": {"info_cache": {profile_dir_name: {"name": profile_display}}}}),
            encoding="utf-8",
        )
        now_us = int((time.time() + bh.WEBKIT_EPOCH_OFFSET_SEC) * 1_000_000)
        bookmarks_obj = {
            "roots": {
                "bookmark_bar": {
                    "type": "folder",
                    "name": "",
                    "children": [
                        {
                            "type": "folder",
                            "name": bm_folder,
                            "children": [
                                {"type": "url", "name": bm_title, "url": bm_url, "date_added": str(now_us)}
                            ],
                        }
                    ],
                }
            }
        }
        (prof / "Bookmarks").write_text(json.dumps(bookmarks_obj), encoding="utf-8")

        conn = sqlite3.connect(str(prof / "History"))
        try:
            conn.execute("PRAGMA journal_mode = WAL;")
            conn.execute(
                "CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER);"
            )
            conn.execute(
                "INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?, ?, ?, 1, ?, 0);",
                (his_url, his_title, visits, now_us),
            )
            conn.commit()
        finally:
            conn.close()

    def _seed_safari_store(self, safari_root: Path) -> None:
        safari_root.mkdir(parents=True, exist_ok=True)
        plist_data = {
            "WebBookmarkType": "WebBookmarkTypeList",
            "Title": "Root",
            "Children": [
                {
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "BookmarksBar",
                    "Children": [
                        {
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URLString": make_url("developer.apple.com", "/hig"),
                            "URIDictionary": {"title": "Apple Human Interface Guidelines"},
                        }
                    ],
                },
                {
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "Title": "com.apple.ReadingList",
                    "Children": [
                        {
                            "WebBookmarkType": "WebBookmarkTypeLeaf",
                            "URLString": make_url("webkit.org", "/blog"),
                            "URIDictionary": {"title": "WebKit Engineering Blog"},
                            "ReadingList": {"DateAdded": dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)},
                        }
                    ],
                },
            ],
        }
        with (safari_root / "Bookmarks.plist").open("wb") as fp:
            plistlib.dump(plist_data, fp, fmt=plistlib.FMT_BINARY)

        now_cd = time.time() - bh.COREDATA_EPOCH_OFFSET_SEC
        conn = sqlite3.connect(str(safari_root / "History.db"))
        try:
            conn.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER);")
            conn.execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, title TEXT, visit_time REAL);")
            conn.execute(
                "INSERT INTO history_items (id, url, visit_count) VALUES (1, ?, 5);",
                (make_url("swift.org", "/blog"),),
            )
            conn.execute(
                "INSERT INTO history_visits (id, history_item, title, visit_time) VALUES (10, 1, 'Swift.org Official Blog', ?);",
                (now_cd,),
            )
            conn.commit()
        finally:
            conn.close()

    def test_aggregates_three_browsers_deduplicates_and_exports_search_index(self) -> None:
        card = bh.dispatch(
            {"query": "", "dataDir": str(self.data_dir), "locale": "zh-Hans"},
            [],
            user_home=self.fake_home,
        )
        self.assertEqual(card["badge"], "3 BROWSERS")
        # 6 unique URLs across Edge (Profile 1), Chrome (Default), and Safari (Bookmarks + Reading List + History)
        # Note: Azure Portal Docs appears in both Edge Bookmarks and Chrome History -> merged into 1 BM+HIS entry!
        self.assertEqual(len(card["items"]), 6)

        azure_row = next(r for r in card["items"] if "Azure Portal Docs" in r["title"])
        self.assertIn("BM+HIS", azure_row["badge"])
        self.assertIn("Edge(Work)", azure_row["subtitle"])
        self.assertIn("Chrome(Personal)", azure_row["subtitle"])

        idx_file = self.data_dir / "search-index.json"
        self.assertTrue(idx_file.is_file())
        idx_payload = json.loads(idx_file.read_text(encoding="utf-8"))
        self.assertEqual(len(idx_payload["items"]), 6)

    def test_dsl_filters_by_browser_kind_and_folder_and_supports_pinning(self) -> None:
        edge_only = bh.dispatch(
            {"query": "@edge", "dataDir": str(self.data_dir)},
            [],
            user_home=self.fake_home,
        )
        self.assertEqual(edge_only["badge"], "EDGE")
        self.assertEqual(len(edge_only["items"]), 2)

        safari_rl = bh.dispatch(
            {"query": "#reading webkit", "dataDir": str(self.data_dir)},
            ["--browser", "safari", "--kind", "bookmarks"],
            user_home=self.fake_home,
        )
        self.assertEqual(len(safari_rl["items"]), 1)
        self.assertIn("WebKit Engineering Blog", safari_rl["items"][0]["title"])

        target_u = make_url("swift.org", "/blog")
        pinned_card = bh.dispatch(
            {"query": "", "dataDir": str(self.data_dir)},
            ["--toggle-pin", target_u],
            user_home=self.fake_home,
        )
        self.assertTrue(pinned_card["items"][0]["title"].startswith("⭐ Swift.org Official Blog"))


if __name__ == "__main__":
    unittest.main()
