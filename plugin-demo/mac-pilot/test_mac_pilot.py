#!/usr/bin/env python3
"""Unit tests for Lumakey Official Plugin: Mac Pilot."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import mac_pilot as mp


class MacPilotTests(unittest.TestCase):
    def test_syncs_system_panes_search_index_and_filters_panes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = mp.execute_plugin(["--panes"], {"query": "蓝牙", "dataDir": tmp})
            self.assertEqual(out["badge"], "SETTINGS")
            self.assertEqual(len(out["items"]), 1)
            self.assertIn("BluetoothSettings", out["items"][0]["openURL"])

            idx = json.loads((Path(tmp) / "search-index.json").read_text(encoding="utf-8"))
            self.assertEqual(len(idx["items"]), 16)

    def test_finder_creates_collision_safe_blank_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "Desk"
            c1 = mp.execute_plugin(["--new-file", str(folder), "md"], {"query": "notes"})
            self.assertEqual(c1["badge"], "FINDER")
            self.assertTrue((folder / "notes.md").exists())

            mp.execute_plugin(["--new-file", str(folder), "md"], {"query": "notes"})
            self.assertTrue((folder / "notes-2.md").exists())


if __name__ == "__main__":
    unittest.main()
