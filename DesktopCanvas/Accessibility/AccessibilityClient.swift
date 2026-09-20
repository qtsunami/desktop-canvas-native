import AppKit
import ApplicationServices

struct RunningWindow: Identifiable {
    let id: String
    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String
    let appIcon: NSImage?
    let title: String
    let frame: CGRect
    let isMinimized: Bool
    let isFullScreen: Bool
    let canMove: Bool
    let canResize: Bool

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名窗口" : trimmed
    }

    var menuTitle: String {
        "\(appName) — \(displayTitle)"
    }

    var canLayout: Bool {
        canMove && canResize && !isFullScreen
    }
}

struct WindowEnumerationResult {
    let windows: [RunningWindow]
    let warnings: [String]
}

struct WindowSnapshot {
    let id: String
    let element: AXUIElement
    let title: String
    let frame: CGRect
    let wasMinimized: Bool
}

enum AccessibilityClientError: LocalizedError {
    case operationFailed(operation: String, error: AXError)
    case missingFrame(title: String)
    case attributeNotSettable(title: String, attribute: String)

    var errorDescription: String? {
        switch self {
        case let .operationFailed(operation, error):
            return "\(operation)失败（AX 错误 \(error.rawValue)）"
        case let .missingFrame(title):
            return "无法读取“\(title)”的位置或尺寸"
        case let .attributeNotSettable(title, attribute):
            return "“\(title)”不允许修改\(attribute)"
        }
    }
}

final class AccessibilityClient {
    private let fullScreenAttribute = "AXFullScreen"

    func enumerateWindows() -> WindowEnumerationResult {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSWorkspace.shared.runningApplications
            .filter { application in
                application.processIdentifier != currentPID
                    && application.activationPolicy == .regular
                    && !application.isTerminated
            }

        var windows: [RunningWindow] = []
        var warnings: [String] = []

        for application in applications {
            let appElement = AXUIElementCreateApplication(application.processIdentifier)
            // A single unresponsive application must not freeze the whole window list.
            // The timeout applies to Accessibility messages sent to this process.
            _ = AXUIElementSetMessagingTimeout(appElement, 0.25)
            var rawWindows: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                appElement,
                kAXWindowsAttribute as CFString,
                &rawWindows
            )

            guard error == .success else {
                if error != .noValue {
                    warnings.append(
                        "无法读取 \(application.localizedName ?? "未知应用") 的窗口（AX \(error.rawValue)）"
                    )
                }
                continue
            }

            guard let windowElements = rawWindows as? [AXUIElement] else {
                continue
            }

            for element in windowElements {
                guard stringAttribute(element, kAXRoleAttribute) == kAXWindowRole else {
                    continue
                }
                guard let frame = frame(of: element), frame.width >= 120, frame.height >= 80 else {
                    continue
                }

                let title = stringAttribute(element, kAXTitleAttribute) ?? ""
                let identifier = "\(application.processIdentifier):\(CFHash(element))"
                let canMove = isSettable(element, attribute: kAXPositionAttribute)
                let canResize = isSettable(element, attribute: kAXSizeAttribute)

                windows.append(
                    RunningWindow(
                        id: identifier,
                        element: element,
                        pid: application.processIdentifier,
                        appName: application.localizedName ?? "未知应用",
                        bundleIdentifier: application.bundleIdentifier ?? "unknown.\(application.processIdentifier)",
                        appIcon: application.icon,
                        title: title,
                        frame: frame,
                        isMinimized: boolAttribute(element, kAXMinimizedAttribute) ?? false,
                        isFullScreen: boolAttribute(element, fullScreenAttribute) ?? false,
                        canMove: canMove,
                        canResize: canResize
                    )
                )
            }
        }

