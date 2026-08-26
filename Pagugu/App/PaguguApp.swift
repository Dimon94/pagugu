import AppKit
import SwiftUI

// L3 COORD: Pagugu/App/PaguguApp.swift
// POS: App 生命周期与单一 AppModel composition root；所有窗口共享同一业务投影与 intent owner；
//      退出时经 AppModel/Git seam 尽力终止在途 Git 子进程，不持久化或恢复 run。
// TEST: repo://PaguguTests/AppModelTests.swift、repo://PaguguTests/GitEligibilityTests.swift；
//       启动 smoke 走 repo://script/build_and_run.sh --verify。

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.terminateInFlightGitProcesses()
    }
}

@main
struct PaguguApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(AppIdentity.displayName, id: AppIdentity.mainWindowID) {
            ContentView(model: model)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 980, height: 640)

        MenuBarExtra(AppIdentity.displayName, systemImage: "shippingbox") {
            MenuBarView()
        }
    }
}
