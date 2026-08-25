import Foundation

// L3 COORD: Pagugu/Eligibility/CheckoutEligibility.swift
// POS: Eligibility 模块（ADR-0004、ADR-0009）。owns 12 态 precedence、观察身份与 freshness 裁决。
//      纯函数；does not own Git 调用、持久化或 UI。
// TEST: repo://PaguguTests/GitEligibilityTests.swift（precedence 与 freshness 表、真实 fetch 失效/恢复）。

enum CheckoutGitState: String, CaseIterable, Equatable, Sendable {
    case inspectionFailed = "inspection-failed"
    case noRemote = "no-remote"
    case detached
    case noUpstream = "no-upstream"
    case upstreamMismatch = "upstream-mismatch"
    case siblingConflict = "sibling-conflict"
    case checkUnknown = "check-unknown"
    case dirty
    case diverged
    case aheadOnly = "ahead-only"
    case updateAvailable = "update-available"
    case upToDate = "up-to-date"

    var displayName: String {
        switch self {
        case .inspectionFailed: return "检查失败"
        case .noRemote: return "仅本地来源"
        case .detached: return "HEAD 已分离"
        case .noUpstream: return "未配置上游"
        case .upstreamMismatch: return "上游来源不一致"
        case .siblingConflict: return "兄弟检出冲突"
        case .checkUnknown: return "尚未检查"
        case .dirty: return "有未提交改动"
        case .diverged: return "本地与上游已分叉"
        case .aheadOnly: return "本地领先"
        case .updateAvailable: return "可更新"
        case .upToDate: return "已是最新"
        }
    }

    var recoveryDirection: String {
        switch self {
        case .inspectionFailed: return "在终端确认该目录仍是完好的 Git 仓库，然后重新扫描。"
        case .noRemote: return "为该仓库配置 origin 后重新扫描。"
        case .detached: return "在终端切换到要维护的分支，然后重新扫描。"
        case .noUpstream: return "在终端为当前分支配置 upstream，然后重新扫描。"
        case .upstreamMismatch: return "将当前分支 upstream 改为该 Skill Source 的远端后重新扫描。"
        case .siblingConflict: return "先处理同一分支在另一 linked worktree 的检出，然后重新扫描。"
        case .checkUnknown: return "运行一次检查以获取远端位置。"
        case .dirty: return "先提交或清理本地改动，然后重新扫描。"
        case .diverged: return "在终端人工处理本地与上游分叉，然后重新检查。"
        case .aheadOnly: return "按需推送或处理本地提交；Pagugu 不会自动回退。"
        case .updateAvailable: return "可发起安全更新。"
        case .upToDate: return "无需处理；需要时可重新检查。"
        }
    }
}
enum CheckoutEligibility {
    // L4 IN: 实时 CheckoutGitFacts 与该检出的 Skill Source Key。
    // OUT: 按 ADR-0004 §6 precedence 唯一确定的主状态。
    // INVARIANT: localPath 来源永远 no-remote；仅 update-available 可更新。
    static func evaluate(facts: CheckoutGitFacts, sourceKey: SkillSourceKey) -> CheckoutGitState {
        if facts.inspectionFailure != nil { return .inspectionFailed }
        if case .localPath = sourceKey { return .noRemote }
        guard let head = facts.head else { return .inspectionFailed }
        guard case .branch = head else { return .detached }
        guard let upstream = facts.upstream else { return .noUpstream }
        guard upstream.remoteURL.flatMap(SkillSourceKey.normalize(remoteURL:)) == sourceKey else {
            return .upstreamMismatch
        }
        if facts.siblingBranchConflict { return .siblingConflict }
        if facts.relativePosition == .unknown { return .checkUnknown }
        if facts.dirty.isDirty { return .dirty }

        switch facts.relativePosition {
        case .diverged: return .diverged
        case .aheadOnly: return .aheadOnly
        case .behindOnly: return .updateAvailable
        case .upToDate: return .upToDate
        case .unknown: return .checkUnknown
        }
    }

    static func identityDigest(
        facts: CheckoutGitFacts,
        sourceKey: SkillSourceKey
    ) -> CheckoutIdentityDigest? {
        guard case .remoteURL(let normalizedRemoteURL) = sourceKey,
              let gitCommonDirectory = facts.gitCommonDirectory,
              let branchName = facts.head?.branchName,
              let upstream = facts.upstream,
              upstream.remoteURL.flatMap(SkillSourceKey.normalize(remoteURL:)) == sourceKey else {
            return nil
        }
        return CheckoutIdentityDigest(
            checkoutCanonicalPath: facts.checkoutPath,
            gitCommonDirIdentifier: gitCommonDirectory,
            normalizedRemoteURL: normalizedRemoteURL,
            branchName: branchName,
            upstreamRefName: upstream.ref
        )
    }

    // L4 IN: Registry 中的观察与同一检出的实时 Git Fact / Skill Source Key。
    // OUT: 完整身份摘要逐字段一致时为 true；不检查 result 或 remote-tracking tip。
    static func observationMatchesIdentity(
        _ observation: CheckoutObservation,
        facts: CheckoutGitFacts,
        sourceKey: SkillSourceKey
    ) -> Bool {
        observation.identityDigest == identityDigest(facts: facts, sourceKey: sourceKey)
    }

    // L4 OUT: 仅成功观察、身份一致且当前 upstream SHA 等于观察 tip 时有效。
    // INVARIANT: HEAD 与 dirty 不参与失效；无 TTL；本函数不修改或删除观察记录。
    static func observationIsFresh(
        _ observation: CheckoutObservation,
        facts: CheckoutGitFacts,
        sourceKey: SkillSourceKey
    ) -> Bool {
        observation.result == .success &&
            observationMatchesIdentity(observation, facts: facts, sourceKey: sourceKey) &&
            observation.remoteTipSHA == facts.upstream?.sha
    }
}
