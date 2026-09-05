import AppKit
import SwiftUI
import TypelessQuietCore

@MainActor
final class UpdateWindowController {
    private let updater: UpdaterController
    private var window: NSWindow?

    init(updater: UpdaterController) { self.updater = updater }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: .zero,
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "Typeless++ 更新"
            window.identifier = NSUserInterfaceItemIdentifier("TypelessUpdateWindow")
            window.contentViewController = NSHostingController(rootView: UpdateView(updater: updater))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct UpdateView: View {
    @ObservedObject var updater: UpdaterController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Typeless++ 更新").font(.title2.bold())
                    Text("当前版本 \(updater.currentVersion)（\(updater.currentBuild)）")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text(updater.message).font(.headline).fixedSize(horizontal: false, vertical: true)
                if [.downloading, .extracting].contains(updater.phase) {
                    ProgressView(value: updater.progress)
                        .accessibilityLabel(updater.phase == .downloading ? "下载进度" : "准备进度")
                } else if updater.phase == .checking || updater.phase == .installing {
                    ProgressView().controlSize(.small)
                }
                HStack {
                    if updater.phase == .ready {
                        Button("重启并完成更新", action: updater.installAndRelaunch)
                            .buttonStyle(.borderedProminent)
                        Button("稍后", action: updater.installLater)
                    } else if updater.phase == .installing {
                        Button("重试重启", action: updater.retryRelaunch)
                    } else if updater.hasUpdate && !updater.isBusy {
                        Button("下载并更新", action: updater.installAvailableUpdate)
                            .buttonStyle(.borderedProminent).disabled(!updater.canCheck)
                    } else if !updater.isBusy {
                        Button("检查更新", action: updater.checkNow)
                            .buttonStyle(.borderedProminent).disabled(!updater.canCheck)
                    }
                    if updater.canCancel { Button("取消", action: updater.cancel) }
                    Spacer()
                    Link("版本说明", destination: URL(string: "https://github.com/timmyagentic/typeless-plusplus/releases")!)
                }
                Text("下载与校验完成后提示重启；关闭此窗口不会中断下载。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            Toggle("自动检查更新", isOn: Binding(get: { updater.automaticChecks }, set: updater.setAutomaticChecks))
                .toggleStyle(.switch).disabled(!updater.canCheck || updater.isBusy)
            Picker("更新渠道", selection: Binding(get: { updater.channel }, set: updater.setChannel)) {
                ForEach(UpdateChannel.allCases, id: \.self) { Text($0.title).tag($0) }
            }.disabled(!updater.canCheck || updater.isBusy)
            if let date = updater.lastCheck {
                Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct UpdateMenu: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        if updater.hasUpdate {
            Button(updater.phase == .ready ? "更新已就绪…" : "有可用更新…") {
                updater.installAvailableUpdate()
            }
        }
        Button("检查更新…", action: updater.checkNow)
        Button("更新设置…", action: updater.present)
    }
}

struct UpdateBadge: View {
    @ObservedObject var updater: UpdaterController
    var body: some View {
        Button {
            if updater.hasUpdate { updater.installAvailableUpdate() } else { updater.present() }
        } label: {
            Label(updater.hasUpdate ? "有可用更新" : "更新", systemImage: "arrow.down.circle")
        }
        .help(updater.message)
    }
}