        return WindowEnumerationResult(windows: windows, warnings: warnings)
    }

    func snapshot(of window: RunningWindow) throws -> WindowSnapshot {
        let currentFrame = try currentFrame(of: window)
        return WindowSnapshot(
            id: window.id,
            element: window.element,
            title: window.menuTitle,
            frame: currentFrame,
            wasMinimized: boolAttribute(window.element, kAXMinimizedAttribute) ?? false
        )
    }

    func currentFrame(of window: RunningWindow) throws -> CGRect {
        guard let currentFrame = frame(of: window.element) else {
            throw AccessibilityClientError.missingFrame(title: window.menuTitle)
        }
        return currentFrame
    }

    func isMinimized(_ window: RunningWindow) -> Bool {
        boolAttribute(window.element, kAXMinimizedAttribute) ?? false
    }

    func isFullScreen(_ window: RunningWindow) -> Bool {
        boolAttribute(window.element, fullScreenAttribute) ?? false
    }

    func canSetFullScreen(_ window: RunningWindow) -> Bool {
        isSettable(window.element, attribute: fullScreenAttribute)
    }

    func setFullScreen(_ fullScreen: Bool, for window: RunningWindow) throws {
        guard canSetFullScreen(window) else {
            throw AccessibilityClientError.attributeNotSettable(
                title: window.menuTitle,
                attribute: "全屏状态"
            )
        }

        let error = AXUIElementSetAttributeValue(
            window.element,
            fullScreenAttribute as CFString,
            fullScreen ? kCFBooleanTrue : kCFBooleanFalse
        )
        guard error == .success else {
            throw AccessibilityClientError.operationFailed(
                operation: "更新“\(window.menuTitle)”的系统全屏状态",
                error: error
            )
        }
    }

    @discardableResult
    func exitFullScreenIfNeeded(_ window: RunningWindow) throws -> Bool {
        guard isFullScreen(window) else { return false }
        try setFullScreen(false, for: window)
        return true
    }

    func setFrame(_ frame: CGRect, for window: RunningWindow) throws {
        guard isSettable(window.element, attribute: kAXPositionAttribute) else {
            throw AccessibilityClientError.attributeNotSettable(
                title: window.menuTitle,
                attribute: "位置"
            )
        }
        guard isSettable(window.element, attribute: kAXSizeAttribute) else {
            throw AccessibilityClientError.attributeNotSettable(
                title: window.menuTitle,
                attribute: "尺寸"
            )
        }

        if isMinimized(window) {
            try setMinimized(false, for: window.element, title: window.menuTitle)
        }

        try setPoint(frame.origin, on: window.element, title: window.menuTitle)
        try setSize(frame.size, on: window.element, title: window.menuTitle)
        // Some apps constrain size by moving the window. A final position write keeps
        // the requested split anchored without entering a retry loop.
        try setPoint(frame.origin, on: window.element, title: window.menuTitle)
    }

    func restore(_ snapshot: WindowSnapshot) throws {
        try setPoint(snapshot.frame.origin, on: snapshot.element, title: snapshot.title)
        try setSize(snapshot.frame.size, on: snapshot.element, title: snapshot.title)
        try setPoint(snapshot.frame.origin, on: snapshot.element, title: snapshot.title)
        if snapshot.wasMinimized {
            try setMinimized(true, for: snapshot.element, title: snapshot.title)
        }
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        if let value = copyAttribute(element, attribute) as? Bool {
            return value
        }
        if let number = copyAttribute(element, attribute) as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard
            let rawPositionValue = copyAttribute(element, kAXPositionAttribute),
            let rawSizeValue = copyAttribute(element, kAXSizeAttribute),
            CFGetTypeID(rawPositionValue) == AXValueGetTypeID(),
            CFGetTypeID(rawSizeValue) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionValue = rawPositionValue as! AXValue
        let sizeValue = rawSizeValue as! AXValue
        guard
            AXValueGetType(positionValue) == .cgPoint,
            AXValueGetType(sizeValue) == .cgSize
        else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &point),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: point, size: size)
    }

    private func isSettable(_ element: AXUIElement, attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        )
        return error == .success && settable.boolValue
    }

    private func setPoint(_ point: CGPoint, on element: AXUIElement, title: String) throws {
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else {
            throw AccessibilityClientError.missingFrame(title: title)
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            value
        )
        guard error == .success else {
            throw AccessibilityClientError.operationFailed(
                operation: "设置“\(title)”的位置",
                error: error
            )
        }
    }

    private func setSize(_ size: CGSize, on element: AXUIElement, title: String) throws {
        var mutableSize = size
        guard let value = AXValueCreate(.cgSize, &mutableSize) else {
            throw AccessibilityClientError.missingFrame(title: title)
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            value
        )
        guard error == .success else {
            throw AccessibilityClientError.operationFailed(
                operation: "设置“\(title)”的尺寸",
                error: error
            )
        }
    }

    private func setMinimized(_ minimized: Bool, for element: AXUIElement, title: String) throws {
        guard isSettable(element, attribute: kAXMinimizedAttribute) else {
            return
        }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXMinimizedAttribute as CFString,
            minimized ? kCFBooleanTrue : kCFBooleanFalse
        )
        guard error == .success else {
            throw AccessibilityClientError.operationFailed(
                operation: "更新“\(title)”的最小化状态",
                error: error
            )
        }
    }
}
