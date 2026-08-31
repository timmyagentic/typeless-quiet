# Changelog

## [Unreleased]

- 增加默认关闭的低额度守护页：可配置阈值、有序账号池和冷却时间；仅启用时运行 60 秒检查。
- 守护要求当前/目标额度快照新鲜、Typeless 明确空闲、池 ID 唯一完整且当前账号在池；
  录音/处理、活动未知、数据陈旧、目标歧义、切换进行中和冷却状态全部 no-op。
- 每轮最多复用一次 P2 官方切换；失败按基础冷却指数退避（上限 24 小时），成功清零。
- 增加 schema v1 `quota-guard.json`，以 0700/0600 权限跨重启保存配置、尝试和失败计数，
  不保存邮箱、密码、token、Cookie 或设备身份。
- 增加安全的一键切换：固定打开 Typeless 官方 HTTPS 登录页，由官网完成桌面 handoff；
  不读取、构造或记录 `typeless://` 认证链接。
- 增加 preflight → request → verify → rollback 状态机；正在录音、处理转录、活动未知、
  当前额度缺失/陈旧、目标暂停或并发 transaction 时 fail closed。
- 只有请求后重新读到目标邮箱和新鲜额度才切换成功；超时保留原账号，错误账号或额度不可验证
  时打开官方流程恢复原账号并再次验证。
- 增加 schema v1 无秘密切换审计和诊断页最近历史；记录 UUID、阶段、时间、结果和固定错误码，
  不记录邮箱、URL、密码、token、Cookie 或设备身份。
- 增加账号与额度基础层：概览、账号、诊断三页，以及菜单栏当前账号/额度摘要。
- 增加 schema v1 账号目录、邮箱标准化与重复检查、排序、暂停、编辑和删除；账号 JSON
  使用原子写入与仅当前用户可读权限。
- 增加按账号 UUID 隔离的 macOS Keychain 秘密存储；元数据与 Keychain 以可回滚事务提交，
  保存失败不会留下半完成状态。
- 只读解析 Typeless 2.4.0 `app-storage.json` 的账号白名单字段，并从当前 Accessibility
  文本识别本地化额度；不读取、保存或记录 token、Cookie、验证码和设备身份。
- 增加账号目录、Keychain、Typeless 运行/版本和额度来源自检；读取不到可靠额度时显示未知。
- 产品更名为 `Typeless++`，源码仓库迁移为 `timmyagentic/typeless-plusplus`；Swift package/product、App/DMG 本地产物、主窗口、菜单、权限引导与文档统一使用新品牌。
- 保留旧 Bundle ID `io.github.timmyagentic.TypelessQuiet`、UserDefaults keys 和窗口状态 key，避免已安装用户重新授权或丢失设置。
- 增加账号管理与安全切换路线图；本阶段不实现账号切换、自动注册、设备身份重置或 token 注入。
- 适配 Typeless 2.4.0 的 “Get unlimited words” / “获取无限字数” 升级提示及对应完整描述，同时保留旧版 “Upgrade for enhanced accuracy”。
- 支持 Tooltip、Dialog、Popover、Sheet 和 Electron Application Dialog 容器映射。
- 优先识别 `AXCloseButton` / `AXCancelButton`、Close/Dismiss/关闭语义与明确的 AX/DOM identifier；兼容 32–44pt 现代图标按钮，并保留旧版无名称 14–20pt 按钮。
- 将 2.4.0 左下角常驻订阅卡片和普通 Upgrade/升级按钮固定为负例，继续要求唯一目标、唯一关闭按钮和动作前复验。

## [0.1.5] - 2026-08-25

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
