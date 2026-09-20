import AppKit
import ApplicationServices

struct AccessibilityPermissionService {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccess() -> Bool {
        // Using the documented key value avoids importing the mutable C global
        // into Swift 6's strict-concurrency model.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
