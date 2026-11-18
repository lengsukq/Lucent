import Foundation

extension ScriptLibraryStore {
    public static func starterTemplates() -> [(ScriptRecord, String, String?)] {
        let ref = Date(timeIntervalSince1970: 1_731_800_000)
        let jsonSvg = """
        <svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg">
          <defs>
            <linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
              <stop offset="0%" stop-color="#06B6D4"/>
              <stop offset="100%" stop-color="#3B82F6"/>
            </linearGradient>
          </defs>
          <rect x="6" y="6" width="52" height="52" rx="14" fill="url(#g)"/>
          <path d="M24 20 C19 20 19 25 19 28 C19 31 16 32 16 32 C16 32 19 33 19 36 C19 39 19 44 24 44" fill="none" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round"/>
          <path d="M40 20 C45 20 45 25 45 28 C45 31 48 32 48 32 C48 32 45 33 45 36 C45 39 45 44 40 44" fill="none" stroke="#FFFFFF" stroke-width="3.5" stroke-linecap="round"/>
        </svg>
        """
        return [
            (
                ScriptRecord(
                    id: "pretty-clipboard-json",
                    title: "美化剪贴板 JSON",
                    englishTitle: "Prettify Clipboard JSON",
                    subtitle: "读取剪贴板 JSON 并缩进格式化后写回剪贴板",
                    englishSubtitle: "Format clipboard JSON with 2-space indent and copy back",
                    keywords: ["!json", "jsonfmt"],
                    category: "开发",
                    fileName: "pretty-clipboard-json.py",
                    runtime: .python3,
                    outputMode: .copyToClipboard,
                    icon: "icons/pretty-clipboard-json.svg",
                    accentColor: "cyan",
                    passClipboard: true,
                    updatedAt: ref
                ),
                """
                #!/usr/bin/env python3
                # @lucent.title: 美化剪贴板 JSON
                # @lucent.title.en: Prettify Clipboard JSON
                # @lucent.keywords: !json, jsonfmt
                # @lucent.output: copyToClipboard
                # @lucent.clipboard: true
                import json, os, sys

                raw = (os.environ.get("LUCENT_QUERY") or os.environ.get("LUCENT_CLIPBOARD") or "").strip()
                if not raw:
                    print("剪贴板为空，请先复制一段 JSON 文本", file=sys.stderr)
                    sys.exit(1)
                obj = json.loads(raw)
                print(json.dumps(obj, ensure_ascii=False, indent=2))
                """,
                jsonSvg
            ),
            (
                ScriptRecord(
                    id: "lan-network-brief",
                    title: "本机局域网与网关速查",
                    englishTitle: "LAN IP & Gateway Brief",
                    subtitle: "快速查看活跃网卡 IPv4 地址、默认路由网关与 DNS",
                    englishSubtitle: "Inspect local IPv4, default gateway, and DNS servers",
                    keywords: ["!ip", "lanip"],
                    category: "系统",
                    fileName: "lan-network-brief.zsh",
                    runtime: .zsh,
                    outputMode: .inlinePreview,
                    icon: "network",
                    accentColor: "mint",
                    updatedAt: ref
                ),
                """
                #!/bin/zsh
                # @lucent.title: 本机局域网与网关速查
                # @lucent.title.en: LAN IP & Gateway Brief
                # @lucent.keywords: !ip, lanip
                # @lucent.output: inlinePreview
                set -euo pipefail

                echo "=== 活跃接口 IPv4 ==="
                ifconfig | awk '/^[a-z0-9]+:/{iface=$1} /inet / && $2 != "127.0.0.1"{print iface, $2}'
                echo ""
                echo "=== 默认网关 ==="
                route -n get default 2>/dev/null | awk '/gateway:|interface:/{print $1, $2}' || true
                """,
                nil
            ),
            (
                ScriptRecord(
                    id: "copy-finder-folder",
                    title: "复制当前访达目录路径",
                    englishTitle: "Copy Front Finder Path",
                    subtitle: "获取最前方访达窗口所在文件夹 POSIX 路径并复制",
                    englishSubtitle: "Copy POSIX path of the frontmost Finder window",
                    keywords: ["!fpath", "finderpath"],
                    category: "效率",
                    fileName: "copy-finder-folder.applescript",
                    runtime: .appleScript,
                    outputMode: .copyToClipboard,
                    icon: "folder.fill.badge.gearshape",
                    accentColor: "blue",
                    updatedAt: ref
                ),
                """
                -- @lucent.title: 复制当前访达目录路径
                -- @lucent.title.en: Copy Front Finder Path
                -- @lucent.keywords: !fpath, finderpath
                -- @lucent.output: copyToClipboard
                tell application "Finder"
                    if (count of Finder windows) > 0 then
                        return POSIX path of (target of front window as alias)
                    else
                        return POSIX path of (desktop as alias)
                    end if
                end tell
                """,
                nil
            )
        ]
    }
}
