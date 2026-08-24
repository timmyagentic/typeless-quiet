import AppKit
import ApplicationServices
import Combine
import ServiceManagement

@MainActor
final class QuietModel: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var typelessRunning = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var lastDismissal: Date?
    @Published private(set) var issueText: String?

    private let defaults = UserDefaults.standard
    private let enabledDefaultsKey = "TypelessQuietEnabled"
    private var permissionTimer: Timer?

    private lazy var monitor = TypelessMonitor { [weak self] event in
        self?.handleMonitorEvent(event)
    }

    init() {
        if defaults.object(forKey: enabledDefaultsKey) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: enabledDefaultsKey)
        }

        accessibilityGranted = AXIsProcessTrusted()
        refreshLaunchAtLoginStatus()
        monitor.start()
        monitor.setWatchingAllowed(isEnabled && accessibilityGranted)

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibilityStatus()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    var statusText: String {
        if !isEnabled {
            return "已暂停"
        }
        if !accessibilityGranted {
            return "需要辅助功能权限"
        }
        if typelessRunning {
            return "正在监听 Typeless"
        }
        return "等待 Typeless 启动"
    }

    var statusSymbol: String {
        if issueText != nil {
            return "exclamationmark.triangle.fill"
        }
        if !isEnabled {
            return "pause.circle"
        }
        if accessibilityGranted {
            return "bell.slash.fill"
        }
        return "lock.fill"
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledDefaultsKey)
        issueText = nil
        monitor.setWatchingAllowed(enabled && accessibilityGranted)
    }

    func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            issueText = nil
        } catch {
            issueText = "无法更新登录项：\(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshAccessibilityStatus() {
        let current = AXIsProcessTrusted()
        guard current != accessibilityGranted else { return }
        accessibilityGranted = current
        issueText = nil
        monitor.setWatchingAllowed(isEnabled && current)
    }

    private func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginEnabled = status == .enabled
        launchAtLoginRequiresApproval = status == .requiresApproval
    }

    private func handleMonitorEvent(_ event: TypelessMonitorEvent) {
        switch event {
        case let .runningChanged(running):
            typelessRunning = running
        case let .dismissed(date):
            lastDismissal = date
            issueText = nil
        case let .unsafe(message):
            issueText = "规则已安全跳过：\(message)"
        case let .error(message):
            issueText = message
        }
    }
}
