import SwiftUI

// L3 COORD: Pagugu/Views/DesignTokens.swift
// POS: 设计令牌唯一定义点（#28）。品牌色、语义状态色、字号梯度、间距/圆角/尺寸令牌与按压反馈集中在此；
//      目录、详情、结果区与各 sheet 一律消费令牌，不逐组件手写冲突值。
//      ChunUI 兼容性结论为不引入（repo://docs/product/chunui-compatibility.md），
//      以原生 SwiftUI 系统语义色与材质达成同等令牌化；正式品牌画布固定浅色，状态仍由颜色、图标和文案共同表达。
//      动效克制：唯一自定义动效是按压反馈（scale 0.96 + 0.1s ease-out）；高频交互无其他自定义动画，
//      所有状态变化另有颜色/图标/文案静态提示。
// TEST: repo://PaguguTests/PaguguTests.swift（pressScale、childIndent、状态色语义）。

/// 设计令牌（Design Tokens）：主窗口全部视觉常量的唯一来源。
/// 约定：新增视觉常量先在这里定义并被消费；View 内不手写与之冲突的字面值。
enum DesignTokens {
    // MARK: - 品牌色（C1-T4「探壳」正式方案）

    enum Brand {
        /// 主背景与品牌暖米白
        static let themeBackground = Color(red: 244 / 255, green: 235 / 255, blue: 221 / 255)
        /// 壳与眼睛的午夜靛紫，也是交互强调色
        static let accent = Color(red: 41 / 255, green: 36 / 255, blue: 92 / 255)
        /// 身体与双钳的暖金黄
        static let character = Color(red: 239 / 255, green: 182 / 255, blue: 62 / 255)
    }

    // MARK: - 间距（紧凑桌面密度，4pt 步进）

    enum Space {
        /// 标题与副行之间的紧凑间距
        static let tight: CGFloat = 2
        /// 同族小元素间距（宿主 logo 槽位、内联标签）
        static let inline: CGFloat = 4
        /// 行内图标与文本间距
        static let row: CGFloat = 6
        /// 详情块内部元素间距
        static let block: CGFloat = 8
        /// 详情各块之间、sheet 段落之间的分区间距
        static let section: CGFloat = 16
        /// 卡片内边距（检出卡、审计详情卡、横幅）
        static let cardPadding: CGFloat = 10
        /// sheet 统一内边距
        static let sheetPadding: CGFloat = 20
        /// 目录行垂直内边距
        static let rowVertical: CGFloat = 2
    }

    // MARK: - 圆角（card 与 inset 是兄弟表面，独立取值；真嵌套时 outer = inner + padding）

    enum Radius {
        /// 嵌套内容块（SKILL.md 原文块）
        static let inset: CGFloat = 6
        /// 卡片与横幅（检出卡、审计详情卡、结果横幅）
        static let card: CGFloat = 8
    }

    // MARK: - 尺寸

    enum Size {
        /// 欢迎页品牌 Logo
        static let welcomeLogo: CGFloat = 112
        /// 宿主 logo 占位圆点直径
        static let hostLogoDot: CGFloat = 8
        /// 目录 chevron 独立热区
        static let disclosureHotspot: CGFloat = 18
        /// 目录子行缩进 = chevron 热区(18) + 行内间距(6)
        static let childIndent: CGFloat = 24
        /// 横幅关闭按钮热区
        static let bannerDismissHotspot: CGFloat = 20
    }

    // MARK: - 字号梯度

    enum Fonts {
        /// sheet 与详情面板标题
        static let panelTitle: Font = .title2.bold()
        /// 来源仓库行标题、详情块小标题
        static let heading: Font = .headline
        /// 目录子 Skill 行标题、正文强调
        static let rowTitle: Font = .callout
        /// 辅助说明
        static let caption: Font = .caption
        /// 次级辅助说明（路径、元信息）
        static let captionSmall: Font = .caption2
        /// 等宽证据值（检出事实、SHA、时间）
        static let evidence: Font = .caption.monospaced()
        /// 等宽正文证据（安装路径、Source Key、仓内相对路径）
        static let evidenceBody: Font = .body.monospaced()
        /// 详情正文（来源仓库内 Skill 名、来源不明说明）
        static let body: Font = .body
        /// SKILL.md 原文
        static let markdown: Font = .callout.monospaced()
        /// 目录展开/收起 chevron
        static let disclosure: Font = .caption2.weight(.semibold)
    }

    // MARK: - 动效（唯一自定义动效：按压反馈；高频交互无其它自定义动画）

    enum Motion {
        /// better-ui 按压缩放，固定 0.96；小于 0.95 会夸张
        static let pressScale: CGFloat = 0.96
        /// 可打断的 ease-out 时长（秒）
        static let pressDuration: TimeInterval = 0.1
        /// 减少动态效果时的按压透明度（替代缩放）
        static let pressReducedOpacity: Double = 0.7
    }

    // MARK: - 语义状态色（系统动态色，明暗两态可辨；状态变化另有图标/文案静态提示）

    enum Status {
        /// 成功、已是最新、可更新通路
        static let ok: Color = .green
        /// 需要人工处理的阻断态、部分完成、取消后果
        static let warning: Color = .orange
        /// 失败、检查错误
        static let error: Color = .red
        /// 进行中（检查中、重查中）
        static let running: Color = .blue
        /// 中性信息（仅本地、未配置上游、尚未检查、本地领先）
        static let neutral: Color = .secondary
    }

    // MARK: - 表面材质

    enum Surface {
        /// 卡片背景
        static var card: some ShapeStyle { .quaternary.opacity(0.25) }
        /// 嵌套内容块背景（略深于卡片以分层）
        static var inset: some ShapeStyle { .quaternary.opacity(0.35) }
        /// 横幅着色底（叠加状态色）
        static func bannerTint(_ status: Color) -> some ShapeStyle { status.opacity(0.12) }
        /// 横幅状态描边（结构分工：描边表达状态归属，不伪造高度）
        static func bannerStroke(_ status: Color) -> some ShapeStyle { status.opacity(0.30) }
    }

    // MARK: - Checkout Git State → 语义状态色（纯呈现映射，不裁决状态；状态本身是 AppModel 投影）

    static func statusColor(for state: CheckoutGitState) -> Color {
        switch state {
        case .upToDate, .updateAvailable: return Status.ok
        case .inspectionFailed, .upstreamMismatch: return Status.error
        case .detached, .siblingConflict, .dirty, .diverged: return Status.warning
        case .noRemote, .noUpstream, .checkUnknown, .aheadOnly: return Status.neutral
        }
    }
}

// MARK: - 按压反馈（better-ui：scale 0.96；plain 图标配 0.1s ease-out 过渡，可被打断）

struct PressFeedbackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressFeedbackLabel(configuration: configuration)
    }
}

private struct PressFeedbackLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? DesignTokens.Motion.pressScale : 1))
            .opacity(reduceMotion && configuration.isPressed ? DesignTokens.Motion.pressReducedOpacity : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.pressDuration),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressFeedbackButtonStyle {
    /// plain 图标按钮的按压反馈（chevron、横幅关闭、行内动作）。
    static var pressFeedback: PressFeedbackButtonStyle { PressFeedbackButtonStyle() }
}
