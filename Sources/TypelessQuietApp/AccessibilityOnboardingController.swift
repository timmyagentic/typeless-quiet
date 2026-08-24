import AppKit
import SwiftUI

@MainActor
final class AccessibilityOnboardingController {
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let contentView = AccessibilityOnboardingView(
            openSettings: { [weak self] in
                self?.openSettings()
            },
            postpone: { [weak self] in
                self?.close()
            }
        )
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "完成 Typeless Quiet 设置"
        window.identifier = NSUserInterfaceItemIdentifier("AccessibilityOnboarding")
        window.contentViewController = NSHostingController(rootView: contentView)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }
}

private struct AccessibilityOnboardingView: View {
    let openSettings: () -> Void
    let postpone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("允许 Typeless Quiet 控制 Typeless")
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text("请在系统设置中开启 Typeless Quiet 的“设备控制和数据访问”权限。部分 macOS 版本会将它显示为“辅助功能”。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text("此权限只用于读取 Typeless 的界面结构，并精确关闭指定的升级提示；其他通知不会被操作。")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.shield")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(spacing: 10) {
                Button("打开系统设置", action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                Button("稍后", action: postpone)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(32)
        .frame(width: 420)
    }
}
