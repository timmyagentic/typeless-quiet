import ApplicationServices
import Foundation
import TypelessQuietCore

enum AXScanFailure: Error, Equatable {
    case applicationTraversalLimitExceeded
    case cardTraversalLimitExceeded
}

struct CapturedTooltip {
    let snapshot: AXNodeSnapshot
    let elementsByPath: [AXNodePath: AXUIElement]
}

// Accessibility descendants form a graph in some Electron apps. Track CF identity so
// shared or cyclic elements are visited once instead of exhausting traversal limits.
private struct AXElementIdentitySet {
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

struct AccessibilityElementReader {
    private let maximumApplicationNodes = 2_500
    private let maximumApplicationDepth = 24
    private let maximumCardNodes = 256
    private let maximumCardDepth = 12

    func windowElements(in application: AXUIElement) -> [AXUIElement] {
        guard let rawValue = attribute("AXWindows", of: application) else {
            return []
        }
        return elementArray(from: rawValue)
    }

    func tooltipElements(in application: AXUIElement) -> Result<[AXUIElement], AXScanFailure> {
        var queue: [(element: AXUIElement, depth: Int)] = [(application, 0)]
        var index = 0
        var tooltips: [AXUIElement] = []
        var seen = AXElementIdentitySet()
        _ = seen.insert(application)

        while index < queue.count {
            guard index < maximumApplicationNodes else {
                return .failure(.applicationTraversalLimitExceeded)
            }

            let item = queue[index]
            index += 1

            if stringAttribute("AXRole", of: item.element) == TargetPromptMatcher.targetCardRole {
                tooltips.append(item.element)
            }

            if item.depth < maximumApplicationDepth {
                for child in childElements(of: item.element) where seen.insert(child) {
                    queue.append((element: child, depth: item.depth + 1))
                }
            }
        }

        return .success(tooltips)
    }

    func capture(_ tooltip: AXUIElement) -> Result<CapturedTooltip, AXScanFailure> {
        var visited = 0
        var elementsByPath: [AXNodePath: AXUIElement] = [:]
        var seen = AXElementIdentitySet()
        _ = seen.insert(tooltip)

        do {
            let rootPath = AXNodePath()
            let snapshot = try captureNode(
                tooltip,
                path: rootPath,
                depth: 0,
                visited: &visited,
                seen: &seen,
                elementsByPath: &elementsByPath
            )
            return .success(CapturedTooltip(
                snapshot: snapshot,
                elementsByPath: elementsByPath
            ))
        } catch {
            return .failure(.cardTraversalLimitExceeded)
        }
    }

    private func captureNode(
        _ element: AXUIElement,
        path: AXNodePath,
        depth: Int,
        visited: inout Int,
        seen: inout AXElementIdentitySet,
        elementsByPath: inout [AXNodePath: AXUIElement]
    ) throws -> AXNodeSnapshot {
        guard visited < maximumCardNodes, depth <= maximumCardDepth else {
            throw AXScanFailure.cardTraversalLimitExceeded
        }

        visited += 1
        elementsByPath[path] = element

        let children = childElements(of: element).filter { seen.insert($0) }
        let childSnapshots = try children.enumerated().map { index, child in
            try captureNode(
                child,
                path: path.appending(index),
                depth: depth + 1,
                visited: &visited,
                seen: &seen,
                elementsByPath: &elementsByPath
            )
        }

        return AXNodeSnapshot(
            role: stringAttribute("AXRole", of: element),
            title: stringAttribute("AXTitle", of: element),
            value: stringAttribute("AXValue", of: element),
            elementDescription: stringAttribute("AXDescription", of: element),
            help: stringAttribute("AXHelp", of: element),
            frame: frame(of: element),
            actions: actionNames(of: element),
            children: childSnapshots
        )
    }

    private func childElements(of element: AXUIElement) -> [AXUIElement] {
        guard let rawValue = attribute("AXChildren", of: element) else {
            return []
        }
        return elementArray(from: rawValue)
    }

    private func elementArray(from rawValue: CFTypeRef) -> [AXUIElement] {
        guard CFGetTypeID(rawValue) == CFArrayGetTypeID() else { return [] }
        let array = unsafeBitCast(rawValue, to: CFArray.self)
        return (0 ..< CFArrayGetCount(array)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else {
                return nil
            }
            let value = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                return nil
            }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        guard let rawValue = attribute(name, of: element),
              CFGetTypeID(rawValue) == CFStringGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(rawValue, to: CFString.self) as String
    }

    private func frame(of element: AXUIElement) -> AXFrame? {
        if let rawFrame = attribute("AXFrame", of: element) {
            if let rect = rectValue(rawFrame) {
                return AXFrame(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.size.width,
                    height: rect.size.height
                )
            }
        }

        guard let rawPosition = attribute("AXPosition", of: element),
              let rawSize = attribute("AXSize", of: element)
        else {
            return nil
        }

        guard let point = pointValue(rawPosition),
              let size = sizeValue(rawSize)
        else {
            return nil
        }

        return AXFrame(
            x: point.x,
            y: point.y,
            width: size.width,
            height: size.height
        )
    }

    private func axValue(_ rawValue: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        return unsafeBitCast(rawValue, to: AXValue.self)
    }

    private func rectValue(_ rawValue: CFTypeRef) -> CGRect? {
        guard let value = axValue(rawValue) else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value, .cgRect, &rect) ? rect : nil
    }

    private func pointValue(_ rawValue: CFTypeRef) -> CGPoint? {
        guard let value = axValue(rawValue) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    private func sizeValue(_ rawValue: CFTypeRef) -> CGSize? {
        guard let value = axValue(rawValue) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    private func actionNames(of element: AXUIElement) -> Set<String> {
        var rawNames: CFArray?
        guard AXUIElementCopyActionNames(element, &rawNames) == .success,
              let rawNames
        else {
            return []
        }

        return Set((0 ..< CFArrayGetCount(rawNames)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(rawNames, index) else {
                return nil
            }
            let value = unsafeBitCast(pointer, to: CFTypeRef.self)
            guard CFGetTypeID(value) == CFStringGetTypeID() else {
                return nil
            }
            let rawString = unsafeBitCast(value, to: CFString.self)
            return rawString as String
        })
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
