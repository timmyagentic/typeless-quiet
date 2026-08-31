# Typeless++ 产品路线图

## 产品承诺

Typeless++ 是一个本地、原生、安装后即可工作的 Typeless 增强层：

1. 自动消除已知的瞬时升级提示，不要求用户学习规则或运行诊断流程。
2. 清楚显示当前 Typeless 账号、剩余额度和增强功能状态。
3. 在用户自己的既有账号之间提供可验证、可回滚的切换。
4. 所有秘密只进入 macOS Keychain；失败时保留当前可用账号并明确说明原因。

当前代码已完成第 1 项和 P1 账号与额度基础层。P2–P4 按下面阶段继续实现，不能把后续
规划写成已交付功能。

## 参考项目与取舍

路线图参考 MIT 项目 [fufu1209/Typeless](https://github.com/fufu1209/Typeless)
commit `f26f798eb7d9ff4331334f3d0725d17c629368d0` 的账号池、额度状态、Keychain、
切换后验证和守护思路，但不复制其源码。

该项目还包含 Playwright 批量注册、邮箱验证码、明文 token 提取后生成桌面登录协议、
会话文件注入、删除 Typeless Keychain/device.cache、轮换设备身份和 onboarding 文件补丁。
这些能力侵入 Typeless 私有状态、升级兼容风险高，也容易把产品目标变成额度规避，因此
不进入 Typeless++ 的默认能力或自动回退链。

## P0：现有 Quiet 能力

- Typeless 进程与辅助功能权限状态。
- 旧版和 Typeless 2.4.0 瞬时升级提示的精确匹配与自动关闭。
- 唯一目标、唯一关闭按钮、动作前复验和 fail-closed。
- 菜单栏、原生主窗口、登录时启动、最近一次关闭与错误状态。
- Developer ID、notarization、Gatekeeper 和可复现发布链。

## P1：账号与额度基础层（已实现）

### 用户功能

- “概览”展示当前账号、剩余额度、最后同步时间、Quiet 状态和下一步建议。
- “账号”页允许用户手动添加自己已有的账号：显示名称、邮箱、备注、是否参与自动切换。
- 只读识别当前 Typeless 登录账号和本地额度；读取失败时显示 `未知`，不猜测。
- 菜单栏快速查看当前账号与额度，并打开账号列表。
- 本地账号搜索、排序、停用、删除和重复邮箱检查。
- 环境自检：Typeless 安装、版本、运行状态、权限、当前登录态是否可读。

当前实现说明：Typeless 2.4.0 身份来自 `app-storage.json` 的显式白名单字段，额度优先
来自可见 Accessibility 文本；当前界面未暴露额度时显示“未知”。P1 不包含切换动作。

### 数据边界

- 普通数据文件只保存账号 UUID、显示名称、标准化邮箱、备注、状态、额度快照和时间戳。
- 密码或未来可能需要的授权材料只写入 Keychain，并以账号 UUID 引用。
- 不保存 access token、refresh token、Cookie、验证码或 Typeless 设备标识。
- 日志默认脱敏邮箱，不记录输入内容和任何秘密。

### 核心模型

```text
AccountProfile
  id, displayName, normalizedEmail, note
  enabled, switchEligibility
  quotaSnapshot(remaining, limit, observedAt, source)
  lastSeenAt, lastSwitchResult

CurrentTypelessState
  appVersion, running, recording
  accountIdentity, quotaSnapshot, freshness
```

## P2：安全的一键手动切换

### 集成顺序

1. 优先验证 Typeless 官方网页登录、handoff 或公开 deep link 能否完成既有账号切换。
2. 如果官方路径需要交互，Typeless++ 只负责打开正确页面、选择账号资料并跟踪结果。
3. 如果官方路径无法无损切换，保留“退出当前账号并打开登录页”的明确降级，不注入 token。

### 事务状态机

```text
idle → preflight → requestingSwitch → verifying → succeeded
                                     └──────────→ failed → restoring
```

- Preflight 检查 Typeless 未在录音/处理转录、目标账号启用、当前状态新鲜。
- 切换前保存非敏感的当前账号/额度快照，不删除 Typeless 数据、Keychain 或缓存。
- 只有重新读取到目标邮箱并拿到新鲜额度，才把切换标记为成功。
- 验证失败时保留原账号状态，并提供重试或打开官方登录页；不能把动作返回成功当成切换成功。
- 每次结果写入本地审计：来源、目标账号 UUID、时间、阶段、结果和脱敏错误。

### UX

- 主窗口账号行提供“一键切换”；菜单栏提供最近账号的快速入口。
- 当前账号、不可切换账号和额度未知账号必须清晰区分。
- 默认不弹技术日志；失败时给出可执行的单句说明和“查看详情”。

## P3：可选的低额度守护

- 默认关闭，用户显式开启并设置阈值、账号池和冷却时间。
- 只在额度数据新鲜、Typeless 空闲、目标账号已验证且当前账号低于阈值时切换。
- 账号池为空、数据陈旧、正在录音、切换歧义或连续失败时 fail closed。
- 每轮最多切换一次；指数退避，禁止循环抖动。
- 可以提示“即将切换”或选择完全安静模式，但历史中始终可追溯。
- 不自动注册账号，不调用邮箱验证码服务，不创建“热备新号”。

## P4：备份、恢复与可移植性

- 导出不含秘密的账号元数据和规则 JSON，带 schema version。
- 可选加密导出由用户显式设置密码；默认导出不包含 Keychain 内容。
- 新设备导入后要求重新完成官方登录/授权，不复制设备身份。
- 账号与规则迁移、冲突合并、回滚和旧 schema 升级均有自动化测试。

## 明确非目标

- 自动或批量注册 Typeless 账号。
- 接收验证码、破解 CAPTCHA/Turnstile 或维护自建邮箱服务。
- 绕过、重置或规避免费额度与订阅限制。
- 提取、保存或注入 access token / refresh token / Cookie。
- 删除或轮换 Typeless 的 Keychain 凭据、`device.cache` 或设备身份。
- 修改 Typeless 的 `app-storage.json`、onboarding 文件、应用包或前端 DOM。
- 页面变化后自动降级为坐标点击或未经验证的破坏性脚本。

## 建议代码边界

```text
TypelessQuietCore (保留现有兼容 target 名)
  Quiet matching, account domain, quota freshness, switch state machine

TypelessQuietApp
  Menu bar, Overview, Accounts, Rules, Diagnostics

TypelessIntegration
  Read-only current-state adapter, official login/handoff adapter

SecureStore
  Keychain references and redacted persistence
```

先把账号领域模型、只读状态和切换状态机做成纯 Swift Core；AppKit/AX、Keychain 与网络适配
放在边缘层，确保绝大多数安全边界可以用无凭证单元测试覆盖。

## 每阶段完成门禁

- 聚焦 RED→GREEN 回归与完整 `make verify`。
- Debug/Release warnings-as-errors。
- 账号秘密扫描：测试 fixture、日志、文档、Git diff 均不得包含真实凭证。
- 切换前后必须读取真实客户端状态；UI 动作成功不等于账号切换成功。
- Developer ID 本机 QA；正式发布另行完成 notarization、Gatekeeper 与远端回下载。
- 未现场观察到的 Typeless 行为明确标记 `UNVERIFIED`。
