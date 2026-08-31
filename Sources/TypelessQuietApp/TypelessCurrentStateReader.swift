import AppKit
import ApplicationServices
import Foundation
import TypelessQuietCore

struct TypelessStateReadResult: Sendable {
    let state: CurrentTypelessState
    let storageURL: URL
    let appVersion: String?
    let appRunning: Bool
}

enum TypelessStateReaderError: LocalizedError {
    case storageNotFound

    var errorDescription: String? {
        switch self {
        case .storageNotFound:
            "未找到 Typeless app-storage.json"
        }
    }
}

protocol TypelessCurrentStateReading {
    func read() throws -> TypelessStateReadResult
}

private struct TypelessAXIdentitySet {
    private var buckets: [CFHashCode: [AXUIElement]] = [:]

    mutating func insert(_ element: AXUIElement) -> Bool {
        let hash = CFHash(element)
        if buckets[hash, default: []].contains(where: { CFEqual($0, element) }) {
            return false
        }
        buckets[hash, default: []].append(element)
        return true
    }
}

struct TypelessCurrentStateReader: TypelessCurrentStateReading {
    private let fileManager = FileManager.default

    func read() throws -> TypelessStateReadResult {
        guard let storageURL = storageCandidates.first(where: {
            fileManager.fileExists(atPath: $0.path)
        }) else {
            throw TypelessStateReaderError.storageNotFound
        }

        let data = try Data(contentsOf: storageURL)
        let attributes = try? fileManager.attributesOfItem(atPath: storageURL.path)
        let modifiedAt = attributes?[.modificationDate] as? Date
        let observedAt = Date()
        var state = try TypelessLocalStateParser.parse(
            data: data,
            observedAt: observedAt,
            fileModifiedAt: modifiedAt
        )

        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: TargetPromptMatcher.targetBundleIdentifier
        )
        let liveQuotaDisabled = ProcessInfo.processInfo.environment[
            "TYPELESS_PLUSPLUS_DISABLE_LIVE_QUOTA"
        ] == "true"
        if !liveQuotaDisabled,
           let running = runningApps.first,
           let quota = VisibleQuotaParser.parse(
               accessibilityTexts(processIdentifier: running.processIdentifier),
               observedAt: observedAt
           ) {
            state = state.merging(quota: quota)
        }

        return TypelessStateReadResult(
            state: state,
            storageURL: storageURL,
            appVersion: installedTypelessVersion,
            appRunning: !runningApps.isEmpty
        )
    }

    private var storageCandidates: [URL] {
        if let override = ProcessInfo.processInfo.environment["TYPELESS_PLUSPLUS_TYPELESS_SUPPORT_DIR"] {
            return [URL(fileURLWithPath: override, isDirectory: true)
                .appendingPathComponent("app-storage.json")]
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ["Typeless", "Typeless.exe"].map {
            support.appendingPathComponent($0, isDirectory: true)
                .appendingPathComponent("app-storage.json")
        }
    }

    private var installedTypelessVersion: String? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Typeless.app"),
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Typeless.app"),
        ]
        for appURL in candidates where fileManager.fileExists(atPath: appURL.path) {
            if let bundle = Bundle(url: appURL),
               let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                return version
            }
        }
        return nil
    }

    private func accessibilityTexts(processIdentifier: pid_t) -> [String] {
        let application = AXUIElementCreateApplication(processIdentifier)
        var queue: [(element: AXUIElement, depth: Int)] = [(application, 0)]
        var index = 0
        var seen = TypelessAXIdentitySet()
        var texts: [String] = []
        _ = seen.insert(application)

        while index < queue.count && index < 2_500 {
            let item = queue[index]
            index += 1

            for attribute in ["AXTitle", "AXValue", "AXDescription"] {
                if let text = stringAttribute(attribute, of: item.element), !text.isEmpty {
                    texts.append(text)
                }
            }

            guard item.depth < 24 else { continue }
            for child in childElements(of: item.element) where seen.insert(child) {
                queue.append((child, item.depth + 1))
            }
        }
        return texts
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXChildren" as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == CFArrayGetTypeID()
        else {
            return []
        }
        let array = unsafeBitCast(value, to: CFArray.self)
        return (0 ..< CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            let candidate = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(candidate) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(candidate, to: AXUIElement.self)
        }
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: CFString.self) as String
    }
}
