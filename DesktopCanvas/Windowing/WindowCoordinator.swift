import AppKit

enum WindowCoordinatorError: LocalizedError {
    case noScreen
    case sameWindow
    case inactiveWorkspace

    var errorDescription: String? {
        switch self {
        case .noScreen:
            return "没有找到可用显示器"
        case .sameWindow:
            return "主任务和关注任务不能选择同一个窗口"
        case .inactiveWorkspace:
            return "工作台尚未启用"
        }
    }
}

@MainActor
final class WindowCoordinator {
    private let accessibilityClient: AccessibilityClient
    private let constraintMonitor: WindowConstraintMonitor
    private var snapshots: [WindowSnapshot] = []
    private var activeMainWindow: RunningWindow?
    private var activeAttentionWindow: RunningWindow?

    var onConstraintFailure: ((RunningWindow, Error) -> Void)? {
        didSet {
            constraintMonitor.onFailure = onConstraintFailure
        }
    }

    init(accessibilityClient: AccessibilityClient) {
        self.accessibilityClient = accessibilityClient
        constraintMonitor = WindowConstraintMonitor(accessibilityClient: accessibilityClient)
    }

    var canRestore: Bool {
        !snapshots.isEmpty
    }

    var isActive: Bool {
        constraintMonitor.isActive
    }

    func apply(
        mainWindow: RunningWindow,
        attentionWindow: RunningWindow,
        ratio: Double,
        mainOnLeft: Bool,
        targetScreen: NSScreen
    ) throws {
        guard mainWindow.id != attentionWindow.id else {
            throw WindowCoordinatorError.sameWindow
        }

        if canRestore {
            try restore()
        }

        snapshots = [
            try accessibilityClient.snapshot(of: mainWindow),
            try accessibilityClient.snapshot(of: attentionWindow),
        ]
        activeMainWindow = mainWindow
        activeAttentionWindow = attentionWindow

        do {
            try updateLayout(
                ratio: ratio,
                mainOnLeft: mainOnLeft,
                targetScreen: targetScreen
            )
        } catch {
            try? restore()
            throw error
        }
    }

    func updateLayout(
        ratio: Double,
        mainOnLeft: Bool,
        targetScreen: NSScreen
    ) throws {
        guard
            let mainWindow = activeMainWindow,
            let attentionWindow = activeAttentionWindow
        else {
            throw WindowCoordinatorError.inactiveWorkspace
        }
        guard let menuBarScreen = NSScreen.screens.first else {
            throw WindowCoordinatorError.noScreen
        }

        let accessibilityVisibleFrame = ScreenCoordinateMapper.appKitToAccessibility(
            targetScreen.visibleFrame,
            menuBarScreenFrame: menuBarScreen.frame
        )
        let frames = LayoutEngine.split(
            visibleFrame: accessibilityVisibleFrame,
            mainRatio: ratio / 100,
            gap: 8,
            mainOnLeft: mainOnLeft
        )

        try accessibilityClient.setFrame(frames.main, for: mainWindow)
        try accessibilityClient.setFrame(frames.attention, for: attentionWindow)
        constraintMonitor.start(
            mainWindow: mainWindow,
            mainZone: frames.main,
            attentionWindow: attentionWindow,
            attentionZone: frames.attention
        )
    }

    func restore() throws {
        constraintMonitor.stop()
        var firstError: Error?
        let snapshotsToRestore = snapshots

        for snapshot in snapshotsToRestore {
            do {
                try accessibilityClient.restore(snapshot)
            } catch {
                firstError = firstError ?? error
            }
        }

        snapshots.removeAll()
        activeMainWindow = nil
        activeAttentionWindow = nil
        if let firstError {
            throw firstError
        }
    }
}
