#!/usr/bin/env python3
"""Unit tests for Lumakey Official Plugin: Translate Hub."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import translate_hub as th


class TranslateHubTests(unittest.TestCase):
    def test_language_detection_and_target_override(self) -> None:
        txt, src, dst = th.parse_target_override("Hello architecture", "zh-Hans", "en")
        self.assertEqual((txt, src, dst), ("Hello architecture", "en", "zh-Hans"))

        txt2, src2, dst2 = th.parse_target_override("流光效率中枢", "zh-Hans", "en")
        self.assertEqual((txt2, src2, dst2), ("流光效率中枢", "zh-Hans", "en"))

        txt3, src3, dst3 = th.parse_target_override(">ja 你好世界", "zh-Hans", "en")
        self.assertEqual((txt3, src3, dst3), ("你好世界", "zh-Hans", "ja"))

    def test_parallel_translation_vocab_save_and_anki_export(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            data_dir = Path(tmp) / "data"
            export_dir = Path(tmp) / "exports"

            def fake_fetcher(text: str, src: str, target: str, _cfg: dict) -> tuple[list[dict[str, str]], dict | None]:
                return (
                    [
                        {"provider": "LLM (deepseek-chat)", "text": "弹性架构"},
                        {"provider": "Built-in GTX", "text": "弹性系统结构"},
                    ],
                    {"word": text, "explain": "n. 弹性；恢复力", "related": []},
                )

            out = th.execute_plugin(
                ["--input"],
                {
                    "query": "resilience",
                    "dataDir": str(data_dir),
                    "config": {"primaryLang": "zh-Hans", "secondaryLang": "en", "exportDir": str(export_dir)},
                },
                fetcher_override=fake_fetcher,
            )
            self.assertEqual(out["title"], "弹性架构")
            self.assertEqual(len(out["items"]), 3)
            self.assertTrue((data_dir / "history.json").exists())

            hist = json.loads((data_dir / "history.json").read_text(encoding="utf-8"))
            eid = hist[0]["id"]

            saved_card = th.execute_plugin(
                ["--save-inline", eid, "resilience", "弹性架构", "zh-Hans", "n. 弹性；恢复力"],
                {"dataDir": str(data_dir), "config": {"exportDir": str(export_dir)}},
            )
            self.assertIn("生词本", saved_card["title"])
            idx = json.loads((data_dir / "search-index.json").read_text(encoding="utf-8"))
            self.assertEqual(len(idx["items"]), 1)
            self.assertIn("resilience", idx["items"][0]["title"])

            exp_card = th.execute_plugin(
                ["--export"],
                {"dataDir": str(data_dir), "config": {"exportDir": str(export_dir)}},
            )
            self.assertEqual(exp_card["badge"], "EXPORTED")
            anki_tsv = (export_dir / "Lumakey-Vocab-Anki.tsv").read_text(encoding="utf-8")
            self.assertIn("resilience\t弹性架构", anki_tsv)
            self.assertTrue((export_dir / "Lumakey-Vocab.csv").exists())


if __name__ == "__main__":
    unittest.main()
