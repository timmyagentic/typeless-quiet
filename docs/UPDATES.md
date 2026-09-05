# 应用内更新与发布

Typeless++ 采用 Sparkle 2.9.6，参考 QuotaMonitor 的非打断式更新流程：后台检查只显示更新入口，点击后重新核对 feed 并下载，校验与准备完成后明确提示重启。手动检查提供检查中、无更新和失败状态。

## 用户体验与渠道

- 菜单栏有「检查更新」「更新设置」，主窗口底部有更新入口。发现更新后菜单栏图标及入口显示提醒，重启应用后仍保留；安装新 build 后自动清除。
- 默认启用自动检查。Sparkle 负责 24 小时调度；启动、唤醒、回到前台时，仅距离上次检查超过 6 小时且没有更新流程正在执行才补查。用户关闭自动检查后，生命周期补查也停止。
- Beta 构建默认「Beta 与正式版」，正式构建默认「仅正式版」。用户的明确渠道选择会保留；切换渠道会清除旧提醒并重新检查。
- 同一 `appcast.xml` 内 Beta 项包含 `<sparkle:channel>beta</sparkle:channel>`，正式版无 channel。Beta 客户端总能看到更高 build 的正式版。
- `CFBundleVersion` 是全渠道严格递增的正整数，`sparkle:version` 必须与它相同。营销版本 `0.0.1` 不参与构建排序，旧 Quiet `0.1.5 (6)` 不会覆盖新品牌 Beta。
- 准备完成前关闭更新窗口不会停止下载；需要取消时使用「取消」。准备完成后选择「稍后」可保留下载，Sparkle 可能在应用正常退出时完成安装。恢复安装时仍显示重启确认，不因点击提醒直接退出应用。

现有 Beta 1 / Beta 2 不含 Sparkle，不能自行获得这个能力。第一次必须手动安装包含更新器的新版本，以后的更新才走上述流程。

## 信任和打包

- `CFBundleIdentifier` 保留 `io.github.timmyagentic.TypelessQuiet`。
- `Resources/Info.plist` 的 `SUPublicEDKey` 为 Typeless++ 独立 Ed25519 公钥。私钥由 Sparkle 保存于本机 login Keychain 的 `typeless-plusplus` account，不与 QuotaMonitor 共享，不进入仓库、命令行参数或 Task 文档。
- Sparkle Ed25519 签名和 Apple Developer ID / notarization 是不同层；必须都验证。
- `scripts/build-app.sh` 嵌入完整 Sparkle.framework，补充 `@executable_path/../Frameworks` rpath，按 helper → framework → app 顺序签名，保留 helper entitlements。缺少 framework 时构建直接失败。
- `SUVerifyUpdateBeforeExtraction=true`，下载在解压前必须通过验证。默认不静默下载或重启，也不上传系统画像。
- 公开 feed 固定为仓库 main 的 `appcast.xml`。初始 feed 有效但没有更新条目；不能把仍不含更新器的旧包填入新 feed。

## 每次发布

1. 从已验证的发布提交构建。修改 `CFBundleShortVersionString`、严格递增的 `CFBundleVersion` 和 `TypelessUpdateChannel`（`beta` 或 `stable`），同步 verify 脚本的预期版本以及 changelog。Beta tag 必须为 `vX.Y.Z-beta.N`，正式 tag 为 `vX.Y.Z`。
2. `CODE_SIGN_IDENTITY='Developer ID Application: …' make verify`。为 App 完成 Apple notarization 与 staple，然后使用已 stapled App 制作最终 ZIP / DMG。DMG 另行签名、公证和 staple。生成 SHA-256 sidecar。
3. 仅对**最终不会再改变的安装包字节**生成签名与待审查 feed（ZIP 和 DMG 均支持）：

   ```bash
   python3 scripts/update-feed.py prepare dist/TypelessPlusPlus-X.Y.Z-beta.N-macos-arm64.zip \
     --tag vX.Y.Z-beta.N --feed appcast.xml --output dist/appcast.next.xml
   ```

   工具解包检查真实 App 的身份、版本、渠道、feed、公钥、嵌入框架、Developer ID、stapled 票据和 Gatekeeper；核对 Keychain 公钥；用 `sign_update` 签名并回验；保证新 build 大于 feed 内所有 Beta / Stable 项，保留既有条目。签名后修改归档字节必须重新执行。
4. 按正式发布授权上传同一安装包至对应 GitHub Release。准备 feed 不会发布或上传任何内容。
5. 独立验证已公开的下载字节：

   ```bash
   python3 scripts/update-feed.py verify-public dist/appcast.next.xml --build NEXT_BUILD
   ```

   必须通过公开下载长度和 Ed25519 校验，再将 `dist/appcast.next.xml` 作为 `appcast.xml` 发起、审查并合并 feed PR。不要在资产尚未公开或可验证之前推进 feed。
6. 对公开 raw feed 和已安装的旧版客户端检查发现、下载、重启、运行版本；GitHub Release 已存在不等于客户端已收到更新。不能以本地 QA 代替这个发布后验证。

签名工具来自固定 SwiftPM 依赖：`.build/artifacts/sparkle/Sparkle/bin/`。以后构建无需再生成 key；可用 `generate_keys --account typeless-plusplus -p` 读取公钥核对。换机器或 CI 自动发布时需要另行安全配置该项目的签名材料，不要生成新 key 覆盖已有更新信任。

## 隔离客户端 QA

以下脚本只创建新目录，不覆盖 `/Applications`。每次生成独立 bundle ID、旧包 build 1001、新包 build 1002 和本地签名 feed。独立 QA 包才会进入 updater-only 入口，不初始化账号、Typeless AX、Keychain 账号目录或登录项。

```bash
CODE_SIGN_IDENTITY='Developer ID Application: …' make app
python3 scripts/prepare-update-qa.py --port 18761 \
  --identity 'Developer ID Application: …' --output dist/updater-qa-NEW
python3 -m http.server 18761 --bind 127.0.0.1 --directory dist/updater-qa-NEW/server
```

打开 manifest 中的 installed App，确认后台发现不会置前窗口，然后从更新入口下载。准备完成后检查 App 仍是 build 1001；点击「重启并完成更新」，检查原安装路径已替换为 build 1002 且新进程实际启动。再测试手动无更新、失败、Beta/Stable 筛选与自动检查开关。公证环境有额外安全策略时，为 QA 目标包单独公证并重建签名 feed；不得修改正式安装的权限或更新偏好。

QA 后退出独立进程、停止本地 HTTP server。正式发布 feed 不接受 QA 包、localhost、外部仓库、非递增 build 或无效签名字段。

参考：[Sparkle 官方接入文档](https://sparkle-project.org/documentation/)、[编程式初始化](https://sparkle-project.org/documentation/programmatic-setup/)、[更新提醒](https://sparkle-project.org/documentation/gentle-reminders/)、[配置与签名](https://sparkle-project.org/documentation/customization/)。
