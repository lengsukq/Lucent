#!/usr/bin/env python3
import unittest
import lumalink_companion as lc


class LumaLinkCompanionV2Tests(unittest.TestCase):
    def test_parse_cli_and_query_routes_all_subviews_and_actions(self) -> None:
        self.assertEqual(lc.parse_cli_and_query(["--toggle"], "")[:2], ("main", "toggle"))
        self.assertEqual(lc.parse_cli_and_query(["--qr"], "")[:2], ("qr_popup", "setEnabled"))
        self.assertEqual(lc.parse_cli_and_query(["--displays"], "")[:2], ("displays", "status"))
        self.assertEqual(
            lc.parse_cli_and_query(["--set-mode", "1", "1280x720@2x_60"], ""),
            ("displays", "setDisplayMode", {"displayID": 1, "modeKey": "1280x720@2x_60", "includeDisplays": True}),
        )
        self.assertEqual(
            lc.parse_cli_and_query(["--revoke", "dev-42"], ""),
            ("devices", "revokeDevice", {"deviceId": "dev-42", "renderQR": False}),
        )
        self.assertEqual(lc.parse_cli_and_query([], "黑屏")[:2], ("main", "toggleCurtain"))

    def test_ungranted_bridge_returns_auth_guidance_card(self) -> None:
        card = lc.build_card_payload({"ok": False, "error": "capability_not_granted"}, locale="zh-Hans")
        self.assertEqual(card["badge"], "AUTH")
        self.assertEqual(card["items"][0]["openURL"], "lumakey://settings/plugin/lumalink-companion")

    def test_main_console_includes_qr_viewer_guards_and_subview_entries(self) -> None:
        resp = {
            "ok": True,
            "data": {
                "enabled": True,
                "isListening": True,
                "localIPv4": "192.168.1.88",
                "port": 59480,
                "pairingPin": "482910",
                "pairURI": "lumalink://pair?host=192.168.1.88&port=59480&pin=482910",
                "qrImagePath": "/tmp/lumakey-lumalink-qr/qr-test.png",
                "connectedDeviceCount": 1,
                "pairedDeviceCount": 2,
                "rdpEnabled": True,
                "rdpRunning": True,
                "rdpPort": 3389,
                "curtainActive": True,
                "caffeineActive": False,
                "hasModifiedDisplays": True,
            },
        }
        card = lc.build_card_payload(resp, view_mode="qr_popup", locale="zh-Hans", pin_qr_on_top=True)
        self.assertEqual(card["badge"], "ONLINE")
        self.assertEqual(card["effect"]["pinImagePath"], "/tmp/lumakey-lumalink-qr/qr-test.png")
        ids = [x["id"] for x in card["items"]]
        self.assertEqual(ids, ["toggle-service", "pair-pin-qr", "switch-displays", "privacy-guards", "toggle-rdp", "manage-devices"])
        self.assertIn("lumakey://image?path=", card["items"][1]["openURL"])

    def test_displays_and_devices_subviews_render_interactive_actions(self) -> None:
        disp_resp = {
            "ok": True,
            "data": {
                "hasModifiedDisplays": True,
                "displays": [
                    {
                        "displayID": 69733382,
                        "name": "Built-in Retina",
                        "currentModeKey": "1440x900@2x_60",
                        "modes": [
                            {"modeKey": "1280x720@2x_60", "label": "1280×720 HiDPI", "refreshHz": 60, "isHiDPI": True, "isCurrent": False},
                            {"modeKey": "1440x900@2x_60", "label": "1440×900 HiDPI (当前)", "refreshHz": 60, "isHiDPI": True, "isCurrent": True},
                        ],
                    }
                ],
            },
        }
        dcard = lc.build_card_payload(disp_resp, view_mode="displays", action_triggered="setDisplayMode", locale="en")
        self.assertEqual(dcard["badge"], "DISPLAY")
        self.assertEqual(dcard["items"][1]["commandArgs"], ["--restore-displays"])
        self.assertEqual(dcard["items"][2]["commandArgs"], ["--set-mode", "69733382", "1280x720@2x_60"])
        self.assertEqual(dcard["items"][3]["commandArgs"], [])

        dev_resp = {
            "ok": True,
            "data": {"pairedDevices": [{"id": "d-9", "name": "Pixel 9 Pro", "pairedAt": 1731700000}]},
        }
        pcard = lc.build_card_payload(dev_resp, view_mode="devices", action_triggered="revokeDevice", locale="zh-Hans")
        self.assertEqual(pcard["badge"], "1 DEV")
        revoke_act = pcard["items"][1]["actions"][0]
        self.assertEqual(revoke_act["style"], "destructive")
        self.assertEqual(revoke_act["commandArgs"], ["--revoke", "d-9"])
        self.assertTrue(bool(revoke_act["confirmMessage"]))


if __name__ == "__main__":
    unittest.main()
