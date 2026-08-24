# Changelog

## [0.1.1] - 2026-08-24

- 首次启动缺少辅助功能权限时立即触发 macOS 官方授权提示；只自动提示一次。
- 首次启动默认注册“登录时启动”，同时尊重用户后续手动关闭选择。
- 为首次启动权限和登录项默认策略增加独立回归测试。
- Developer ID 构建完成 Apple notarization 和 stapling，可通过 Gatekeeper 验证。

## [0.1.0] - 2026-08-24

首个公开版本：

- 原生 Swift macOS 菜单栏后台应用，不依赖 Hammerspoon、Node 或第三方 Swift 包。
- 仅连接 Bundle ID 为 `now.typeless.desktop` 的 Typeless 主进程。
- 精确匹配 `AXUserInterfaceTooltip` 和 `Upgrade for enhanced accuracy`。
- 只在目标卡片内部识别唯一的无名称右上角关闭按钮；所有歧义路径均 fail closed。
- AX Observer 加仅在 Typeless 运行时启用的有界扫描兜底。
- 中文菜单栏状态、辅助功能权限引导和登录启动设置。
- 16 项匹配器回归测试与 GitHub Actions 构建门禁。

已知限制：

- 下载资产仅支持 macOS 13+ Apple Silicon arm64。
- App 使用 Developer ID 签名，但没有 Apple notarization。
- 服务器下发目标提示尚未完成真实客户端 AX/E2E 验证。
