import AppKit

@main
@MainActor
enum IntegrationWindowHost {
    private static let delegate = HostDelegate()

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.finishLaunching()
        application.run()
    }
}

@MainActor
private final class HostDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let visibleFrame = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1_200, height: 800)

        let mainWindow = makeWindow(
            title: "[DesktopCanvasTest] Main",
            frame: NSRect(
                x: visibleFrame.minX + 80,
                y: visibleFrame.minY + 100,
                width: 620,
                height: 480
            ),
            color: .systemBlue
        )
        let attentionWindow = makeWindow(
            title: "[DesktopCanvasTest] Attention",
            frame: NSRect(
                x: visibleFrame.maxX - 500,
                y: visibleFrame.minY + 180,
                width: 420,
                height: 360
            ),
            color: .systemOrange
        )

        windows = [mainWindow, attentionWindow]
        mainWindow.makeKeyAndOrderFront(nil)
        attentionWindow.orderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindow(title: String, frame: NSRect, color: NSColor) -> NSWindow {
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 180, height: 140)
        window.isReleasedWhenClosed = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = color.withAlphaComponent(0.12).cgColor

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        window.contentView = contentView
        return window
    }
}
