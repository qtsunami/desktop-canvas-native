import AppKit
import Combine

enum AccessibilityPermissionState: Equatable {
    case checking
    case required
    case granted

    var title: String {
        switch self {
        case .checking: "正在检查权限"
        case .required: "需要辅助功能权限"
        case .granted: "辅助功能权限已开启"
        }
    }

    var systemImage: String {
        switch self {
        case .checking: "hourglass"
        case .required: "lock.trianglebadge.exclamationmark"
        case .granted: "checkmark.shield.fill"
        }
    }
}

enum AppLogLevel: String {
    case info = "信息"
    case warning = "提醒"
    case error = "错误"

    var systemImage: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }
}

struct AppLogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let level: AppLogLevel
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var permissionState: AccessibilityPermissionState = .checking
    @Published var windows: [RunningWindow] = []
    @Published var mainWindowID: String?
    @Published var attentionWindowID: String?
    @Published var ratio: Double = 70
    @Published var mainOnLeft = true
    @Published var isWorking = false
    @Published var isWorkspaceActive = false
    @Published var statusMessage = "准备检查系统权限"
    @Published var logs: [AppLogEntry] = []

    private let permissionService = AccessibilityPermissionService()
    private let accessibilityClient = AccessibilityClient()
    private lazy var coordinator: WindowCoordinator = {
        let coordinator = WindowCoordinator(accessibilityClient: accessibilityClient)
        coordinator.onConstraintFailure = { [weak self] window, error in
            guard let self else { return }
            let message = "无法继续限制“\(window.menuTitle)”：\(error.localizedDescription)"
            self.statusMessage = message
            self.log(.error, message)
        }
        return coordinator
    }()
    private var started = false
    private var notificationTokens: [NSObjectProtocol] = []
    private var permissionPollingTask: Task<Void, Never>?

    var manageableWindows: [RunningWindow] {
        windows.filter(\.canLayout)
    }

    var selectedMainWindow: RunningWindow? {
        manageableWindows.first(where: { $0.id == mainWindowID })
    }

    var selectedAttentionWindow: RunningWindow? {
        manageableWindows.first(where: { $0.id == attentionWindowID })
    }

    var canApply: Bool {
        guard
            permissionState == .granted,
            let mainWindowID,
            let attentionWindowID,
            mainWindowID != attentionWindowID,
            manageableWindows.contains(where: { $0.id == mainWindowID }),
            manageableWindows.contains(where: { $0.id == attentionWindowID })
        else {
            return false
        }
        return !isWorking && !isWorkspaceActive
    }

    var canRestore: Bool {
        isWorkspaceActive && !isWorking
    }

    func start() {
        guard !started else { return }
        started = true
        registerForSystemChanges()
        startPermissionPolling()
        refreshPermissionAndWindows()
    }

    func requestPermission() {
        log(.info, "请求辅助功能权限")
        _ = permissionService.requestAccess()
        refreshPermissionAndWindows()
        if permissionState != .granted {
            statusMessage = "请在系统设置中开启桌面画布，然后返回应用"
        }
    }

    func openSystemSettings() {
        permissionService.openSystemSettings()
        log(.info, "已打开辅助功能设置")
    }

    func refreshPermissionAndWindows() {
        let trusted = permissionService.isTrusted()
        permissionState = trusted ? .granted : .required
        if trusted {
            refreshWindows()
        } else {
            windows = []
            statusMessage = "授权后才能查看和调整其他应用窗口"
        }
    }

    func refreshWindows() {
        guard permissionService.isTrusted() else {
            refreshPermissionAndWindows()
            return
        }
        guard !isWorkspaceActive else {
            statusMessage = "工作台运行中；停止后可重新选择窗口"
            return
        }

        let previousMainID = mainWindowID
        let previousAttentionID = attentionWindowID
        let result = accessibilityClient.enumerateWindows()
        windows = result.windows.sorted { left, right in
            let appOrder = left.appName.localizedCaseInsensitiveCompare(right.appName)
            if appOrder != .orderedSame {
                return appOrder == .orderedAscending
            }
            return left.displayTitle.localizedCaseInsensitiveCompare(right.displayTitle)
                == .orderedAscending
        }

        let eligible = manageableWindows
        mainWindowID = eligible.contains(where: { $0.id == previousMainID })
            ? previousMainID
            : eligible.first?.id
        attentionWindowID = eligible.contains(where: {
            $0.id == previousAttentionID && $0.id != mainWindowID
        })
            ? previousAttentionID
            : eligible.first(where: { $0.id != mainWindowID })?.id

        statusMessage = eligible.isEmpty
            ? "没有找到可管理的普通窗口"
            : "已找到 \(eligible.count) 个可管理窗口"
        log(.info, "刷新窗口列表：可管理 \(eligible.count) 个，共 \(windows.count) 个")
        result.warnings.prefix(4).forEach { log(.warning, $0) }
    }

    func applyLayout() {
        guard
            let mainWindow = manageableWindows.first(where: { $0.id == mainWindowID }),
            let attentionWindow = manageableWindows.first(where: { $0.id == attentionWindowID })
        else {
            statusMessage = "请选择两个不同的可管理窗口"
            log(.warning, statusMessage)
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try coordinator.apply(
                mainWindow: mainWindow,
                attentionWindow: attentionWindow,
                ratio: ratio,
                mainOnLeft: mainOnLeft
            )
            isWorkspaceActive = coordinator.isActive
            statusMessage = "工作台运行中：主任务最多 \(Int(ratio))%，关注任务最多 \(100 - Int(ratio))%"
            log(.info, "持续约束已启用：\(mainWindow.menuTitle) / \(attentionWindow.menuTitle)")
        } catch {
            isWorkspaceActive = false
            statusMessage = "布局失败：\(error.localizedDescription)"
            log(.error, statusMessage)
        }
    }

    func restoreWindows() {
        guard coordinator.canRestore else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try coordinator.restore()
            isWorkspaceActive = false
            statusMessage = "已恢复窗口原始位置"
            log(.info, statusMessage)
            refreshWindows()
        } catch {
            isWorkspaceActive = false
            statusMessage = "部分窗口恢复失败：\(error.localizedDescription)"
            log(.error, statusMessage)
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    private func registerForSystemChanges() {
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.handleApplicationBecameActive()
                }
            }
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            notificationTokens.append(
                workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard
                            self?.permissionState == .granted,
                            self?.isWorkspaceActive == false
                        else { return }
                        self?.refreshWindows()
                    }
                }
            )
        }
    }

    private func handleApplicationBecameActive() {
        let trusted = permissionService.isTrusted()

        if !trusted {
            permissionState = .required
            windows = []
            statusMessage = "授权后才能查看和调整其他应用窗口"
            return
        }

        // Returning from System Settings is the one activation that needs a full
        // refresh. Normal focus changes keep the existing list responsive; the
        // user can explicitly refresh when windows change.
        guard permissionState != .granted else { return }
        permissionState = .granted
        refreshWindows()
    }

    private func startPermissionPolling() {
        permissionPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                guard self.permissionState != .granted else { continue }
                self.handleApplicationBecameActive()
            }
        }
    }

    private func log(_ level: AppLogLevel, _ message: String) {
        logs.insert(AppLogEntry(level: level, message: message), at: 0)
        if logs.count > 100 {
            logs.removeLast(logs.count - 100)
        }
    }
}
