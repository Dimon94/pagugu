import XCTest
@testable import Pagugu

final class PersistenceTests: XCTestCase {
    private enum TestInterruption: Error {
        case beforeReplace
    }

    private var directoryURL: URL!
    private let fileManager = FileManager.default

    override func setUp() {
        super.setUp()
        directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: directoryURL)
        super.tearDown()
    }

    func testMissingRegistryLoadsAsNormalEmptyState() async {
        let persistence = Persistence(directoryURL: directoryURL)

        let result = await persistence.loadRegistry()

        XCTAssertEqual(result, .ready(.empty))
        XCTAssertFalse(fileManager.fileExists(atPath: directoryURL.appendingPathComponent("registry.json").path))
    }

    func testLivePersistenceIsSingleWriterSharedAcrossWindows() {
        XCTAssertTrue(Persistence.live === Persistence.live)
    }

    func testCompatibilityMatrix() async throws {
        struct Case {
            let name: String
            let json: String
            let expectedKind: RegistryRecovery.Kind?
        }

        let cases = [
            Case(name: "空文件", json: "", expectedKind: .corrupt),
            Case(name: "不可解析", json: "{", expectedKind: .corrupt),
            Case(
                name: "缺少必填集合",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "当前无已知旧版本迁移",
                json: #"{"schemaVersion":0,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "未知未来版本",
                json: #"{"schemaVersion":2,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .unknownFutureVersion
            ),
            Case(
                name: "布尔 schema 版本",
                json: #"{"schemaVersion":true,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "非整数 schema 版本",
                json: #"{"schemaVersion":1.5,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            // 错误实现会失败：JSONDecoder 会把 1.0 解码成 Int 1，继而错误进入 ready。
            Case(
                name: "浮点字面量 schema 版本",
                json: #"{"schemaVersion":1.0,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "等价浮点字面量 schema 版本",
                json: #"{"schemaVersion":1.00,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "未知字段",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{},"futureOptional":true}"#,
                expectedKind: nil
            ),
            Case(
                name: "类型不符",
                json: #"{"schemaVersion":1,"projectScanRoots":"wrong","sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "来源键未规范化",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{"/installation":{"skillSourceKey":"HTTPS://github.com/Owner/repo.git","repositoryRelativePath":"skills/example"}},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "来源键含空路径段",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{"/installation":{"skillSourceKey":"github.com//Owner/repo","repositoryRelativePath":"skills/example"}},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "点号不是 canonical 仓库根相对路径",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{"/installation":{"skillSourceKey":"/repository","repositoryRelativePath":"."}},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "路径未规范化",
                json: #"{"schemaVersion":1,"projectScanRoots":[{"canonicalPath":"/tmp/../root","asFoundPath":"/root"}],"sourceMappings":{},"checkoutObservations":{}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "成功观察缺少 remote tip",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{"/checkout":{"result":"success","completedAt":"2026-08-25T00:00:00Z","identityDigest":{"checkoutCanonicalPath":"/checkout","gitCommonDirIdentifier":"git-dir","normalizedRemoteURL":"git@example.com:repo.git","branchName":"main","upstreamRefName":"origin/main"}}}}"#,
                expectedKind: .corrupt
            ),
            Case(
                name: "失败观察错误携带 remote tip",
                json: #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{"/checkout":{"result":"failure","completedAt":"2026-08-25T00:00:00Z","remoteTipSHA":"abc123","identityDigest":{"checkoutCanonicalPath":"/checkout","gitCommonDirIdentifier":"git-dir","normalizedRemoteURL":"git@example.com:repo.git","branchName":"main","upstreamRefName":"origin/main"}}}}"#,
                expectedKind: .corrupt
            ),
        ]

        for testCase in cases {
            let caseDirectory = directoryURL.appendingPathComponent(UUID().uuidString)
            try fileManager.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
            let registryURL = caseDirectory.appendingPathComponent("registry.json")
            let originalData = Data(testCase.json.utf8)
            try originalData.write(to: registryURL)

            let result = await Persistence(directoryURL: caseDirectory).loadRegistry()

            if let expectedKind = testCase.expectedKind {
                guard case .restricted(let recovery) = result else {
                    return XCTFail("\(testCase.name) 应进入受限恢复模式")
                }
                XCTAssertEqual(recovery.kind, expectedKind, testCase.name)
                if expectedKind == .unknownFutureVersion {
                    XCTAssertEqual(recovery.evidenceURL, registryURL)
                    XCTAssertEqual(try Data(contentsOf: registryURL), originalData)
                } else {
                    XCTAssertNotEqual(recovery.evidenceURL, registryURL)
                    XCTAssertFalse(fileManager.fileExists(atPath: registryURL.path), testCase.name)
                    XCTAssertEqual(try Data(contentsOf: recovery.evidenceURL), originalData)
                }
            } else {
                XCTAssertEqual(result, .ready(.empty), testCase.name)
                XCTAssertEqual(try Data(contentsOf: registryURL), originalData)
            }
        }
    }

    // review-r2 回归守卫：schema 版本边界必须保持 typed Decodable，不能退回无类型桥接。
    func testSchemaVersionDecoderUsesTypedBoundaryWithoutUntypedJSONBridges() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Pagugu/Persistence/Persistence.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "private func decodeSchemaVersion"))
        let end = try XCTUnwrap(source.range(
            of: "private func quarantineCorruptRegistry",
            range: start.upperBound..<source.endIndex
        ))
        let decoderSource = source[start.lowerBound..<end.lowerBound]

        XCTAssertTrue(decoderSource.contains("JSONDecoder"))
        XCTAssertTrue(decoderSource.contains("RegistrySchemaHeader.self"))
        for forbiddenBoundary in ["JSONSerialization", "[String: Any]", "NSNumber"] {
            XCTAssertFalse(
                decoderSource.contains(forbiddenBoundary),
                "schemaVersion 解码不得使用无类型边界：\(forbiddenBoundary)"
            )
        }
    }

    func testSourceMappingAcceptsEmptyRelativePathForSkillAtRepositoryRoot() async throws {
        let caseDirectory = directoryURL.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: caseDirectory, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{"/installation":{"skillSourceKey":"/repository","repositoryRelativePath":""}},"checkoutObservations":{}}"#
        try Data(json.utf8).write(to: caseDirectory.appendingPathComponent("registry.json"))

        let result = await Persistence(directoryURL: caseDirectory).loadRegistry()

        guard case .ready(let document) = result else {
            return XCTFail("仓库根 Skill 的空相对路径应是合法 canonical 值")
        }
        XCTAssertEqual(document.sourceMappings["/installation"]?.repositoryRelativePath, "")
    }

    func testDurableWriteUsesRequiredPermissionsAndDropsUnknownFields() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let json = #"{"schemaVersion":1,"projectScanRoots":[],"sourceMappings":{},"checkoutObservations":{},"futureOptional":true}"#
        try Data(json.utf8).write(to: registryURL)
        let persistence = Persistence(directoryURL: directoryURL)
        guard case .ready(let document) = await persistence.loadRegistry() else {
            return XCTFail("含未知字段的 v1 Registry 应正常加载")
        }

        try await persistence.saveRegistry(document)

        let rewritten = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: registryURL)) as? [String: Any]
        )
        XCTAssertEqual(
            Set(rewritten.keys),
            ["schemaVersion", "projectScanRoots", "sourceMappings", "checkoutObservations"]
        )
        XCTAssertNil(rewritten["futureOptional"])
        let directoryMode = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: directoryURL.path)[.posixPermissions] as? NSNumber
        ).intValue
        let fileMode = try XCTUnwrap(
            fileManager.attributesOfItem(atPath: registryURL.path)[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
    }

    func testExternalModificationFailsClosedWithoutOverwrite() async throws {
        let persistence = Persistence(directoryURL: directoryURL)
        let initialLoad = await persistence.loadRegistry()
        XCTAssertEqual(initialLoad, .ready(.empty))
        let first = document(scanRoot: "/first")
        try await persistence.saveRegistry(first)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        var externallyModified = try Data(contentsOf: registryURL)
        externallyModified.append(0x0A)
        try externallyModified.write(to: registryURL)

        do {
            try await persistence.saveRegistry(document(scanRoot: "/second"))
            XCTFail("外部修改后必须拒绝覆写")
        } catch let error as PersistenceError {
            guard case .externallyModified(let recovery) = error else {
                return XCTFail("错误类型不符：\(error)")
            }
            XCTAssertEqual(recovery.kind, .externallyModified)
            XCTAssertEqual(recovery.evidenceURL, registryURL)
        }
        XCTAssertEqual(try Data(contentsOf: registryURL), externallyModified)
    }

    func testInterruptionBeforeRenameKeepsLastGoodRegistry() async throws {
        let initial = Persistence(directoryURL: directoryURL)
        let initialLoad = await initial.loadRegistry()
        XCTAssertEqual(initialLoad, .ready(.empty))
        let lastGood = document(scanRoot: "/last-good")
        try await initial.saveRegistry(lastGood)

        let interrupted = Persistence(directoryURL: directoryURL) {
            throw TestInterruption.beforeReplace
        }
        let interruptedLoad = await interrupted.loadRegistry()
        XCTAssertEqual(interruptedLoad, .ready(lastGood))

        do {
            try await interrupted.saveRegistry(document(scanRoot: "/new"))
            XCTFail("rename 前中断应报告写失败")
        } catch let error as PersistenceError {
            guard case .writeFailed = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }

        let reloaded = await Persistence(directoryURL: directoryURL).loadRegistry()
        XCTAssertEqual(reloaded, .ready(lastGood))
        let temporaryFiles = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
            .filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(temporaryFiles.isEmpty)
    }

    func testResetRequiresConfirmationAndQuarantinesBeforeWritingEmptyRegistry() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let futureData = Data(
            #"{"schemaVersion":2,"projectScanRoots":[{"canonicalPath":"/kept","asFoundPath":"/kept"}],"sourceMappings":{},"checkoutObservations":{}}"#.utf8
        )
        try futureData.write(to: registryURL)
        let persistence = Persistence(directoryURL: directoryURL)
        guard case .restricted(let recovery) = await persistence.loadRegistry() else {
            return XCTFail("未来版本应进入受限恢复模式")
        }
        XCTAssertEqual(recovery.kind, .unknownFutureVersion)
        XCTAssertTrue(Persistence.resetImpact.contains("Project Scan Root"))
        XCTAssertTrue(Persistence.resetImpact.contains("来源映射"))
        XCTAssertTrue(Persistence.resetImpact.contains("上次观察"))
        XCTAssertTrue(Persistence.resetImpact.contains("人工重建"))
        XCTAssertTrue(Persistence.resetImpact.contains("重新检查"))

        do {
            _ = try await persistence.resetRegistry(confirmed: false)
            XCTFail("未确认不得重置")
        } catch let error as PersistenceError {
            XCTAssertEqual(error, .resetConfirmationRequired)
        }
        XCTAssertEqual(try Data(contentsOf: registryURL), futureData)

        let resetBackup = try await persistence.resetRegistry(confirmed: true)
        let quarantineURL = try XCTUnwrap(resetBackup)

        XCTAssertNotEqual(quarantineURL, registryURL)
        XCTAssertEqual(try Data(contentsOf: quarantineURL), futureData)
        let resetLoad = await persistence.loadRegistry()
        XCTAssertEqual(resetLoad, .ready(.empty))
        let reloaded = await Persistence(directoryURL: directoryURL).loadRegistry()
        XCTAssertEqual(reloaded, .ready(.empty))
    }

    func testEveryStableUpdateFailureReasonIsValidAuditEvidence() async throws {
        XCTAssertEqual(
            AuditRecord.UpdateFailureReasonCode.allCases.map(\.rawValue),
            UpdateRunFailureReason.allCases.map(\.rawValue),
            "Persistence wire code 必须与 Runs 拥有的稳定失败类完全一致"
        )
        let persistence = Persistence(directoryURL: directoryURL)

        for reason in UpdateRunFailureReason.allCases {
            try await persistence.appendAuditEvidence(
                updateFailureRecord(id: reason.rawValue, reasonCode: reason.rawValue)
            )
        }

        let document = await persistence.loadAuditDocument()
        XCTAssertEqual(
            document?.records.compactMap(\.updateFailureReason),
            UpdateRunFailureReason.allCases.map(\.rawValue)
        )
    }

    // 错误实现会失败：只校验 kebab-case 会让未知 code 进入历史，随后 UI 无法把它
    // 转为 UpdateRunFailureReason，并静默隐藏整段失败原因。
    func testUnknownUpdateFailureReasonMakesAuditHistoryUnavailable() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let auditURL = directoryURL.appendingPathComponent("audit-history.json")
        let document = AuditDocument(
            schemaVersion: AuditDocument.currentSchemaVersion,
            records: [updateFailureRecord(id: "unknown", reasonCode: "not-a-reason")]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: auditURL)

        let loaded = await Persistence(directoryURL: directoryURL).loadAuditDocument()
        let projection = AuditPresentation.project(loaded)

        XCTAssertNil(loaded, "未知失败类必须走历史不可用，不能作为合法记录进入 UI")
        XCTAssertTrue(projection.isUnavailable)
        XCTAssertEqual(AuditHistoryProjection.unavailableMessage, "历史不可用")
        XCTAssertFalse(fileManager.fileExists(atPath: auditURL.path))
        let quarantined = try fileManager.contentsOfDirectory(atPath: directoryURL.path)
        XCTAssertTrue(quarantined.contains { $0.hasPrefix("audit-history.corrupt-") })
    }

    func testAuditV1KeepsPreActionSourceMappingRecordsReadable() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"records":[{"id":"legacy","recordedAt":"2026-08-25T00:00:00Z","outcome":"created","installationCanonicalPath":"/installation","target":{"skillSourceKey":"github.com/Owner/repo","repositoryRelativePath":"skills/example"}}]}"#
        try Data(json.utf8).write(to: directoryURL.appendingPathComponent("audit-history.json"))
        let persistence = Persistence(directoryURL: directoryURL)

        let audit = await persistence.loadAuditEvidence()

        XCTAssertEqual(audit.records.count, 1)
        XCTAssertEqual(audit.records.first?.action, .sourceMapping)
        XCTAssertEqual(audit.records.first?.outcome, .created)
        XCTAssertEqual(audit.records.first?.installationCanonicalPath, "/installation")
    }

    func testMissingAuditLoadsAsNormalEmptyHistory() async {
        let persistence = Persistence(directoryURL: directoryURL)

        let document = await persistence.loadAuditDocument()
        let projection = AuditPresentation.project(document)

        XCTAssertEqual(document, .empty)
        XCTAssertFalse(projection.isUnavailable)
        XCTAssertTrue(projection.items.isEmpty)
        XCTAssertFalse(fileManager.fileExists(
            atPath: directoryURL.appendingPathComponent("audit-history.json").path
        ))
    }

    // 错误实现会失败：已有但不可读的审计文件不能冒充正常空历史。
    func testUnreadableAuditIsQuarantinedAndSignalsHistoryUnavailable() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let auditURL = directoryURL.appendingPathComponent("audit-history.json")
        try Data(#"{"schemaVersion":1,"records":[]}"#.utf8).write(to: auditURL)
        try fileManager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: auditURL.path)
        XCTAssertThrowsError(try Data(contentsOf: auditURL), "测试夹具必须真实触发字节读取失败")
        let persistence = Persistence(directoryURL: directoryURL)

        let document = await persistence.loadAuditDocument()
        let projection = AuditPresentation.project(document)

        XCTAssertNil(document, "读取失败必须向呈现层暴露不可用信号")
        XCTAssertTrue(projection.isUnavailable)
        XCTAssertTrue(projection.items.isEmpty)
        XCTAssertEqual(AuditHistoryProjection.unavailableMessage, "历史不可用")
        XCTAssertFalse(fileManager.fileExists(atPath: auditURL.path), "不可读审计必须被 quarantine")
        let quarantined = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertTrue(quarantined.first?.lastPathComponent.hasPrefix("audit-history.corrupt-") == true)
    }

    // 错误实现会失败：损坏审计必须 fail-open 返回空历史、quarantine 原文件，
    // 并向调用方暴露「历史不可用」信号；不能静默重建为空冒充正常空历史。
    func testCorruptAuditLoadsEmptyFailOpenAndSignalsUnavailable() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let auditURL = directoryURL.appendingPathComponent("audit-history.json")
        try Data("not json".utf8).write(to: auditURL)
        let persistence = Persistence(directoryURL: directoryURL)

        let document = await persistence.loadAuditDocument()
        let audit = await persistence.loadAuditEvidence()

        XCTAssertNil(document, "损坏审计必须向呈现层暴露不可用信号")
        XCTAssertEqual(audit, .empty, "损坏审计 fail-open：丢弃重建为空")
        XCTAssertFalse(fileManager.fileExists(atPath: auditURL.path))
        let quarantined = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertTrue(quarantined.first?.lastPathComponent.hasPrefix("audit-history.corrupt-") == true)

        // 损坏不阻断后续写入：追加记录后历史恢复正常可读。
        try await persistence.appendAuditEvidence(AuditRecord(
            id: "after-corruption",
            recordedAt: Date(timeIntervalSince1970: 1),
            outcome: .created,
            installationCanonicalPath: "/installations/example",
            target: SourceMappingRecord(
                skillSourceKey: "github.com/Owner/repo",
                repositoryRelativePath: "skills/example"
            )
        ))
        let recovered = await persistence.loadAuditDocument()
        XCTAssertEqual(recovered?.records.map(\.id), ["after-corruption"])
    }

    func testClearAuditEvidenceOnlyRemovesAuditCollectionWithoutTombstone() async throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let registryURL = directoryURL.appendingPathComponent("registry.json")
        let registryJSON = #"{"schemaVersion":1,"projectScanRoots":[{"canonicalPath":"/scan","asFoundPath":"/scan"}],"sourceMappings":{},"checkoutObservations":{}}"#
        try Data(registryJSON.utf8).write(to: registryURL)
        let persistence = Persistence(directoryURL: directoryURL)
        _ = await persistence.loadRegistry()
        try await persistence.appendAuditEvidence(AuditRecord(
            id: "legacy",
            recordedAt: Date(timeIntervalSince1970: 1),
            outcome: .created,
            installationCanonicalPath: "/installations/example",
            target: SourceMappingRecord(
                skillSourceKey: "github.com/Owner/repo",
                repositoryRelativePath: "skills/example"
            )
        ))

        try await persistence.clearAuditEvidence()

        let reloaded = await Persistence(directoryURL: directoryURL)
        let cleared = await reloaded.loadAuditEvidence()
        XCTAssertTrue(cleared.records.isEmpty, "清空不留墓碑记录")
        let registryReload = await reloaded.loadRegistry()
        XCTAssertEqual(
            registryReload,
            .ready(document(scanRoot: "/scan")),
            "清空审计不得触碰 Registry"
        )
    }

    func testAuditEvidenceKeepsLatestTwoHundredRecords() async throws {
        let persistence = Persistence(directoryURL: directoryURL)
        let target = SourceMappingRecord(
            skillSourceKey: "github.com/Owner/repo",
            repositoryRelativePath: "skills/example"
        )

        for index in 0..<201 {
            try await persistence.appendAuditEvidence(AuditRecord(
                id: String(index),
                recordedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                outcome: .created,
                installationCanonicalPath: "/installations/\(index)",
                target: target
            ))
        }

        let audit = await persistence.loadAuditEvidence()
        XCTAssertEqual(audit.records.count, 200)
        XCTAssertEqual(audit.records.first?.id, "1")
        XCTAssertEqual(audit.records.last?.id, "200")
    }

    private func updateFailureRecord(id: String, reasonCode: String) -> AuditRecord {
        AuditRecord(
            id: id,
            recordedAt: Date(timeIntervalSince1970: 1),
            updateRunID: "run-\(id)",
            phase: .terminal,
            target: .init(
                skillIdentity: .init(
                    skillSourceKey: "github.com/Owner/repo",
                    repositoryRelativePath: "skills/example"
                ),
                checkoutCanonicalPath: "/checkouts/repo",
                branchName: "main",
                upstreamRefName: "origin/main"
            ),
            outcome: .failed,
            failureReason: reasonCode
        )
    }

    private func document(scanRoot: String) -> RegistryDocument {
        RegistryDocument(
            schemaVersion: RegistryDocument.currentSchemaVersion,
            projectScanRoots: [
                ProjectScanRootRecord(canonicalPath: scanRoot, asFoundPath: scanRoot),
            ],
            sourceMappings: [:],
            checkoutObservations: [:]
        )
    }
}
