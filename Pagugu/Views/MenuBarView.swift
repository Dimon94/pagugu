import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("打开 Pagugu") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AppIdentity.mainWindowID)
        }

        Divider()

        Button("退出 Pagugu") {
            NSApplication.shared.terminate(nil)
        }
    }
}
