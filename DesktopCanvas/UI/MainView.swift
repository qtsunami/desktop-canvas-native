import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.permissionState == .granted {
                        WorkspaceSetupView()
                    } else {
                        PermissionView()
                    }

                    LogPanel()
                }
                .padding(20)
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 680, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            if Bundle.main.bundleURL.pathExtension == "app" {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "rectangle.split.2x1.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("桌面画布")
                    .font(.title2.weight(.semibold))
                Text("把主任务与需要持续关注的任务放在同一视野")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            PermissionStatusLabel(state: model.permissionState)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在处理")
            } else {
                Image(systemName: statusSymbol)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
            }

            Text(model.statusMessage)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Text(AppVersion.betaLabel)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var statusSymbol: String {
        if model.permissionState == .required {
            return "exclamationmark.triangle.fill"
        }
        return model.isWorkspaceActive ? "lock.rectangle.fill" : "checkmark.circle.fill"
    }

    private var statusColor: Color {
        if model.permissionState == .required {
            return .orange
        }
        return model.isWorkspaceActive ? .accentColor : .green
    }
}

private struct PermissionStatusLabel: View {
    let state: AccessibilityPermissionState

    var body: some View {
        Label(state.title, systemImage: state.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundColor, in: Capsule())
            .accessibilityLabel("权限状态：\(state.title)")
    }

    private var foregroundColor: Color {
        switch state {
        case .checking: .secondary
        case .required: .orange
        case .granted: .green
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

private struct PermissionView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "hand.raised.square.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text("先允许桌面画布调整窗口")
                        .font(.headline)
                    Text("macOS 要求你明确开启“辅助功能”权限。桌面画布只读取窗口名称、位置和尺寸，并在工作台启用期间限制所选窗口的范围；不会读取窗口里的聊天、网页或文件内容。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button {
                            model.requestPermission()
                        } label: {
                            Label("请求权限", systemImage: "checkmark.shield")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("打开系统设置") {
                            model.openSystemSettings()
                        }

                        Button("重新检查") {
                            model.refreshPermissionAndWindows()
                        }
                    }
                }
            }
            .padding(8)
        } label: {
            Label("系统权限", systemImage: "lock.shield")
        }
    }
}

private struct WorkspaceSetupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.isWorkspaceActive {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.rectangle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("工作台运行中")
                            .font(.headline)
                        Text(
                            "\(model.selectedDisplay?.shortTitle ?? "所选显示器") · "
                                + "\(Int(model.ratio))% / \(100 - Int(model.ratio))%。"
                                + " 调整下方布局会立即生效。"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        model.restoreWindows()
                    } label: {
                        Label("停止并恢复", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!model.canRestore)
                }
                .padding(12)
                .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    windowPicker(
                        title: "主任务窗口",
                        help: "你当前主要操作的工作",
                        selection: $model.mainWindowID
                    )

                    Divider()

                    windowPicker(
                        title: "关注窗口",
                        help: "需要持续观察进度或及时响应的工作",
                        selection: $model.attentionWindowID
                    )

