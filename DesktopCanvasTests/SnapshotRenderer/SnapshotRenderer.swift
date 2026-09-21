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
        let size: CGSize
        let rootView: AnyView

        switch mode {
        case "permission":
            model.permissionState = .required
            model.statusMessage = "授权后才能查看和调整其他应用窗口"
            size = CGSize(width: 760, height: 760)
            rootView = AnyView(MainView().environmentObject(model))
        case "workspace":
            configureWorkspaceFixture(model)
            size = CGSize(width: 760, height: 760)
            rootView = AnyView(MainView().environmentObject(model))
        case "workspace-active":
            configureWorkspaceFixture(model)
            model.isWorkspaceActive = true
            model.statusMessage = "工作台运行中：内建显示器（主显示器），70 : 30"
            size = CGSize(width: 760, height: 760)
            rootView = AnyView(MainView().environmentObject(model))
        case "workspace-paused":
            configureWorkspaceFixture(model)
            model.isWorkspaceActive = true
            model.isWorkspacePaused = true
            model.statusMessage = "工作台已暂停：窗口暂时可以自由移动"
            size = CGSize(width: 760, height: 760)
            rootView = AnyView(MainView().environmentObject(model))
        case "floating-controls", "floating-controls-paused":
            configureWorkspaceFixture(model)
            model.isWorkspaceActive = true
            model.isWorkspacePaused = mode == "floating-controls-paused"
            size = CGSize(width: 520, height: 120)
            rootView = AnyView(
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    FloatingControlBar(model: model)
                }
            )
        default:
            throw SnapshotError.invalidArguments
        }

        let content = rootView
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, isDark ? .dark : .light)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: size)
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
        model.displays = [
            WorkspaceDisplay(
                id: "fixture-display",
                name: "内建显示器",
                pointSize: CGSize(width: 1_440, height: 900),
                isMain: true,
                screen: nil
            ),
        ]
        model.selectedDisplayID = "fixture-display"
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
        model.mainOnLeft = true
        model.statusMessage = "已找到 2 个可管理窗口"
    }
}

private enum SnapshotError: Error {
    case invalidArguments
    case renderFailed
    case encodingFailed
}
