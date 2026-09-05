import AppKit
import Combine
import Sparkle
import TypelessQuietCore

/// Sparkle owns scheduling, signature verification and installation. This bridge
/// gives background discovery a quiet badge and makes relaunch an explicit action.
@MainActor
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver {
    enum Phase: Equatable {
        case idle, checking, available, downloading, extracting, ready, installing, upToDate, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var available: AvailableUpdate?
    @Published private(set) var canCheck = false
    @Published private(set) var automaticChecks = false
    @Published private(set) var channel: UpdateChannel
    @Published private(set) var lastCheck: Date?
    @Published private(set) var progress: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var canCancel = false
    let currentVersion: String
    let currentBuild: String
    var onPresent: (() -> Void)?

    private let defaults: UserDefaults
    private let bundle: Bundle
    private var updater: SPUUpdater?
    private var cancellables: Set<AnyCancellable> = []
    private var intent = UpdateCheckIntent()
    private var cancellation: (() -> Void)?
    private var installReply: ((SPUUserUpdateChoice) -> Void)?
    private var retryTermination: (() -> Void)?
    private var totalBytes: UInt64 = 0
    private var downloadedBytes: UInt64 = 0
    private var userInitiated = false
    private let availabilityKey = "TypelessPlusPlus.UpdateAvailability.v1"
    private let channelKey = "TypelessPlusPlus.UpdateChannel"
    private lazy var window = UpdateWindowController(updater: self)

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard, start: Bool = true) {
        self.bundle = bundle
        self.defaults = defaults
        currentVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        currentBuild = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        channel = .resolve(saved: defaults.string(forKey: channelKey),
                           bundled: bundle.object(forInfoDictionaryKey: "TypelessUpdateChannel") as? String)
        super.init()
        if let data = defaults.data(forKey: availabilityKey),
           let saved = try? JSONDecoder().decode(AvailableUpdate.self, from: data),
           saved.isNewer(than: currentBuild, channel: channel) {
            available = saved
            phase = .available
        } else {
            defaults.removeObject(forKey: availabilityKey)
        }
        guard start else { return }
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed),
              url.scheme == "https" || (Self.isIsolatedQA(bundle) && url.scheme == "http" && url.host == "127.0.0.1"),
              let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: publicKey)?.count == 32 else {
            phase = .failed
            errorMessage = "此构建缺少有效的更新配置。"
            return
        }
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheck)
        do {
            try updater.start()
        } catch {
            phase = .failed
            errorMessage = "无法启动更新器：\(error.localizedDescription)"
        }
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.checkInBackgroundIfNeeded() }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.checkInBackgroundIfNeeded() }.store(in: &cancellables)
        // App initialization can precede NSApplication's finished-launching event.
        DispatchQueue.main.async { [weak self] in self?.checkInBackgroundIfNeeded() }
    }

    static func isIsolatedQA(_ bundle: Bundle) -> Bool {
        bundle.object(forInfoDictionaryKey: "TypelessUpdaterQA") as? Bool == true
            && bundle.bundleIdentifier?.hasPrefix("io.github.timmyagentic.TypelessUpdaterQA.") == true
    }

    var isBusy: Bool { [.checking, .downloading, .extracting, .ready, .installing].contains(phase) }
    var hasUpdate: Bool { available != nil }
    var message: String {
        switch phase {
        case .idle: return "自动检查更新，发现新版本时在应用内提醒。"
        case .checking: return "正在检查更新…"
        case .available: return "发现新版本 \(available?.version ?? "")"
        case .downloading: return "正在下载更新…"
        case .extracting: return "正在校验并准备更新…"
        case .ready: return "更新已准备好，重启 Typeless++ 即可完成。"
        case .installing: return "正在安装更新…"
        case .upToDate: return "当前已是所选渠道的最新版本。"
        case .failed: return errorMessage ?? "更新失败，请稍后重试。"
        }
    }

    func present() {
        if let onPresent { onPresent() } else { window.show() }
    }

    func checkNow() {
        guard canCheck, !isBusy else { present(); return }
        intent.reset()
        userInitiated = true
        updater?.checkForUpdates()
    }

    func installAvailableUpdate() {
        guard phase != .ready, phase != .installing else { present(); return }
        guard canCheck, !isBusy else { present(); return }
        // Revalidate the feed, even for a badge restored from an earlier launch.
        intent.requestDirectInstall()
        userInitiated = true
        updater?.checkForUpdates()
    }

    func checkInBackgroundIfNeeded(now: Date = Date()) {
        guard let updater, !isBusy, UpdatePolicy.shouldCheck(
            automatic: updater.automaticallyChecksForUpdates, canCheck: updater.canCheckForUpdates,
            lastCheck: updater.lastUpdateCheckDate, now: now
        ) else { return }
        userInitiated = false
        updater.checkForUpdatesInBackground()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func setChannel(_ newChannel: UpdateChannel) {
        guard canCheck, !isBusy, newChannel != channel else { return }
        channel = newChannel
        defaults.set(newChannel.rawValue, forKey: channelKey)
        recordAvailability(nil)
        phase = .idle
        updater?.resetUpdateCycle()
        checkNow()
    }

    func cancel() {
        guard let reply = cancellation else { return }
        clearCallbacks()
        intent.reset()
        phase = available == nil ? .idle : .available
        reply()
    }

    func installAndRelaunch() {
        let reply = installReply
        installReply = nil
        guard let reply else { return }
        phase = .installing
        reply(.install)
    }

    func installLater() {
        let reply = installReply
        installReply = nil
        phase = .available
        reply?(.dismiss)
    }

    func retryRelaunch() { retryTermination?() }

    private func clearCallbacks() {
        cancellation = nil
        canCancel = false
        installReply = nil
        retryTermination = nil
    }

    private func recordAvailability(_ update: AvailableUpdate?) {
        available = update
        if let update, let data = try? JSONEncoder().encode(update) {
            defaults.set(data, forKey: availabilityKey)
        } else {
            defaults.removeObject(forKey: availabilityKey)
        }
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel.allowedChannels }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        intent.reset()
        clearCallbacks()
        if let error = error as NSError? {
            if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) {
                recordAvailability(nil)
                phase = .upToDate
            } else {
                errorMessage = error.localizedDescription
                phase = .failed
            }
        }
        userInitiated = false
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiated = true
        self.cancellation = cancellation
        canCancel = true
        errorMessage = nil
        phase = .checking
        present()
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        receiveDiscovery(AvailableUpdate(version: item.displayVersionString, build: item.versionString,
                         channel: item.channel == "beta" ? .beta : .stable),
                         userInitiated: state.userInitiated, recoveredInstallation: state.stage == .installing,
                         reply: reply)
    }

    // Kept separate from Sparkle's immutable input objects for callback lifecycle tests.
    func receiveDiscovery(_ update: AvailableUpdate, userInitiated: Bool,
                          recoveredInstallation: Bool, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearCallbacks()
        let directInstall = intent.consumeDirectInstall()
        guard update.isNewer(than: currentBuild, channel: channel) else {
            recordAvailability(nil)
            phase = .upToDate
            reply(.dismiss)
            return
        }
        recordAvailability(update)
        if recoveredInstallation {
            // An .install here can immediately terminate the app; require a fresh click.
            phase = .ready
            installReply = reply
            if userInitiated { present() }
        } else if directInstall {
            phase = .downloading
            reply(.install)
        } else {
            phase = .available
            if userInitiated { present() }
            reply(.dismiss)
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        intent.reset()
        clearCallbacks()
        recordAvailability(nil)
        phase = .upToDate
        if userInitiated { present() }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        intent.reset()
        clearCallbacks()
        phase = .failed
        errorMessage = error.localizedDescription
        if userInitiated { present() }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        canCancel = true
        totalBytes = 0
        downloadedBytes = 0
        progress = 0
        phase = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        totalBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        downloadedBytes += length
        progress = totalBytes == 0 ? 0 : min(1, Double(downloadedBytes) / Double(totalBytes))
    }

    func showDownloadDidStartExtractingUpdate() {
        // Sparkle invalidates the download cancellation callback before extraction.
        cancellation = nil
        canCancel = false
        phase = .extracting
        progress = 0
    }

    func showExtractionReceivedProgress(_ progress: Double) { self.progress = progress }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        clearCallbacks()
        installReply = reply
        phase = .ready
        present()
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        clearCallbacks()
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
        phase = .installing
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        recordAvailability(nil)
        clearCallbacks()
        phase = .upToDate
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        clearCallbacks()
        intent.reset()
        if isBusy { phase = available == nil ? .idle : .available }
    }

    func showUpdateInFocus() { present() }
}