                    if model.manageableWindows.count < 2 {
                        Label(
                            "至少打开两个普通应用窗口后再刷新。全屏窗口和不允许调整大小的窗口不会出现在列表中。",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            } label: {
                HStack {
                    Label("选择工作", systemImage: "macwindow.on.rectangle")
                    Spacer()
                    Button {
                        model.refreshWindows()
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("重新读取当前打开的窗口")
                    .disabled(model.isWorkspaceActive)
                }
            }
            .disabled(model.isWorkspaceActive)

            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("目标显示器", selection: displayBinding) {
                        ForEach(model.displays) { display in
                            Text(display.menuTitle).tag(display.id)
                        }
                    }
                    .help("两个窗口将排列在所选显示器的可用桌面区域")

                    Divider()

                    HStack {
                        Text("主任务占比")
                        Spacer()
                        Text("\(Int(model.ratio)) : \(100 - Int(model.ratio))")
                            .font(.body.monospacedDigit().weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Text("常用比例")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach([50, 60, 70, 75], id: \.self) { value in
                            Toggle(
                                "\(value):\(100 - value)",
                                isOn: presetBinding(for: Double(value))
                            )
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .accessibilityHint("将主任务占比设为 \(value)%")
                        }
                    }

                    Slider(value: ratioBinding, in: 50 ... 75, step: 5) {
                        Text("主任务窗口宽度")
                    } minimumValueLabel: {
                        Text("50")
                    } maximumValueLabel: {
                        Text("75")
                    }
                    .accessibilityValue("主任务 \(Int(model.ratio))%，关注任务 \(100 - Int(model.ratio))%")

                    Picker("主任务位置", selection: sideBinding) {
                        Text("左侧").tag(true)
                        Text("右侧").tag(false)
                    }
                    .pickerStyle(.segmented)

                    LayoutPreview(ratio: model.ratio, mainOnLeft: model.mainOnLeft)
                }
                .padding(8)
            } label: {
                Label("布局", systemImage: "rectangle.split.2x1")
            }
            .disabled(model.isWorking || model.displays.isEmpty)

            HStack {
                Button {
                    model.applyLayout()
                } label: {
                    Label(
                        model.isWorkspaceActive ? "工作台已启用" : "启用工作台",
                        systemImage: model.isWorkspaceActive
                            ? "lock.rectangle.fill"
                            : "rectangle.split.2x1.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canApply)

                Button {
                    model.restoreWindows()
                } label: {
                    Label("停止并恢复", systemImage: "arrow.uturn.backward")
                }
                .disabled(!model.canRestore)

                Spacer()

                Text(model.isWorkspaceActive ? "持续限制已开启" : "启用后，最大化也不会越过分区")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ratioBinding: Binding<Double> {
        Binding(
            get: { model.ratio },
            set: { model.setRatio($0) }
        )
    }

    private var sideBinding: Binding<Bool> {
        Binding(
            get: { model.mainOnLeft },
            set: { model.setMainOnLeft($0) }
        )
    }

    private var displayBinding: Binding<String> {
        Binding(
            get: { model.selectedDisplayID },
            set: { model.setSelectedDisplayID($0) }
        )
    }

    private func presetBinding(for value: Double) -> Binding<Bool> {
        Binding(
            get: { model.ratio == value },
            set: { isSelected in
                if isSelected {
                    model.setRatio(value)
                }
            }
        )
    }

    @ViewBuilder
    private func windowPicker(
        title: String,
        help: String,
        selection: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("请选择窗口").tag(String?.none)
                ForEach(model.manageableWindows) { window in
                    if let appIcon = window.appIcon {
                        Label {
                            Text(window.menuTitle)
                        } icon: {
                            Image(nsImage: appIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                        }
                        .tag(Optional(window.id))
                    } else {
                        Text(window.menuTitle)
                            .tag(Optional(window.id))
                    }
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LayoutPreview: View {
    let ratio: Double
    let mainOnLeft: Bool

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 8
            let usableWidth = max(proxy.size.width - spacing, 0)
            let mainWidth = usableWidth * ratio / 100
            let attentionWidth = usableWidth - mainWidth

            HStack(spacing: spacing) {
                if mainOnLeft {
                    pane("主任务", symbol: "cursorarrow.click.2", width: mainWidth, emphasized: true)
                    pane("持续关注", symbol: "eye", width: attentionWidth, emphasized: false)
                } else {
                    pane("持续关注", symbol: "eye", width: attentionWidth, emphasized: false)
                    pane("主任务", symbol: "cursorarrow.click.2", width: mainWidth, emphasized: true)
                }
            }
        }
        .frame(height: 100)
        .padding(8)
        .background(Color(nsColor: .underPageBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "布局预览，主任务在\(mainOnLeft ? "左侧" : "右侧")，占 \(Int(ratio))%，持续关注任务占 \(100 - Int(ratio))%"
        )
    }

    private func pane(
        _ title: String,
        symbol: String,
        width: CGFloat,
        emphasized: Bool
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.title2)
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(
            emphasized ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    emphasized ? Color.accentColor.opacity(0.45) : Color(nsColor: .separatorColor),
                    lineWidth: 1
                )
        }
    }
}

private struct LogPanel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        DisclosureGroup {
            if model.logs.isEmpty {
                Text("权限检查、窗口刷新和布局结果会显示在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(model.logs) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: entry.level.systemImage)
                                    .foregroundStyle(color(for: entry.level))
                                    .frame(width: 14)
                                    .accessibilityHidden(true)
                                Text(entry.date.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(entry.message)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxHeight: 132)
            }
        } label: {
            HStack {
                Label("运行记录", systemImage: "list.bullet.rectangle")
                Spacer()
                if !model.logs.isEmpty {
                    Button("清除") {
                        model.clearLogs()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("清除运行记录")
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func color(for level: AppLogLevel) -> Color {
        switch level {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Label(model.permissionState.title, systemImage: model.permissionState.systemImage)

            if model.permissionState == .granted {
                Divider()
                if let main = model.selectedMainWindow {
                    Text("主任务：\(main.appName)")
                }
                if let attention = model.selectedAttentionWindow {
                    Text("关注：\(attention.appName)")
                }
                if let display = model.selectedDisplay {
                    Text("显示器：\(display.shortTitle)")
                }

                if model.isWorkspaceActive {
                    Label(
                        "工作台运行中（\(Int(model.ratio)):\(100 - Int(model.ratio))）",
                        systemImage: "lock.rectangle.fill"
                    )
                }

                Button("启用工作台") {
                    model.applyLayout()
                }
                .disabled(!model.canApply)

                Menu("主任务比例") {
                    ForEach([50, 60, 70, 75], id: \.self) { value in
                        Button {
                            model.setRatio(Double(value))
                        } label: {
                            if Int(model.ratio) == value {
                                Label("\(value):\(100 - value)", systemImage: "checkmark")
                            } else {
                                Text("\(value):\(100 - value)")
                            }
                        }
                    }
                }
                .disabled(model.isWorking)

                Button(model.mainOnLeft ? "主任务移到右侧" : "主任务移到左侧") {
                    model.toggleMainSide()
                }
                .disabled(model.isWorking)

                if model.displays.count > 1 {
                    Menu("目标显示器") {
                        ForEach(model.displays) { display in
                            Button {
                                model.setSelectedDisplayID(display.id)
                            } label: {
                                if model.selectedDisplayID == display.id {
                                    Label(display.menuTitle, systemImage: "checkmark")
                                } else {
                                    Text(display.menuTitle)
                                }
                            }
                        }
                    }
                    .disabled(model.isWorking)
                }

                Button("停止并恢复") {
                    model.restoreWindows()
                }
                .disabled(!model.canRestore)

                Button("刷新窗口") {
                    model.refreshWindows()
                }
                .disabled(model.isWorkspaceActive)
            }

            Divider()
            Button("打开桌面画布") {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            SettingsLink {
                Text("设置…")
            }
            Divider()
            Button("退出桌面画布") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("权限") {
                LabeledContent("辅助功能") {
                    Label(model.permissionState.title, systemImage: model.permissionState.systemImage)
                        .foregroundStyle(model.permissionState == .granted ? .green : .orange)
                }

                Text("该权限仅用于列出窗口，并在工作台启用期间约束你主动选择的窗口位置和尺寸。桌面画布不采集屏幕内容。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("打开系统设置") {
                        model.openSystemSettings()
                    }
                    Button("重新检查") {
                        model.refreshPermissionAndWindows()
                    }
                }
            }

            Section("关于") {
                LabeledContent("版本", value: AppVersion.betaLabel)
                LabeledContent("最低系统", value: "macOS 14")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 300)
    }
}
