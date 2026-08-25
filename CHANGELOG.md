# Changelog

## [Unreleased]

- 增加简洁原生主窗口：显示运行状态、自动关闭开关、权限状态、登录启动和最近关闭时间。
- 用户正常打开或再次点击已运行 App 时显示/置前主窗口；登录项启动继续保持后台安静。
- 菜单栏增加“打开 Typeless Quiet”入口；权限缺失时仍优先显示现有授权引导。

## [0.1.4] - 2026-08-25

- 将 400ms 全量 AX 轮询改为 AXObserver 主导：监听 application 与 window 的创建、布局和激活事件。
- 连续 AX 通知合并为 80ms debounce；Observer 有效时只保留 8 秒 watchdog，完全不可用时使用 1 秒 fallback。
- 增加扫描触发来源、耗时和 observer coverage 日志，方便持续验证常驻性能。

## [0.1.3] - 2026-08-24

- 权限缺失时显示可见的原生设置引导，不再被旧的一次性提示标记静默跳过。
- 系统辅助功能提示按 App build 去重；新 build 会重新尝试，拒绝后仍保留明确的系统设置入口。
- DMG 安装图改为“拖入 Applications，然后从 Applications 打开”的两步说明。

## [0.1.2] - 2026-08-24

- 增加原创 App 图标，改善 Finder、Applications 和系统设置中的识别度。
- 发布标准 DMG 拖拽安装窗口：App、Applications alias 和清晰安装箭头。
- App 与 DMG 分别完成 Developer ID 签名、Apple notarization、stapling 和 Gatekeeper 验证。
- 保留 ZIP 作为备用下载格式。

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
