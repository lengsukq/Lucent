#!/usr/bin/env python3
"""Unit tests for Lumakey Official Plugin: Screen Shield."""

from __future__ import annotations

import tempfile
import unittest
from typing import Any

import screen_shield as ss


class ScreenShieldTests(unittest.TestCase):
    def test_console_overview_and_preset_activation(self) -> None:
        calls: list[tuple[str, dict[str, Any]]] = []

        def fake_bridge(action: str, params: dict[str, Any]) -> dict[str, Any]:
            calls.append((action, params))
            return {"ok": True, "data": {"accessibilityTrusted": True}}

        with tempfile.TemporaryDirectory() as tmp:
            overview = ss.execute_plugin([], {"dataDir": tmp, "config": {"holdSeconds": "3"}}, bridge_fn=fake_bridge)
            self.assertEqual(overview["badge"], "SHIELD")
            self.assertEqual(len(overview["items"]), 4)

            act = ss.execute_plugin(
                ["--preset", "clean"],
                {"dataDir": tmp, "config": {"holdSeconds": "3", "blockInput": "true", "keepAwake": "true"}},
                bridge_fn=fake_bridge,
            )
            self.assertEqual(act["badge"], "ACTIVE")
            self.assertTrue(act["effect"]["closeOverlay"])
            self.assertEqual(calls[-1][0], "setStatusScreen")
            self.assertEqual(calls[-1][1]["preset"], "clean")
            self.assertEqual(calls[-1][1]["holdSeconds"], 3.0)

            custom = ss.execute_plugin(
                [],
                {"query": "猫咪出没 · 键盘已锁", "config": {"customIcon": "🐾"}},
                bridge_fn=fake_bridge,
            )
            self.assertEqual(custom["badge"], "ACTIVE")
            self.assertEqual(calls[-1][1]["preset"], "custom")
            self.assertEqual(calls[-1][1]["title"], "猫咪出没 · 键盘已锁")
            self.assertEqual(calls[-1][1]["icon"], "🐾")


if __name__ == "__main__":
    unittest.main()
