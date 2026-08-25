import Foundation

// L3 COORD: Pagugu/Discovery/SkillDiscovery.swift
// POS: Discovery 模块（ADR-0009 §2）。owns Discovery Scan：遍历 Scan Root、软链接解析、
//      Canonical Path 去重防环、SKILL.md 解析校验、Scan Issue。does not own 身份归因（归 Identity）。
// TEST: repo://PaguguTests/DiscoveryTests.swift（scratch 扫描测试）。
// IN: Personal Skill Root 路径列表；OUT: ScanResult（skills + issues + outcome）。

/// Discovery Scan 的产物状态（#3 resolution §8）。
enum ScanOutcome: Sendable {
    case complete
    case partial
    case failed
}

/// 跳过的单项问题：不可读目录、断链、不可解析的 SKILL.md 等。
struct ScanIssue: Sendable, Equatable {
    let path: String
    let reason: String
}

/// Discovery Scan 发现的一个候选 Skill（未归因，只产出事实）。
struct DiscoveredSkill: Sendable, Equatable {
    /// as-found 路径（展示用）。
    let asFoundPath: String
    /// 完全解析软链接后的绝对路径（归因与去重用）。
    let canonicalPath: String
    /// 目录名（展示元数据，不参与身份）。
    let name: String
}

/// Discovery Scan 的完整产出。
struct ScanResult: Sendable {
    let outcome: ScanOutcome
    let skills: [DiscoveredSkill]
    let issues: [ScanIssue]
}

// MARK: - Discovery 扫描入口

enum Discovery {
    static let personalSkillRoots: [String] = [
       ("~/.claude/skills" as NSString).expandingTildeInPath,
       ("~/.agents/skills" as NSString).expandingTildeInPath,
        ("~/.codex/skills" as NSString).expandingTildeInPath,
    ]

    /// 扫描指定 Personal Skill Root 列表，产出完整 ScanResult。
    /// Root 不存在时视为正常空态（#3 resolution §8）；其他错误记 Scan Issue 并标记 partial。
    /// Canonical Path 去重仅在同一 root 内防环；跨 root 的同一 Skill 由 Identity 层聚合（ADR-0001 §3）。
    static func scanPersonalRoots(_ roots: [String]) -> ScanResult {
        var skills: [DiscoveredSkill] = []
        var issues: [ScanIssue] = []
        var hasPartial = false

        for root in roots {
            var canonicals = Set<String>()
            let fm = FileManager.default
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
                // 不存在 = 正常空态，不记 Issue
                continue
            }
            scanDirectory(
                root,
                asFoundRoot: root,
                canonicals: &canonicals,
                skills: &skills,
                issues: &issues,
                partial: &hasPartial
            )
        }

        let outcome: ScanOutcome = hasPartial ? .partial : .complete
        return ScanResult(outcome: outcome, skills: skills, issues: issues)
    }

    /// 扫描单个 Project Scan Root。
    /// Canonical Path 去重仅在本次扫描内防环；跨 root 的同一 Skill 由 Identity 层聚合（ADR-0001 §3）。
    static func scanProjectRoot(_ root: String) -> ScanResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else {
            return ScanResult(outcome: .failed, skills: [], issues: [
                ScanIssue(path: root, reason: "目录不存在或不可读")
            ])
        }

        var skills: [DiscoveredSkill] = []
        var issues: [ScanIssue] = []
        var canonicals = Set<String>()
        var hasPartial = false

        scanDirectory(
            root,
            asFoundRoot: root,
            canonicals: &canonicals,
            skills: &skills,
            issues: &issues,
            partial: &hasPartial
        )

        let outcome: ScanOutcome = hasPartial ? .partial : .complete
        return ScanResult(outcome: outcome, skills: skills, issues: issues)
    }

    // MARK: - 递归遍历

    private static func scanDirectory(
        _ path: String,
        asFoundRoot: String,
        canonicals: inout Set<String>,
        skills: inout [DiscoveredSkill],
        issues: inout [ScanIssue],
        partial: inout Bool
    ) {
        let fm = FileManager.default
        let skillMD = (path as NSString).appendingPathComponent("SKILL.md")

        if fm.fileExists(atPath: skillMD) {
            // 命中 Skill：解析 frontmatter，叶子停止
            let canonical = resolveCanonical(path)
            if canonicals.contains(canonical) {
                return // Canonical Path 去重
            }
            canonicals.insert(canonical)

            if let skill = parseSkillMD(at: skillMD, asFoundPath: path, canonicalPath: canonical) {
                skills.append(skill)
            } else {
                issues.append(ScanIssue(path: path, reason: "SKILL.md 不可解析（frontmatter 缺失或格式错误）"))
                partial = true
            }
            return // 命中 Skill 后叶子停止
        }

        // 非 Skill 目录：继续递归子目录
        let children: [String]
        do {
            children = try fm.contentsOfDirectory(atPath: path)
        } catch {
            issues.append(ScanIssue(path: path, reason: "目录不可读：\(error.localizedDescription)"))
            partial = true
            return
        }

        for child in children.sorted() {
            let childPath = (path as NSString).appendingPathComponent(child)

            // 跟随软链接后的 canonical 路径用于防环
            let canonical = resolveCanonical(childPath)
            if canonicals.contains(canonical) {
                continue // 环或重复，跳过
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: childPath, isDirectory: &isDir), isDir.boolValue else {
                continue // 跳过文件
            }

            scanDirectory(
                childPath,
                asFoundRoot: asFoundRoot,
                canonicals: &canonicals,
                skills: &skills,
                issues: &issues,
                partial: &partial
            )
        }
    }

    // MARK: - Canonical Path

    /// `realpath` 完全解析软链接后的绝对路径；解析失败时回退到原始路径。
    static func resolveCanonical(_ path: String) -> String {
        (path as NSString).resolvingSymlinksInPath
    }

    // MARK: - SKILL.md frontmatter 解析

    /// 解析顶层精确 `SKILL.md`：校验 YAML frontmatter 的 `name` 和 `description` 字段。
    /// 无 frontmatter 或字段缺失记为 Scan Issue（不可解析）。
    private static func parseSkillMD(at path: String, asFoundPath: String, canonicalPath: String) -> DiscoveredSkill? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil // 无 frontmatter 开头
        }

        var name: String?
        var description: String?
        var inFrontmatter = false

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                break
            }
            inFrontmatter = true

            if trimmed.hasPrefix("name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                description = String(trimmed.dropFirst(12)).trimmingCharacters(in: .whitespaces)
            }
        }

        guard inFrontmatter, let resolvedName = name, !resolvedName.isEmpty else {
            return nil
        }
        // description 是 SHOULD requirement，缺失时仍视为可解析但不阻断
        _ = description

        let asFoundName = (asFoundPath as NSString).lastPathComponent
        return DiscoveredSkill(
            asFoundPath: asFoundPath,
            canonicalPath: canonicalPath,
            name: asFoundName
        )
    }
}
