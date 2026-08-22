import SwiftUI

struct ContentView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Pagugu 已准备好", systemImage: "shippingbox")
        } description: {
            Text("Skill 扫描将在下一个功能切片中加入。")
        }
        .frame(minWidth: 640, minHeight: 420)
    }
}

#Preview {
    ContentView()
}
