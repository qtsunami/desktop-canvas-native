import Foundation

@MainActor
final class WindowConstraintMonitor {
    private struct Binding {
        let window: RunningWindow
        let zone: CGRect
    }

    private let accessibilityClient: AccessibilityClient
    private var bindings: [Binding] = []
    private var monitoringTask: Task<Void, Never>?
    private var reportedFailureWindowIDs: Set<String> = []

    var onCorrection: ((RunningWindow) -> Void)?
    var onFailure: ((RunningWindow, Error) -> Void)?

    init(accessibilityClient: AccessibilityClient) {
        self.accessibilityClient = accessibilityClient
    }

    var isActive: Bool {
        monitoringTask != nil
    }

    func start(
        mainWindow: RunningWindow,
        mainZone: CGRect,
        attentionWindow: RunningWindow,
        attentionZone: CGRect
    ) {
        stop()
        bindings = [
            Binding(window: mainWindow, zone: mainZone),
            Binding(window: attentionWindow, zone: attentionZone),
        ]
        reportedFailureWindowIDs.removeAll()

        monitoringTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.enforceConstraints()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        bindings.removeAll()
        reportedFailureWindowIDs.removeAll()
    }

    private func enforceConstraints() {
        for binding in bindings {
            guard !accessibilityClient.isMinimized(binding.window) else { continue }

            do {
                let exitedFullScreen = try accessibilityClient.exitFullScreenIfNeeded(binding.window)
                let currentFrame = try accessibilityClient.currentFrame(of: binding.window)
                let constrainedFrame = exitedFullScreen
                    ? binding.zone
                    : LayoutEngine.constrain(currentFrame, to: binding.zone)

                if !approximatelyEqual(currentFrame, constrainedFrame) {
                    try accessibilityClient.setFrame(constrainedFrame, for: binding.window)
                    onCorrection?(binding.window)
                }
                reportedFailureWindowIDs.remove(binding.window.id)
            } catch {
                guard reportedFailureWindowIDs.insert(binding.window.id).inserted else {
                    continue
                }
                onFailure?(binding.window, error)
            }
        }
    }

    private func approximatelyEqual(
        _ left: CGRect,
        _ right: CGRect,
        tolerance: CGFloat = 1
    ) -> Bool {
        abs(left.minX - right.minX) <= tolerance
            && abs(left.minY - right.minY) <= tolerance
            && abs(left.width - right.width) <= tolerance
            && abs(left.height - right.height) <= tolerance
    }
}
