import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingControlPanelController {
    private enum Metrics {
        static let size = CGSize(width: 356, height: 52)
        static let topInset: CGFloat = 8
    }

    private let model: AppModel
    private var panel: FloatingControlPanel?
    private var presentationObserver: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        presentationObserver = model.$isWorkspaceActive
            .combineLatest(model.$selectedDisplayID, model.$displays)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                Task { @MainActor [weak self] in
                    self?.synchronizePresentation()
                }
            }
    }

    private func synchronizePresentation() {
        guard model.isWorkspaceActive, let screen = model.selectedDisplay?.screen else {
            panel?.orderOut(nil)
            return
        }

        let panel = panel ?? makePanel()
        let visibleFrame = screen.visibleFrame
        let origin = CGPoint(
            x: visibleFrame.midX - (Metrics.size.width / 2),
            y: visibleFrame.maxY - Metrics.size.height - Metrics.topInset
        )
        panel.setFrame(NSRect(origin: origin, size: Metrics.size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> FloatingControlPanel {
        let panel = FloatingControlPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary,
        ]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.contentView = NSHostingView(
            rootView: FloatingControlBar(model: model)
                .frame(width: Metrics.size.width, height: Metrics.size.height)
        )
        self.panel = panel
        return panel
    }
}

private final class FloatingControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct FloatingControlBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Label(
                model.isWorkspacePaused ? "已暂停" : "约束中",
                systemImage: model.isWorkspacePaused ? "pause.circle.fill" : "lock.rectangle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(model.isWorkspacePaused ? Color.orange : Color.green)
            .lineLimit(1)

            Divider()
                .frame(height: 20)

            FloatingIconButton(
                title: model.isWorkspacePaused ? "继续工作台约束" : "暂停工作台约束",
                systemImage: model.isWorkspacePaused ? "play.fill" : "pause.fill",
                isDisabled: model.isWorking,
                action: model.toggleWorkspacePause
            )

            FloatingIconButton(
                title: "交换主任务与关注任务的左右位置",
                systemImage: "arrow.left.arrow.right",
                isDisabled: model.isWorking,
                action: model.toggleMainSide
            )

            Menu {
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
            } label: {
                Label(
                    "\(Int(model.ratio)):\(100 - Int(model.ratio))",
                    systemImage: "rectangle.split.2x1"
                )
                .font(.caption.monospacedDigit().weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isWorking)
            .help("调整主任务与关注任务的宽度比例")
            .accessibilityLabel("布局比例，当前 \(Int(model.ratio)) 比 \(100 - Int(model.ratio))")

            Divider()
                .frame(height: 20)

            FloatingIconButton(
                title: "停止工作台并恢复原窗口",
                systemImage: "xmark",
                role: .destructive,
                isDisabled: !model.canRestore,
                action: model.restoreWindows
            )
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color(nsColor: .separatorColor).opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("工作台悬浮控制条")
    }
}

private struct FloatingIconButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    var isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .help(title)
        .accessibilityLabel(title)
    }
}
