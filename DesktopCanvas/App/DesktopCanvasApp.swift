import AppKit
import SwiftUI

@main
@MainActor
struct DesktopCanvasApp: App {
    @StateObject private var model: AppModel
    private let floatingControlPanelController: FloatingControlPanelController

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        floatingControlPanelController = FloatingControlPanelController(model: model)
#if DEBUG
        Task { @MainActor in
            DebugIntegrationTestRunner.startIfRequested()
        }
#endif
    }

    var body: some Scene {
        Window("桌面画布", id: "main") {
            MainView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                }
        }
        .defaultSize(width: 760, height: 760)
        .windowResizability(.contentMinSize)

        MenuBarExtra("桌面画布", systemImage: "rectangle.split.2x1") {
            MenuBarContentView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .onAppear {
                    model.start()
                }
        }
    }
}
