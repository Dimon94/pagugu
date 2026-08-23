import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct PaguguApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // PROTOTYPE / THROWAWAY — issue #10：窗口标题标注原型身份，只存在于本 worktree。
        WindowGroup("\(AppIdentity.displayName) · PROTOTYPE", id: AppIdentity.mainWindowID) {
            ContentView()
        }
        .defaultSize(width: 980, height: 640)

        MenuBarExtra(AppIdentity.displayName, systemImage: "shippingbox") {
            MenuBarView()
        }
    }
}
