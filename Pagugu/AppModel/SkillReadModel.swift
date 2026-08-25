import Foundation

// L3 COORD: Pagugu/AppModel/SkillReadModel.swift
// POS: AppModel 模块（ADR-0009 §7）。owns Skill Read Model 只读投影。
// TEST: repo://PaguguTests/AppModelTests.swift（Skill、Project Scan Root 投影与欢迎态测试）。

/// Skill Read Model：AppModel 发布的只读投影，View 只消费不重建。
struct SkillReadModel: Sendable {
    /// 目录条目（已按 Skill Identity 聚合）。
    let entries: [SkillDirectoryEntry]
    /// 扫描问题列表。
    let issues: [ScanIssue]
    /// 整体扫描状态。
    let scanOutcome: ScanOutcome
    /// Project Scan Root 主张的按序实时投影。
    let projectScanRoots: [ProjectScanRoot]
    /// 是否为空态（无任何 Skill 且无 Issue）。
    let isEmpty: Bool

    static func empty() -> SkillReadModel {
        SkillReadModel(entries: [], issues: [], scanOutcome: .complete, projectScanRoots: [])
    }

    init(
        entries: [SkillDirectoryEntry],
        issues: [ScanIssue],
        scanOutcome: ScanOutcome,
        projectScanRoots: [ProjectScanRoot] = []
    ) {
        self.entries = entries
        self.issues = issues
        self.scanOutcome = scanOutcome
        self.projectScanRoots = projectScanRoots
        self.isEmpty = entries.isEmpty && issues.isEmpty
    }
}
