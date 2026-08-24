// PROTOTYPE / THROWAWAY — issue #10（Wayfinder map #1）
// Prototype 根视图：场景条（顶）+ variant 内容 + variant 切换浮层（底，←/→ 切换）。
// 更新确认、映射选择两个 workflow sheet 与 Registry 受限恢复接管挂在根层，三个 variant 共用同一语义。
// 全部内存 stub；不是生产实现。

import SwiftUI

@MainActor
struct PrototypeRootView: View {
    @State private var world = PrototypeWorld()
    @State private var variant: PrototypeVariant = .f

    var body: some View {
        VStack(spacing: 0) {
            PrototypeScenarioBar(world: world)
            Divider()
            // 产品侧结果反馈横幅（B4）：所有操作结果的家，瞬时、可关闭。
            StubNoticeBanner(world: world)
            Group {
                if world.registryMode != .normal {
                    StubRegistryRecoveryView(world: world)
                } else {
                    switch variant {
                    case .a: PrototypeVariantAView(world: world)
                    case .b: PrototypeVariantBView(world: world)
                    case .c: PrototypeVariantCView(world: world)
                    case .d: PrototypeVariantDView(world: world)
                    case .e: PrototypeVariantEView(world: world)
                    case .f: PrototypeVariantFView(world: world)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            PrototypeSwitcherBar(variant: $variant)
        }
        .background(PrototypeArrowKeyMonitor(onStep: stepVariant))
        .sheet(isPresented: updateSheetPresented) {
            StubUpdateSheet(world: world)
                .interactiveDismissDisabled(updateDismissDisabled)
        }
        .sheet(isPresented: mappingSheetPresented) {
            StubMappingSheet(world: world)
        }
    }

    /// sheet 打开时不切换 variant，避免在确认/映射流程下换掉背景布局。
    private func stepVariant(_ delta: Int) {
        guard world.update == nil, world.mappingDraftID == nil else { return }
        let all = PrototypeVariant.allCases
        let next = (all.firstIndex(of: variant)! + delta + all.count) % all.count
        variant = all[next]
    }

    private var updateSheetPresented: Binding<Bool> {
        Binding(
            get: { world.update != nil },
            set: { presented in
                // Esc 关闭确认 sheet 等价于取消（无修改）；重查/执行/失败页有自己的出口。
                if !presented, case .confirming = world.update?.phase {
                    world.cancelUpdate()
                }
            }
        )
    }

    private var updateDismissDisabled: Bool {
        switch world.update?.phase {
        case .rechecking, .applying, .failed: return true
        case .confirming, nil: return false
        }
    }

    private var mappingSheetPresented: Binding<Bool> {
        Binding(
            get: { world.mappingDraftID != nil },
            set: { if !$0 { world.cancelMappingDraft() } }
        )
    }
}
