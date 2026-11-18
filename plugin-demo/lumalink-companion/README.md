# 流光随行 · LumaLink 远控伴侣 (`lumalink-companion` v2.2)

本插件是仓库 `plugin-demo/` 示例商店中的 **Host Bridge v3.7 全功能远控控制台**，预编译为 `arm64` 原生 Swift 6 可执行程序（`bin/lumalink-companion`，零 Python 运行时依赖），无需在主程序设置侧边栏保留常驻入口，即可直接在 `⌥Space` 浮窗内完成全部局域网与内网穿透远控管理闭环：

- **物理局域网 / 内网穿透网卡切换与 6 位配对码直显 (`lumalink-network` / `lumalink-pin`)**：自动识别并区分物理局域网（`en0`）与 Tailscale / ZeroTier 内网穿透网卡，一键查看并复制主机 IP、端口与 CSPRNG 6 位防爆破配对码。
- **一键扫码配对 (`lumalink-qr`)**：宿主桥使用 `CoreImage` (`CIQRCodeGenerator`) 动态渲染高清 `380×380` 配对二维码，支持直接在独立悬浮置顶窗（`lucent://image?path=...&pin=1`）扫码连接，并支持一键轮换配对码（连续 5 次输错自动锁定 60 秒并强制轮换）。
- **多屏 HiDPI 分辨率内联切换 (`lumalink-displays`)**：直接在插件卡片内浏览全部活跃显示器的 HiDPI / 原生模式，单击即可切换至适合手机屏幕比例的 `1280×720 HiDPI` / `1600×900 HiDPI`，并支持一键还原切换前的原生分辨率。
- **物理防窥黑屏与防休眠守卫 (`lumalink-curtain` / `lumalink-caffeine`)**：支持绑定独立全局快捷键静默切换 Mac 物理显示器隐私幕布或 `IOPMAssertion` 防空闲睡眠保护。
- **已配对手机安全审计与吊销 (`lumalink-devices`)**：所有设备配对 Token 均密封于宿主 `LocalSecretVault`（磁盘配置与备份归档零明文留存），卡片内支持带二次确认弹窗（`destructive` + `confirmMessage`）单台吊销解绑。
- **纯外部沙盒与即关即毁**：声明 `"resourceScopes": []` 与 `"capabilities": ["lumaLinkStatus"]`，未安装、停用或卸载插件时自动释放全部 TCP / Bonjour / RDP 端口。
