#!/usr/bin/env python3
"""Unit tests for Lumakey `ai-quota` v1.2 demo plugin (custom glass HUD, floating panel & notifications)."""

from __future__ import annotations

import datetime as dt
import io
import json
import stat
import tempfile
import time
import unittest
import urllib.request
from pathlib import Path
from unittest import mock

import ai_quota


class _FakeHTTPResponse(io.BytesIO):
    def __init__(self, body: bytes, status: int = 200) -> None:
        super().__init__(body)
        self.status = status

    def __enter__(self) -> "_FakeHTTPResponse":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()


class AIQuotaPluginTests(unittest.TestCase):
    def test_full_dashboard_custom_hud_floating_panel_and_notification_effects(self) -> None:
        with tempfile.TemporaryDirectory(prefix="lk-aq-test-") as tmp:
            root = Path(tmp)
            home = root / "home"
            data_dir = root / "data"
            bin_dir = root / "bin"
            home.mkdir()
            data_dir.mkdir()
            bin_dir.mkdir()

            codex_bin = bin_dir / "codex"
            reset_5h = int(time.time()) + 7200
            reset_7d = int(time.time()) + 345600
            codex_bin.write_text(
                "#!/usr/bin/env python3\n"
                "import json, sys\n"
                "if len(sys.argv) > 1 and sys.argv[1] == '--version':\n"
                "    print('codex 0.156.0'); raise SystemExit(0)\n"
                "for line in sys.stdin:\n"
                "    msg = json.loads(line)\n"
                "    if msg.get('id') == 0:\n"
                "        print(json.dumps({'jsonrpc':'2.0','id':0,'result':{}}), flush=True)\n"
                "    elif msg.get('id') == 1:\n"
                f"        print(json.dumps({{'jsonrpc':'2.0','id':1,'result':{{'rateLimits':{{'planType':'pro','primary':{{'usedPercent':22,'windowDurationMins':300,'resetsAt':{reset_5h}}},'secondary':{{'usedPercent':35,'windowDurationMins':10080,'resetsAt':{reset_7d}}}}}}}}}), flush=True)\n"
                "        break\n",
                encoding="utf-8",
            )
            codex_bin.chmod(codex_bin.stat().st_mode | stat.S_IXUSR)

            codex_sess = home / ".codex" / "sessions" / "2026" / "11" / "16"
            codex_sess.mkdir(parents=True)
            (codex_sess / "rollout-1.jsonl").write_text(
                json.dumps({"payload": {"info": {"total_token_usage": {"total_tokens": 84500}}}}) + "\n",
                encoding="utf-8",
            )

            claude_dir = home / ".claude"
            claude_proj = claude_dir / "projects" / "demo-proj"
            claude_proj.mkdir(parents=True)
            (claude_dir / ".usage-remote-cache.json").write_text(
                json.dumps(
                    {
                        "five_hour": {"utilization": 0.30, "resets_at": "2026-11-17T12:00:00Z"},
                        "seven_day": {"utilization": 0.45, "resets_at": "2026-11-20T12:00:00Z"},
                    }
                ),
                encoding="utf-8",
            )
            now_iso = dt.datetime.now(dt.timezone.utc).isoformat()
            (claude_proj / "sess-1.jsonl").write_text(
                json.dumps(
                    {
                        "timestamp": now_iso,
                        "message": {
                            "id": "msg_01",
                            "usage": {
                                "input_tokens": 2000,
                                "output_tokens": 3000,
                                "cache_read_input_tokens": 18000,
                                "cache_creation_input_tokens": 2000,
                            },
                        },
                    }
                )
                + "\n",
                encoding="utf-8",
            )

            agy_bin = bin_dir / "agy"
            agy_bin.write_text(
                "#!/bin/sh\n"
                'if [ "$1" = "--version" ]; then echo "agy 2.1.0"; exit 0; fi\n'
                'echo "Gemini Models Five Hour Limit: 92% remaining"\n'
                'echo "Gemini Models Weekly: 81% remaining"\n',
                encoding="utf-8",
            )
            agy_bin.chmod(agy_bin.stat().st_mode | stat.S_IXUSR)

            dsh_usage_dir = home / "dsh-usage-data" / "dsh-usage"
            dsh_usage_dir.mkdir(parents=True)
            (dsh_usage_dir / "usage-records.json").write_text(
                json.dumps(
                    [
                        {
                            "timestamp": int(time.time() * 1000),
                            "inputMissTokens": 4000,
                            "cacheHitTokens": 16000,
                            "outputTokens": 2500,
                            "cost": 0.42,
                        }
                    ]
                ),
                encoding="utf-8",
            )

            def _fake_urlopen(req: urllib.request.Request, timeout: float = 2.8) -> _FakeHTTPResponse:
                self.assertEqual(req.full_url, "https://api.deepseek.com/user/balance")
                self.assertEqual(req.get_header("Authorization"), "Bearer sk-test-valid-key")
                resp_obj = {
                    "is_available": True,
                    "balance_infos": [
                        {
                            "currency": "CNY",
                            "total_balance": "128.50",
                            "granted_balance": "28.50",
                            "topped_up_balance": "100.00",
                        },
                        {
                            "currency": "USD",
                            "total_balance": "15.00",
                            "granted_balance": "0.00",
                            "topped_up_balance": "15.00",
                        },
                    ],
                }
                return _FakeHTTPResponse(json.dumps(resp_obj).encode("utf-8"), 200)

            base_stdin = {
                "locale": "zh-Hans",
                "dataDir": str(data_dir),
                "config": {
                    "deepseekApiKey": "sk-test-valid-key",
                    "extraCliPaths": str(bin_dir),
                    "cacheTtlSeconds": "60",
                    "floatingIntervalSeconds": "45",
                    "notifyOnRefresh": "true",
                },
            }

            with mock.patch.object(urllib.request, "urlopen", side_effect=_fake_urlopen):
                payload = ai_quota.dispatch(stdin_payload=base_stdin, argv=["--dashboard"], user_home=home)
                hud_payload = ai_quota.dispatch(stdin_payload=base_stdin, argv=["--custom-hud"], user_home=home)
                json_payload = ai_quota.dispatch(stdin_payload=base_stdin, argv=["--json"], user_home=home)
                float_payload = ai_quota.dispatch(stdin_payload=base_stdin, argv=["--float-panel"], user_home=home)
                refresh_payload = ai_quota.dispatch(stdin_payload=base_stdin, argv=["--refresh"], user_home=home)

            self.assertEqual(payload["schemaVersion"], 2)
            self.assertEqual(len(payload["items"]), 5)
            metrics = {m["key"]: m["value"] for m in payload["metrics"]}
            self.assertIn("5h 78%", metrics["Codex CLI"])
            self.assertIn("5h 70%", metrics["Claude Code"])
            self.assertIn("¥128.50", metrics["DeepSeek 余额"])
            self.assertIn("$15.00", metrics["DeepSeek 余额"])

            # Verify custom frameless WebView HUD launch effect
            hud_eff = hud_payload["effect"]["openWindow"]
            self.assertEqual(hud_eff["htmlPath"], "ui/widget.html")
            self.assertEqual(hud_eff["chrome"], "frameless")
            self.assertTrue(hud_eff["transparent"])
            self.assertTrue(hud_eff["pinOnTop"])
            self.assertTrue(hud_payload["effect"]["closeOverlay"])

            # Verify raw JSON mode for window.lumakey.run(['--json'])
            self.assertTrue(json_payload["ok"])
            self.assertEqual(len(json_payload["providers"]), 5)
            self.assertEqual(json_payload["providers"][0]["primaryPercent"], 78.0)

            # Verify floating panel effect
            f_eff = float_payload["effect"]
            self.assertTrue(f_eff["openFloatingPanel"])
            self.assertTrue(f_eff["floatingPanelPinOnTop"])
            self.assertEqual(f_eff["floatingPanelIntervalSeconds"], 45)
            self.assertTrue(f_eff["closeOverlay"])

            # Verify native system notification effect on --refresh
            r_eff = refresh_payload["effect"]
            self.assertIn("notification", r_eff)
            self.assertEqual(r_eff["notification"]["title"], "AI 额度雷达已刷新")
            self.assertIn("Codex:", r_eff["notification"]["body"])

            for fname in ("quota-snapshot.json", "search-index.json", "status.json"):
                fpath = data_dir / fname
                self.assertTrue(fpath.is_file(), f"Missing {fname}")
                self.assertNotIn("sk-test-valid-key", fpath.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
