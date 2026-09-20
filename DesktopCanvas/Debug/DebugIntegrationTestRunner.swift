#if DEBUG
import AppKit
import Foundation

@MainActor
enum DebugIntegrationTestRunner {
    private static var hasStarted = false

    static func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard
            !hasStarted,
            arguments.contains("--integration-test"),
            let reportFlagIndex = arguments.firstIndex(of: "--integration-report"),
            arguments.indices.contains(reportFlagIndex + 1)
        else {
            return
        }

        hasStarted = true
        let reportURL = URL(fileURLWithPath: arguments[reportFlagIndex + 1])

        Task { @MainActor in
            await run(reportURL: reportURL)
            NSApplication.shared.terminate(nil)
        }
    }

    private static func run(reportURL: URL) async {
        var report: [String: Any] = [
            "test": "persistent-accessibility-workspace",
            "ratio": 70,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        let permissionService = AccessibilityPermissionService()
        let trusted = permissionService.isTrusted()
        report["accessibilityTrusted"] = trusted
        guard trusted else {
            report["success"] = false
            report["error"] = "Accessibility permission is not available to this build."
            write(report, to: reportURL)
            return
        }

        let client = AccessibilityClient()
        let enumeration = client.enumerateWindows()
        report["enumeratedWindowCount"] = enumeration.windows.count
        report["enumerationWarningCount"] = enumeration.warnings.count

        guard
            let mainWindow = enumeration.windows.first(where: {
                $0.title == "[DesktopCanvasTest] Main" && $0.canLayout
            }),
            let attentionWindow = enumeration.windows.first(where: {
                $0.title == "[DesktopCanvasTest] Attention" && $0.canLayout
            })
        else {
            report["success"] = false
            report["error"] = "The isolated integration-test windows were not found."
            write(report, to: reportURL)
            return
        }

        let coordinator = WindowCoordinator(accessibilityClient: client)

        do {
            let mainBefore = try client.currentFrame(of: mainWindow)
            let attentionBefore = try client.currentFrame(of: attentionWindow)
            report["mainBefore"] = dictionary(for: mainBefore)
            report["attentionBefore"] = dictionary(for: attentionBefore)

            guard
                let targetScreen = NSScreen.main ?? NSScreen.screens.first,
                let menuBarScreen = NSScreen.screens.first
            else {
                throw DebugIntegrationError.noScreen
            }

            try coordinator.apply(
                mainWindow: mainWindow,
                attentionWindow: attentionWindow,
                ratio: 70,
                mainOnLeft: true,
                targetScreen: targetScreen
            )
            try? await Task.sleep(for: .milliseconds(350))

            let mainAfterLayout = try client.currentFrame(of: mainWindow)
            let attentionAfterLayout = try client.currentFrame(of: attentionWindow)
            report["mainAfterLayout"] = dictionary(for: mainAfterLayout)
            report["attentionAfterLayout"] = dictionary(for: attentionAfterLayout)

            let accessibilityVisibleFrame = ScreenCoordinateMapper.appKitToAccessibility(
                targetScreen.visibleFrame,
                menuBarScreenFrame: menuBarScreen.frame
            )
            let expectedFrames = LayoutEngine.split(
                visibleFrame: accessibilityVisibleFrame,
                mainRatio: 0.70,
                gap: 8,
                mainOnLeft: true
            )
            let layoutMatches = approximatelyEqual(mainAfterLayout, expectedFrames.main)
                && approximatelyEqual(attentionAfterLayout, expectedFrames.attention)
            report["layoutMatchesExpectedFrames"] = layoutMatches

            // Simulate the system or another application expanding each window
            // to the whole usable screen. The active workspace must pull it back
            // into its assigned zone without user intervention.
            try client.setFrame(accessibilityVisibleFrame, for: mainWindow)
            let mainAfterMaximizeRequest = try client.currentFrame(of: mainWindow)
            report["mainAfterMaximizeRequest"] = dictionary(for: mainAfterMaximizeRequest)
            try? await Task.sleep(for: .milliseconds(800))

            let mainAfterConstraint = try client.currentFrame(of: mainWindow)
            report["mainAfterConstraint"] = dictionary(for: mainAfterConstraint)
            let mainMaximumConstrained = approximatelyEqual(
                mainAfterConstraint,
                expectedFrames.main
            )
            report["mainMaximumConstrainedToZone"] = mainMaximumConstrained

            try client.setFrame(accessibilityVisibleFrame, for: attentionWindow)
            let attentionAfterMaximizeRequest = try client.currentFrame(of: attentionWindow)
            report["attentionAfterMaximizeRequest"] = dictionary(
                for: attentionAfterMaximizeRequest
            )
            try? await Task.sleep(for: .milliseconds(800))

            let attentionAfterConstraint = try client.currentFrame(of: attentionWindow)
            report["attentionAfterConstraint"] = dictionary(for: attentionAfterConstraint)
            let attentionMaximumConstrained = approximatelyEqual(
                attentionAfterConstraint,
                expectedFrames.attention
            )
            report["attentionMaximumConstrainedToZone"] = attentionMaximumConstrained

            let supportsSystemFullScreen = client.canSetFullScreen(mainWindow)
            report["systemFullScreenSupported"] = supportsSystemFullScreen
            var systemFullScreenConstrained = true
            if supportsSystemFullScreen {
                try client.setFullScreen(true, for: mainWindow)
                try? await Task.sleep(for: .milliseconds(2_500))

                let mainAfterSystemFullScreen = try client.currentFrame(of: mainWindow)
                report["mainAfterSystemFullScreenAttempt"] = dictionary(
                    for: mainAfterSystemFullScreen
                )
                report["mainRemainsSystemFullScreen"] = client.isFullScreen(mainWindow)
                systemFullScreenConstrained = !client.isFullScreen(mainWindow)
                    && approximatelyEqual(mainAfterSystemFullScreen, expectedFrames.main)
            }
            report["systemFullScreenConstrainedToZone"] = systemFullScreenConstrained

            try coordinator.updateLayout(
                ratio: 60,
                mainOnLeft: false,
                targetScreen: targetScreen
            )
            try? await Task.sleep(for: .milliseconds(350))

            let updatedFrames = LayoutEngine.split(
                visibleFrame: accessibilityVisibleFrame,
                mainRatio: 0.60,
                gap: 8,
                mainOnLeft: false
            )
            let mainAfterLiveUpdate = try client.currentFrame(of: mainWindow)
            let attentionAfterLiveUpdate = try client.currentFrame(of: attentionWindow)
            report["mainAfterLiveUpdate"] = dictionary(for: mainAfterLiveUpdate)
            report["attentionAfterLiveUpdate"] = dictionary(for: attentionAfterLiveUpdate)
            let liveUpdateMatches = approximatelyEqual(mainAfterLiveUpdate, updatedFrames.main)
                && approximatelyEqual(attentionAfterLiveUpdate, updatedFrames.attention)
            report["liveLayoutUpdateMatchesExpectedFrames"] = liveUpdateMatches

            try coordinator.restore()
            try? await Task.sleep(for: .milliseconds(350))

            let mainAfterRestore = try client.currentFrame(of: mainWindow)
            let attentionAfterRestore = try client.currentFrame(of: attentionWindow)
            report["mainAfterRestore"] = dictionary(for: mainAfterRestore)
            report["attentionAfterRestore"] = dictionary(for: attentionAfterRestore)

            let restoreMatches = approximatelyEqual(mainAfterRestore, mainBefore)
                && approximatelyEqual(attentionAfterRestore, attentionBefore)
            report["restoreMatchesOriginalFrames"] = restoreMatches
            report["success"] = layoutMatches
                && mainMaximumConstrained
                && attentionMaximumConstrained
                && systemFullScreenConstrained
                && liveUpdateMatches
                && restoreMatches
        } catch {
            try? coordinator.restore()
            report["success"] = false
            report["error"] = error.localizedDescription
        }

        write(report, to: reportURL)
    }

    private static func approximatelyEqual(
        _ left: CGRect,
        _ right: CGRect,
        tolerance: CGFloat = 2
    ) -> Bool {
        abs(left.origin.x - right.origin.x) <= tolerance
            && abs(left.origin.y - right.origin.y) <= tolerance
            && abs(left.size.width - right.size.width) <= tolerance
            && abs(left.size.height - right.size.height) <= tolerance
    }

    private static func dictionary(for frame: CGRect) -> [String: Double] {
        [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ]
    }

    private static func write(_ report: [String: Any], to url: URL) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: report,
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: url, options: .atomic)
        } catch {
            let message = "Failed to write integration report: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }
}

private enum DebugIntegrationError: LocalizedError {
    case noScreen

    var errorDescription: String? {
        "No display was available for the integration test."
    }
}
#endif
