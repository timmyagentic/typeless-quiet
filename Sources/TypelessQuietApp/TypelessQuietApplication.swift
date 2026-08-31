import SwiftUI

@main
struct TypelessQuietApplication: App {
    @NSApplicationDelegateAdaptor(TypelessQuietAppDelegate.self)
    private var appDelegate
    @StateObject private var model: QuietModel

    init() {
        let model = QuietModel()
        _model = StateObject(wrappedValue: model)
        MainWindowRequestRouter.handler = { [weak model] in
            model?.showPrimaryInterface()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text(model.statusText)

            if let accountSummary = model.accountManager.menuSummary {
                Text(accountSummary)
            }

            if let operation = model.switchCoordinator.operation {
                Text(operation.menuSummary(accounts: model.accountManager.accounts))
            }

            if let lastDismissal = model.lastDismissal {
                Text("上次关闭：\(lastDismissal.formatted(date: .abbreviated, time: .standard))")
            }

            if let issueText = model.issueText {
                Text(issueText)
            }

            Divider()

            Button("刷新账号与额度") {
                model.accountManager.refresh()
            }

            let switchableAccounts = model.accountManager.accounts.filter {
                $0.status == .available && $0.email != model.accountManager.currentState?.email
            }
            if !switchableAccounts.isEmpty {
                Menu("安全切换账号") {
                    ForEach(switchableAccounts) { account in
                        Button(account.displayName) {
                            model.switchCoordinator.startSwitch(to: account.id)
                        }
                        .disabled(model.switchCoordinator.isBusy)
                    }
                }
            }

            if model.switchCoordinator.isBusy {
                Button("取消切换并恢复") {
                    model.switchCoordinator.cancelAndRestore()
                }
            }

            Divider()

            Button("打开 Typeless++") {
                model.showPrimaryInterface()
            }

            Divider()

            Toggle(
                "启用自动关闭",
                isOn: Binding(
                    get: { model.isEnabled },
                    set: { model.setEnabled($0) }
                )
            )

            if model.accessibilityGranted {
                Label("辅助功能权限已授予", systemImage: "checkmark.shield")
            } else {
                Button("显示授权引导…") {
                    model.showAccessibilityOnboarding()
                }
                Button("打开辅助功能设置") {
                    model.openAccessibilitySettings()
                }
            }

            Toggle(
                "登录时启动",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )

            if model.launchAtLoginRequiresApproval {
                Label("登录项等待系统设置批准", systemImage: "exclamationmark.circle")
            }

            Button("打开登录项设置") {
                model.openLoginItemSettings()
            }

            Divider()

            Button("退出 Typeless++") {
                model.quit()
            }
        } label: {
            Label("Typeless++", systemImage: model.statusSymbol)
        }
        .menuBarExtraStyle(.menu)
    }
}
