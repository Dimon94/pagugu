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
        WindowGroup(AppIdentity.displayName, id: AppIdentity.mainWindowID) {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)

        MenuBarExtra(AppIdentity.displayName, systemImage: "shippingbox") {
            MenuBarView()
        }
    }
}
