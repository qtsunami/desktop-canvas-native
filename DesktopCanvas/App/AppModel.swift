import AppKit
import Combine

enum AppVersion {
    static let marketingVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "0.2.0"

    static let betaLabel: String = {
        var components = marketingVersion.split(separator: ".").map(String.init)
        if components.count == 3, components.last == "0" {
            components.removeLast()
        }
        return "Beta \(components.joined(separator: "."))"
    }()
}

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

struct WorkspaceDisplay: Identifiable {
    let id: String
    let name: String
    let pointSize: CGSize
    let isMain: Bool
    let screen: NSScreen?

    var menuTitle: String {
        let size = "\(Int(pointSize.width)) × \(Int(pointSize.height))"
        return isMain ? "\(name) · \(size)（主显示器）" : "\(name) · \(size)"
    }

    var shortTitle: String {
        isMain ? "\(name)（主显示器）" : name
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var permissionState: AccessibilityPermissionState = .checking
    @Published var windows: [RunningWindow] = []
    @Published var displays: [WorkspaceDisplay] = []
    @Published var mainWindowID: String?
    @Published var attentionWindowID: String?
    @Published var ratio: Double = 70
    @Published var mainOnLeft = true
    @Published var selectedDisplayID = ""
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

    private enum PreferenceKey {
        static let ratio = "workspace.ratio"
        static let mainOnLeft = "workspace.mainOnLeft"
        static let displayID = "workspace.displayID"
    }

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: PreferenceKey.ratio) != nil {
            ratio = Self.normalizedRatio(defaults.double(forKey: PreferenceKey.ratio))
        }
        if defaults.object(forKey: PreferenceKey.mainOnLeft) != nil {
            mainOnLeft = defaults.bool(forKey: PreferenceKey.mainOnLeft)
        }
        selectedDisplayID = defaults.string(forKey: PreferenceKey.displayID) ?? ""
        refreshDisplays(updateActiveWorkspace: false)
    }

    var manageableWindows: [RunningWindow] {
        windows.filter(\.canLayout)
    }

    var selectedMainWindow: RunningWindow? {
        manageableWindows.first(where: { $0.id == mainWindowID })
    }

    var selectedAttentionWindow: RunningWindow? {
        manageableWindows.first(where: { $0.id == attentionWindowID })
    }

    var selectedDisplay: WorkspaceDisplay? {
        displays.first(where: { $0.id == selectedDisplayID })
    }

    var canApply: Bool {
        guard
            permissionState == .granted,
            let mainWindowID,
            let attentionWindowID,
            mainWindowID != attentionWindowID,
            manageableWindows.contains(where: { $0.id == mainWindowID }),
            manageableWindows.contains(where: { $0.id == attentionWindowID }),
            selectedDisplay?.screen != nil
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
        refreshDisplays(updateActiveWorkspace: false)
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

    func setRatio(_ newRatio: Double) {
        let normalized = Self.normalizedRatio(newRatio)
        guard ratio != normalized else { return }
        ratio = normalized
        UserDefaults.standard.set(normalized, forKey: PreferenceKey.ratio)
        updateActiveLayout(reason: "主任务占比已调整为 \(Int(normalized))%")
    }

    func setMainOnLeft(_ newValue: Bool) {
        guard mainOnLeft != newValue else { return }
        mainOnLeft = newValue
        UserDefaults.standard.set(newValue, forKey: PreferenceKey.mainOnLeft)
        updateActiveLayout(reason: "主任务已移动到\(newValue ? "左侧" : "右侧")")
    }

    func toggleMainSide() {
        setMainOnLeft(!mainOnLeft)
    }

    func setSelectedDisplayID(_ displayID: String) {
        guard
            displayID != selectedDisplayID,
            displays.contains(where: { $0.id == displayID })
        else { return }

        selectedDisplayID = displayID
        UserDefaults.standard.set(displayID, forKey: PreferenceKey.displayID)
        updateActiveLayout(reason: "工作台已移动到 \(selectedDisplay?.shortTitle ?? "所选显示器")")
    }

    func applyLayout() {
        guard
            let mainWindow = manageableWindows.first(where: { $0.id == mainWindowID }),
            let attentionWindow = manageableWindows.first(where: { $0.id == attentionWindowID }),
            let display = selectedDisplay,
            let targetScreen = display.screen
        else {
            statusMessage = "请选择两个不同的可管理窗口和目标显示器"
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
                mainOnLeft: mainOnLeft,
                targetScreen: targetScreen
            )
            isWorkspaceActive = coordinator.isActive
            statusMessage = "工作台运行中：\(display.shortTitle)，\(Int(ratio)) : \(100 - Int(ratio))"
            log(
                .info,
                "持续约束已启用：\(mainWindow.menuTitle) / \(attentionWindow.menuTitle) · \(display.shortTitle)"
            )
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

    func refreshDisplays(updateActiveWorkspace: Bool = true) {
        let currentSelection = selectedDisplayID
        let mainScreen = NSScreen.screens.first

        displays = NSScreen.screens.map { screen in
            let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
            let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber
            let fallbackID = [
                Int(screen.frame.minX),
                Int(screen.frame.minY),
                Int(screen.frame.width),
                Int(screen.frame.height),
            ].map(String.init).joined(separator: ":")

            return WorkspaceDisplay(
                id: screenNumber.map { String($0.uint32Value) } ?? fallbackID,
                name: screen.localizedName,
                pointSize: screen.frame.size,
                isMain: screen == mainScreen,
                screen: screen
            )
        }

        if !displays.contains(where: { $0.id == currentSelection }) {
            selectedDisplayID = displays.first(where: \.isMain)?.id ?? displays.first?.id ?? ""
            if !selectedDisplayID.isEmpty {
                UserDefaults.standard.set(selectedDisplayID, forKey: PreferenceKey.displayID)
            }
        }

        if updateActiveWorkspace {
            updateActiveLayout(reason: "显示器配置已更新")
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

        notificationTokens.append(
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshDisplays()
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

    private func updateActiveLayout(reason: String) {
        guard isWorkspaceActive, !isWorking else { return }
        guard let display = selectedDisplay, let targetScreen = display.screen else {
            statusMessage = "目标显示器不可用，请重新选择"
            log(.error, statusMessage)
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            try coordinator.updateLayout(
                ratio: ratio,
                mainOnLeft: mainOnLeft,
                targetScreen: targetScreen
            )
            isWorkspaceActive = coordinator.isActive
            statusMessage = "工作台运行中：\(display.shortTitle)，\(Int(ratio)) : \(100 - Int(ratio))"
            log(.info, reason)
        } catch {
            statusMessage = "调整布局失败：\(error.localizedDescription)"
            log(.error, statusMessage)
        }
    }

    private static func normalizedRatio(_ value: Double) -> Double {
        min(max((value / 5).rounded() * 5, 50), 75)
    }

    private func log(_ level: AppLogLevel, _ message: String) {
        logs.insert(AppLogEntry(level: level, message: message), at: 0)
        if logs.count > 100 {
            logs.removeLast(logs.count - 100)
        }
    }
}
