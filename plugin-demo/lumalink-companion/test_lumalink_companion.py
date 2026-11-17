#!/usr/bin/env python3
import unittest
import lumalink_companion as lc


class LumaLinkCompanionV21Tests(unittest.TestCase):
    def test_parse_cli_and_query_routes_all_subviews_and_actions(self) -> None:
        self.assertEqual(lc.parse_cli_and_query(["--toggle"], "")[:2], ("main", "toggle"))
        self.assertEqual(lc.parse_cli_and_query(["--pin"], "")[:2], ("pin_detail", "setEnabled"))
        self.assertEqual(lc.parse_cli_and_query(["--networks"], "")[:2], ("networks", "status"))
        self.assertEqual(
            lc.parse_cli_and_query(["--select-net", "en0:192.168.1.88"], ""),
            ("main", "selectNetwork", {"interface": "en0:192.168.1.88", "customHost": "", "renderQR": True}),
        )
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
        self.assertEqual(lc.parse_cli_and_query([], "配对码")[:2], ("pin_detail", "setEnabled"))
        self.assertEqual(lc.parse_cli_and_query([], "内网穿透")[:2], ("networks", "status"))

    def test_ungranted_bridge_returns_auth_guidance_card(self) -> None:
        card = lc.build_card_payload({"ok": False, "error": "capability_not_granted"}, locale="zh-Hans")
        self.assertEqual(card["badge"], "SETUP")
        self.assertEqual(card["items"][0]["openURL"], "lumakey://settings/plugin/lumalink-companion")

    def test_main_console_includes_pin_network_switcher_and_qr_popup(self) -> None:
        resp = {
            "ok": True,
            "data": {
                "enabled": True,
                "isListening": True,
                "localIPv4": "192.168.1.88",
                "selectedNetworkLabel": "自动优选 · 局域网 · en0 (192.168.1.88)",
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
        self.assertEqual(
            ids,
            ["toggle-service", "pair-pin-qr", "toggle-rdp", "switch-network", "switch-displays", "privacy-guards", "manage-devices"],
        )
        self.assertEqual(card["metrics"][0]["value"], "482910")

    def test_networks_and_pin_detail_cards_render_manual_fields(self) -> None:
        resp = {
            "ok": True,
            "data": {
                "enabled": True,
                "isListening": True,
                "localIPv4": "192.168.1.88",
                "preferredInterface": "",
                "customConnectHost": "",
                "selectedNetworkLabel": "局域网 · en0 (192.168.1.88)",
                "port": 59480,
                "rdpPort": 3389,
                "pairingPin": "903412",
                "pairURI": "lumalink://pair?host=192.168.1.88&port=59480&pin=903412",
                "qrImagePath": "/tmp/qr.png",
                "networkInterfaces": [
                    {"id": "en0:192.168.1.88", "interfaceName": "en0", "ipv4": "192.168.1.88", "kind": "lan", "displayLabel": "局域网 · en0 (192.168.1.88)"},
                    {"id": "utun4:100.88.1.2", "interfaceName": "utun4", "ipv4": "100.88.1.2", "kind": "tunnel", "displayLabel": "内网穿透/组网 · utun4 (100.88.1.2)"},
                ],
            },
        }
        net_card = lc.build_card_payload(resp, view_mode="networks", locale="zh-Hans")
        self.assertEqual(net_card["badge"], "NETWORK")
        self.assertEqual(net_card["items"][2]["commandArgs"], ["--select-net", "en0:192.168.1.88"])
        self.assertEqual(net_card["items"][3]["commandArgs"], ["--select-net", "utun4:100.88.1.2"])

        pin_card = lc.build_card_payload(resp, view_mode="pin_detail", locale="zh-Hans")
        self.assertEqual(pin_card["badge"], "PIN READY")
        self.assertEqual(pin_card["items"][1]["copyText"], "903412")
        self.assertEqual(pin_card["items"][2]["copyText"], "192.168.1.88")
        self.assertIn("192.168.1.88", pin_card["markdown"])


if __name__ == "__main__":
    unittest.main()
