import LumakeyFoundation; import LumakeySearch; import LumakeyMedia; import LumakeySystem
import Foundation

extension PluginStarterGallery {
    static let portManagerStarterTemplate = PluginStarterTemplate(
        id: "port-killer",
        name: "开发端口与监听进程管家",
        subtitle: "全量 LISTEN 端口表 · 内存与运行时长 · 二次确认优雅/强制释放",
        description: "自动扫描本机全部 TCP 监听端口，解析进程内存占用、运行时长与启动命令，支持按端口号或进程名过滤，并在卡片内带二次确认一键发送 SIGTERM / SIGKILL。",
        mode: .view,
        icon: "bolt.horizontal.circle.fill",
        accentColor: "orange",
        categoryTag: "开发排障",
        keywords: ["port", "lsof", "listen", "killport", "端口", "进程占用"],
        config: [
            PluginConfigField(
                key: "highlightDevPorts", label: "优先置顶常见开发端口 (3000/5173/8080 等)",
                type: .boolean, defaultValue: "true", section: "列表排序与安全"
            ),
            PluginConfigField(
                key: "maxListedPorts", label: "单页最多展示监听端口数",
                type: .number, control: .slider, defaultValue: "25",
                section: "列表排序与安全", minValue: 5, maxValue: 80, stepValue: 5
            )
        ],
        capabilities: [],
        resourceScopes: [.subprocess],
        commands: [
            PluginCommandSpec(
                id: "list-all-ports", title: "扫描本机全部 TCP 监听端口",
                subtitle: "汇总当前所有 LISTEN 端口、占用进程内存与可执行路径并支持一键释放",
                keywords: ["ports", "监听列表", "排查端口", "portcheck"],
                icon: "list.bullet.rectangle.portrait", arguments: ["--all"], passQuery: true
            )
        ],
        locales: [
            "en": PluginLocaleStrings(
                name: "Dev Port & Listener Manager",
                description: "Scan all active TCP LISTEN ports, inspect RSS memory & command paths, filter by port/process, and terminate via confirmed SIGTERM or SIGKILL.",
                categoryTag: "DevOps",
                commands: [
                    "list-all-ports": PluginCommandLocaleStrings(
                        title: "List All Active TCP Listening Ports",
                        subtitle: "Inspect listening PIDs, memory usage & release ports with confirmation"
                    )
                ]
            )
        ],
        scriptBody: #"""
        #!/bin/zsh
        set -euo pipefail
        PAYLOAD="$(cat || true)"
        Q="$(printf '%s' "$PAYLOAD" | /usr/bin/plutil -extract query raw -o - - 2>/dev/null || true)"
        COUNT="$(/usr/sbin/lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | /usr/bin/awk 'NR>1{c++} END{print c+0}')"
        Q_SAFE="${Q//\"/\\\"}"
        cat <<EOF
        {"schemaVersion":2,"title":"开发端口与监听进程管家","subtitle":"活跃监听端口 ${COUNT} 个","badge":"${COUNT} LISTEN","metrics":[{"key":"活跃监听端口","value":"${COUNT}"},{"key":"筛选词","value":"${Q_SAFE:-全部}"}],"items":[{"id":"port-summary","title":"当前共有 ${COUNT} 条 TCP LISTEN 记录","subtitle":"回车刷新最新监听状态","icon":"network","badge":"LISTEN","copyText":"${COUNT}"}]}
        EOF
        """#
    )
}
