import AppKit
import SwiftUI

// L3 COORD: Pagugu/Views/MenuBarView.swift
// POS: 状态栏窗口只提供打开与退出动作；消费全局暖米白品牌画布，不承载业务状态或工作流。
// TEST: repo://PaguguTests/PaguguTests.swift::testBrandThemeCoversAllAppOwnedSurfaces。

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.block) {
            Button("打开 Pagugu") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppIdentity.mainWindowID)
            }

            Divider()

            Button("退出 Pagugu") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(DesignTokens.Space.sheetPadding)
        .frame(minWidth: 200)
        .background(DesignTokens.Brand.themeBackground)
    }
}
