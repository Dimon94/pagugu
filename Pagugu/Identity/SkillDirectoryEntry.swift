import Foundation

// L3 COORD: Pagugu/Identity/SkillDirectoryEntry.swift
// POS: Identity 模块（纯函数，ADR-0009 §2）。owns Skill 目录条目、来源/检出分组、
//      逐检出 Skill 成员清单、复制投影呈现组与逐 Installation 来源映射投影值类型。
//      映射不拥有 Skill Source、Checkout 或 Git 状态事实。
// TEST: repo://PaguguTests/IdentityTests.swift（分组、指纹与映射投影表测试）。

/// Projection Type（CONTEXT.md）：Skill Installation 的形态分类。
enum ProjectionType: String, Hashable, Sendable {
    /// 软链接：完全解析后归因到目标所在的 Skill Source。
    case symlink
    /// 复制：不自动归因；未映射即为 Unattributed Installation。
    case copy
    /// 仓库本体：安装路径即 Skill Source 工作树。
    case repositorySelf

    var displayName: String {
        switch self {
        case .symlink: return "软链接"
        case .copy: return "复制"
        case .repositorySelf: return "仓库本体"
        }
    }
}

/// 一个 Skill Installation：as-found 路径、canonical 路径、Agent Host 集合、Projection Type。
struct SkillInstallation: Hashable, Sendable {
    let asFoundPath: String
    /// 该安装完全解析软链接后的绝对路径（呈现组内逐安装保留）。
    let canonicalPath: String
    let hosts: Set<AgentHost>
    let projectionType: ProjectionType
    /// 只存在于复制投影；记录仍由 Registry owns。
    let sourceMapping: SourceMappingProjection?

    var isManuallyMapped: Bool {
        sourceMapping?.validity == .valid
    }
}

/// 一条来源映射在当前 Scan Result 下的纯函数投影。
struct SourceMappingProjection: Identifiable, Hashable, Sendable {
    var id: String { installationCanonicalPath }

    let installationCanonicalPath: String
    let targetIdentity: SkillIdentity
    let validity: SourceMappingValidity
}

/// 一条 Skill 目录条目（Skill Identity + 聚合属性）。身份与去重的 canonical 条目。
struct SkillDirectoryEntry: Identifiable, Hashable, Sendable {
    let id: SkillIdentity
    let displayName: String
    /// Skill 内容的 canonical 路径（SKILL.md 原文读取与安装事实展示用）。
    let canonicalPath: String
    let installations: [SkillInstallation]

    /// 宿主并集（S2：logo 槽位点亮 = 任一安装事实）。
    var hosts: Set<AgentHost> {
        Set(installations.flatMap(\.hosts))
    }
}

/// 一个已发现 Skill Source Checkout；以工作树根 Canonical Path 标识。
struct SkillSourceCheckout: Identifiable, Hashable, Sendable {
    let canonicalPath: String

    var id: String { canonicalPath }
}

/// 目标物理检出内实际发现的 Skill Identity 清单；更新爆炸半径只读本清单。
struct CheckoutSkillInventory: Hashable, Sendable {
    let checkoutCanonicalPath: String
    let skillIdentities: [SkillIdentity]
}

/// 来源仓库行（Variant F 呈现分组）：一个 Skill Source 及其全部子 Skill。
struct SkillSourceItem: Identifiable, Hashable, Sendable {
    let id: SkillSourceKey
    let displayName: String
    let skills: [SkillDirectoryEntry]
    /// 同一 Skill Source Key 下全部已发现物理检出。不得聚合成单一假状态。
    let checkouts: [SkillSourceCheckout]
    /// 每个物理检出的真实 Skill 成员；不同 clone/worktree 不互相污染更新影响名单。
    let checkoutSkillInventories: [CheckoutSkillInventory]

    init(
        id: SkillSourceKey,
        displayName: String,
        skills: [SkillDirectoryEntry],
        checkouts: [SkillSourceCheckout],
        checkoutSkillInventories: [CheckoutSkillInventory] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.skills = skills
        self.checkouts = checkouts
        self.checkoutSkillInventories = checkoutSkillInventories
    }

    func skills(atCheckoutCanonicalPath checkoutPath: String) -> [SkillDirectoryEntry] {
        guard let inventory = checkoutSkillInventories.first(where: {
            $0.checkoutCanonicalPath == checkoutPath
        }) else { return [] }
        let identities = Set(inventory.skillIdentities)
        return skills.filter { identities.contains($0.id) }
    }

    /// 仓库行的宿主并集（全部子 Skill 的安装事实）。
    var hosts: Set<AgentHost> {
        Set(skills.flatMap(\.hosts))
    }
}

/// 无仓库可归行：Unattributed Installation 的呈现条目（CONTEXT.md：来源不明、不可更新）。
/// 内容完全一致（内容指纹相同）的多个复制安装聚合为一个只读呈现组；
/// 内容不同或读取不完整（无指纹）时按安装 Canonical Path 各自单列。
/// 聚合只是呈现：不推断 Skill Source，不产生更新目标（ADR-0001 §4）。
struct UnattributedInstallationItem: Identifiable, Hashable, Sendable {
    /// 稳定标识：可合并组为 `sha256:<内容指纹>`；不可合并单例为安装 Canonical Path。
    let id: String
    let displayName: String
    /// 代表 canonical 路径（读取 SKILL.md 原文用；组内内容指纹一致，任一同效）。
    let canonicalPath: String
    let installations: [SkillInstallation]

    /// 宿主并集（S2：logo 槽位点亮 = 任一安装事实）。
    var hosts: Set<AgentHost> {
        Set(installations.flatMap(\.hosts))
    }
}

/// 目录分组的完整产物：来源仓库行集合 + 无仓库可归行集合。
struct SkillDirectoryContents: Sendable {
    let sources: [SkillSourceItem]
    let unattributedInstallations: [UnattributedInstallationItem]
    let mappingTargets: [SkillDirectoryEntry]
    let invalidMappings: [SourceMappingProjection]
}
