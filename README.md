# Typeless Quiet

[![CI](https://github.com/timmyagentic/typeless-quiet/actions/workflows/ci.yml/badge.svg)](https://github.com/timmyagentic/typeless-quiet/actions/workflows/ci.yml)

一个轻量、原生的 macOS 菜单栏工具，提供简洁主窗口，只负责自动关闭 Typeless 中标题为
`Upgrade for enhanced accuracy` 的付费升级提示。

Typeless Quiet 是非官方项目，与 Typeless 或 Simply LLC 没有隶属、授权或合作关系。

> `v0.1.4` 提供 macOS 13+ Apple Silicon arm64 下载。App 已使用 Developer ID 签名、
> Apple notarization 并 staple 公证票据，可通过 Gatekeeper 验证。服务器下发提示的真实
> 客户端 AX 结构仍待现场验证。

## 为什么不是 Hammerspoon

Typeless Quiet 直接使用 macOS Accessibility API，不依赖 Hammerspoon、Node、npm、
Electron 或第三方 Swift 包。它不会修改 Typeless 应用包，也不会拦截网络请求。

应用需要常驻，但只在 Typeless 运行时连接其 Accessibility 树。它优先响应窗口和布局的
Accessibility 通知，并只保留低频 watchdog；通知完全不可用时才降级轮询。Typeless 未
运行时，它只等待系统的应用启动通知。

## 安全边界

规则必须同时满足以下条件才会执行 `AXPress`：

1. 目标进程 Bundle ID 精确等于 `now.typeless.desktop`。
2. 容器角色精确等于 `AXUserInterfaceTooltip`。
3. 容器或后代文本精确等于 `Upgrade for enhanced accuracy`。
4. 关闭候选是目标卡片的后代 `AXButton`。
5. 候选没有 Accessibility 名称，尺寸在 14–20 pt 之间，位于卡片内部右上角。
6. 候选支持 `AXPress`，并且全卡片中恰好只有一个候选。
7. 执行动作前重新抓取一次 AX 树，结果必须与首次判断完全一致。

任一条件不满足、遍历超过上限、出现多个目标卡片或多个按钮时，应用都会停止本次操作。
它不会全局搜索 Close 按钮，也不会使用屏幕坐标点击。

## 系统要求

- macOS 13 或更高版本
- 构建时需要 Xcode/Swift 工具链
- 运行时需要用户手动授予“辅助功能”权限

## 下载 v0.1.4

- [Typeless Quiet v0.1.4 Release](https://github.com/timmyagentic/typeless-quiet/releases/tag/v0.1.4)
- 平台：macOS 13+，Apple Silicon arm64
- 推荐资产：`Typeless-Quiet-0.1.4-macos-arm64.dmg`
- 备用资产：`Typeless-Quiet-0.1.4-macos-arm64.zip`
- 校验：两种格式均提供 `.sha256` 文件

打开 DMG 后，先将 Typeless Quiet 拖入 Applications，再从 Applications 打开它。App
会在权限缺失时显示可见的原生授权引导，并提供直达系统设置的按钮。App 与 DMG 都已
完成 Apple notarization 与 stapling。公证和 Developer ID 签名不代表真实弹窗 E2E 已
验证；该项仍需在服务器提示实际出现时完成。

正常打开 App 会显示主窗口；关闭窗口后仍会在菜单栏运行。登录项自动启动时不会主动
弹出主窗口，再次从 Applications 打开即可随时显示或置前。

## 构建与验证

```bash
git clone https://github.com/timmyagentic/typeless-quiet.git
cd typeless-quiet
make verify
```

验证通过后，应用位于：

```text
dist/Typeless Quiet.app
```

重新生成 App 图标和 DMG 背景、制作本地测试 DMG：

```bash
make assets
make dmg
```

DMG 布局使用系统 Finder 自动化写入 `.DS_Store`；首次运行构建脚本时，macOS 可能要求
允许当前终端控制 Finder。该权限只用于设置安装卷的背景、图标位置和窗口状态。

默认构建使用本机 ad-hoc 签名。如果需要在多次本地升级后尽量保持稳定的应用身份，
可以传入 Keychain 中已有的固定代码签名证书：

```bash
CODE_SIGN_IDENTITY='Developer ID Application: …' make verify
```

本地 Developer ID 签名不等于公证；对外分发前仍需单独完成 notarization。

## 本机安装

从源码构建后，默认安装到 `~/Applications`，不会覆盖现有副本：

```bash
./scripts/install.sh
```

升级本地副本时，旧版本会先移动为带时间戳的备份：

```bash
./scripts/install.sh --replace
```

首次启动后：

1. 正常打开时会显示主窗口；权限缺失时优先显示可见的原生设置引导。
2. 每个 App build 最多自动尝试一次 macOS 官方权限提示；若系统不再重复显示，使用引导
   中的按钮直接打开系统设置。
3. 在“设备控制和数据访问”（部分 macOS 显示为“辅助功能”）中批准 Typeless Quiet。
4. 应用会默认注册“登录时启动”；若系统要求额外批准，菜单会显示对应状态。
5. 你随时可以从菜单关闭登录启动，应用不会在下次启动时重新强制开启。

系统权限最终仍必须由用户批准，应用不会静默绕过 macOS 权限。若系统提示被拒绝，原生
设置引导会在权限仍缺失的下次启动再次出现，不会再被历史的一次性标记静默跳过；菜单中
也保留手动入口。

## 卸载

1. 在菜单中关闭“登录时启动”。
2. 退出 Typeless Quiet。
3. 将 `~/Applications/Typeless Quiet.app` 移到废纸篓。
4. 如需清理授权，在“系统设置 → 隐私与安全性 → 设备控制和数据访问”（部分 macOS
   显示为“辅助功能”）移除它。

## 运行状态与日志

主窗口和菜单栏都会显示等待 Typeless、正在监听、缺少权限、暂停或 fail-closed 原因。
系统日志只记录规则结果，不记录输入内容或其他界面文本：

```bash
log stream --predicate 'subsystem == "io.github.timmyagentic.TypelessQuiet"'
```

## 当前验证限制

匹配器、Release 构建、应用包结构和签名可以自动验证；但目标提示由服务器下发，
只有它实际出现时才能确认 Typeless 当前版本暴露的 AX Role、层级和几何仍与规则一致。
在完成这项现场验证前，真实自动关闭行为应视为 `UNVERIFIED`。

## 参与贡献

欢迎提交 Issue 或 Pull Request。涉及匹配范围的修改必须附带负例测试；规则应继续保持
fail closed，不能改成全局 Close 按钮搜索、模糊标题或屏幕坐标点击。

## License

[MIT](LICENSE)
