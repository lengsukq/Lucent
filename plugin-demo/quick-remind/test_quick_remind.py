#!/usr/bin/env python3
"""Unit tests for Lumakey Official Plugin: Quick Remind."""

from __future__ import annotations

import datetime as dt
import tempfile
import unittest

import quick_remind as qr


class QuickRemindTests(unittest.TestCase):
    def test_parses_relative_and_clock_phrases_bilingually(self) -> None:
        base = dt.datetime(2026, 11, 16, 18, 0, 0)

        p1 = qr.parse_natural_reminder("10m 喝水", now=base)
        self.assertIsNotNone(p1)
        assert p1 is not None
        self.assertEqual(p1[0], dt.datetime(2026, 11, 16, 18, 10, 0))
        self.assertEqual(p1[1], "喝水")
        self.assertEqual(p1[2], "once")

        p2 = qr.parse_natural_reminder("明天 9:30 交周报 工作日", now=base)
        self.assertIsNotNone(p2)
        assert p2 is not None
        self.assertEqual(p2[0], dt.datetime(2026, 11, 17, 9, 30, 0))
        self.assertEqual(p2[1], "交周报")
        self.assertEqual(p2[2], "weekdays")

        p3 = qr.parse_natural_reminder("in 2h check deployment", now=base)
        self.assertIsNotNone(p3)
        assert p3 is not None
        self.assertEqual(p3[0], dt.datetime(2026, 11, 16, 20, 0, 0))
        self.assertEqual(p3[1], "check deployment")

    def test_board_create_snooze_and_recurring_completion(self) -> None:
        base = dt.datetime(2026, 11, 16, 18, 0, 0)
        synced: list[str] = []

        with tempfile.TemporaryDirectory() as tmp:
            c1 = qr.execute_plugin(
                ["--add"],
                {"query": "15分钟 喂猫 每天", "dataDir": tmp, "config": {"snoozeMinutes": "10"}},
                now_override=base,
                apple_sync_fn=lambda title, _dt, _lst: (synced.append(title) or True),
            )
            self.assertEqual(synced, ["喂猫"])
            self.assertEqual(c1["badge"], "1 ACTIVE")

            items = qr.load_reminders(tmp)
            rid = items[0]["id"]

            # Snooze +10m
            qr.execute_plugin(
                ["--snooze", rid],
                {"dataDir": tmp, "config": {"snoozeMinutes": "10", "syncAppleReminders": "false"}},
                now_override=base,
            )
            after_snz = qr.load_reminders(tmp)[0]
            self.assertEqual(after_snz["dueDisplay"], "2026-11-16 18:10")

            # Completing a daily reminder advances it to the next day instead of closing permanently
            qr.execute_plugin(["--done", rid], {"dataDir": tmp}, now_override=base)
            after_done = qr.load_reminders(tmp)[0]
            self.assertFalse(after_done["done"])
            self.assertEqual(after_done["dueDisplay"], "2026-11-17 18:10")


if __name__ == "__main__":
    unittest.main()
