import SwiftUI

// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// 本 worktree 中基线占位内容整体替换为 MVP 1.0 主窗口闭环原型（内存 stub + variant 切换）。
// 只存在于本 worktree，不是生产实现；不得直接晋升生产。
struct ContentView: View {
    var body: some View {
        PrototypeRootView()
            .frame(minWidth: 860, minHeight: 560)
    }
}

#Preview {
    ContentView()
}
