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

            if let lastDismissal = model.lastDismissal {
                Text("上次关闭：\(lastDismissal.formatted(date: .abbreviated, time: .standard))")
            }

            if let issueText = model.issueText {
                Text(issueText)
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
