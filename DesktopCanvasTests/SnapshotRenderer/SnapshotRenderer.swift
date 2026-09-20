import AppKit
import ApplicationServices
import SwiftUI

@main
@MainActor
enum SnapshotRenderer {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else {
            throw SnapshotError.invalidArguments
        }

        let requestedMode = arguments[1]
        let isDark = requestedMode.hasSuffix("-dark")
        let mode = requestedMode.replacingOccurrences(of: "-dark", with: "")
        let outputURL = URL(fileURLWithPath: arguments[2])
        let model = AppModel()

        switch mode {
        case "permission":
            model.permissionState = .required
            model.statusMessage = "授权后才能查看和调整其他应用窗口"
        case "workspace":
            configureWorkspaceFixture(model)
        case "workspace-active":
            configureWorkspaceFixture(model)
            model.isWorkspaceActive = true
            model.statusMessage = "工作台运行中：主任务最多 70%，关注任务最多 30%"
        default:
            throw SnapshotError.invalidArguments
        }

        let content = MainView()
            .environmentObject(model)
            .frame(width: 760, height: 680)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 680)
        hostingView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let representation = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.renderFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private static func configureWorkspaceFixture(_ model: AppModel) {
        let placeholderElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        model.permissionState = .granted
        model.windows = [
            RunningWindow(
                id: "fixture-main",
                element: placeholderElement,
                pid: 1,
                appName: "开发工具",
                bundleIdentifier: "fixture.development",
                appIcon: nil,
                title: "当前项目",
                frame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
                isMinimized: false,
                isFullScreen: false,
                canMove: true,
                canResize: true
            ),
            RunningWindow(
                id: "fixture-attention",
                element: placeholderElement,
                pid: 2,
                appName: "浏览器",
                bundleIdentifier: "fixture.browser",
                appIcon: nil,
                title: "进度预览",
                frame: CGRect(x: 1_000, y: 0, width: 440, height: 800),
                isMinimized: false,
                isFullScreen: false,
                canMove: true,
                canResize: true
            ),
        ]
        model.mainWindowID = "fixture-main"
        model.attentionWindowID = "fixture-attention"
        model.ratio = 70
        model.statusMessage = "已找到 2 个可管理窗口"
    }
}

private enum SnapshotError: Error {
    case invalidArguments
    case renderFailed
    case encodingFailed
}
