//
//  LibraryTests.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation
import SwiftSyntax
import Testing
@testable import SwiftCheckCore

/// A temporary project folder, removed when the value goes away.
private final class TempProject {
    let root: URL

    init(config: String? = nil, files: [String: String] = [:]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcheck-lib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let config { try write(Configuration.fileName, config) }
        for (path, text) in files { try write(path, text) }
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

@Suite struct ProjectAPITests {
    @Test func opensConfigurationAndDiscoversRoot() throws {
        let temp = try TempProject(config: #"{"rules": {"force-unwrap": "error"}}"#, files: ["Sources/App/A.swift": "let a = b!\n"])
        #expect(Project.hasConfiguration(at: temp.root))
        let project = try Project(root: temp.root)
        #expect(project.ruleSet.rules.first { $0.rule.id == "force-unwrap" }?.severity == .error)
        #expect(project.root == FileCollector.canonical(temp.root))

        let discovered = try #require(try Project.discover(from: temp.root.appendingPathComponent("Sources/App")))
        #expect(discovered.root == project.root)
        #expect(try Project.discover(from: URL(fileURLWithPath: "/")) == nil)
    }

    @Test func invalidConfigurationThrows() throws {
        let temp = try TempProject(config: #"{"rules": {"force-unwrap": "loud"}}"#)
        #expect(throws: Configuration.ConfigError.self) { try Project(root: temp.root) }
    }

    @Test func checksPathsAndReportsSkipped() throws {
        let temp = try TempProject(config: #"{"exclude": ["Generated"]}"#, files: [
            "A.swift": "let a = b!\nlet c = try! d()\n",
            "Generated/G.swift": "let a = b!\n",
            "notes.md": "x",
        ])
        let project = try Project(root: temp.root)
        let result = project.check(paths: ["A.swift", "Generated/G.swift", "notes.md", "Missing.swift"])
        #expect(result.files == ["A.swift"])
        #expect(Set(result.skipped) == ["Generated/G.swift", "notes.md", "Missing.swift"])
        #expect(result.reported.map(\.rule) == ["force-unwrap", "force-try"])
        #expect(result.errorCount == 1 && result.warningCount == 1 && result.hasErrors)
        #expect(result.violationsByFile["A.swift"]?.count == 2)
        #expect(result.absolutePath(of: result.reported[0]) == project.root.appendingPathComponent("A.swift").path)
        #expect(!result.wasCancelled)
    }

    @Test func checksSourcesInMemory() throws {
        let temp = try TempProject(config: #"{"include": ["Sources"]}"#)
        let project = try Project(root: temp.root)
        let result = project.check(sources: [
            SourceInput(path: "Sources/A.swift", text: "let a = b as! C\n"),
            SourceInput(path: "Tests/T.swift", text: "let a = b!\n"),
            SourceInput(path: "Sources/readme.txt", text: "x!"),
            SourceInput(path: "/elsewhere/X.swift", data: Data("let x = try! y()\n".utf8)),
        ])
        #expect(result.files == ["Sources/A.swift", "/elsewhere/X.swift"])
        #expect(result.skipped == ["Tests/T.swift", "Sources/readme.txt"])
        #expect(result.reported.map(\.rule).sorted() == ["force-cast", "force-try"])
        // Nothing was written to disk.
        #expect(!FileManager.default.fileExists(atPath: temp.root.appendingPathComponent("Sources").path))
    }

    @Test func baselineIsAppliedAndUpdated() throws {
        let temp = try TempProject(config: "{}", files: ["A.swift": "let a = b!\n", "B.swift": "let c = d!\n"])
        var project = try Project(root: temp.root)
        #expect(project.baseline == nil)
        try project.updateBaseline(with: project.checkAll(), replacingAll: true)

        project = try Project(root: temp.root)
        #expect(project.baseline?.counts.count == 2)
        let all = project.checkAll()
        #expect(all.reported.isEmpty && all.baselinedCount == 2)
        #expect(project.checkAll(options: CheckOptions(applyBaseline: false)).reported.count == 2)

        // A new violation in A.swift: partial update keeps B.swift's entry.
        try temp.write("A.swift", "let a = b!\nlet e = f!\n")
        project = try Project(root: temp.root)
        #expect(project.check(paths: ["A.swift"]).reported.map(\.line) == [2])
        let updated = try project.updateBaseline(with: project.check(paths: ["A.swift"]), replacingAll: false)
        #expect(updated.counts.values.reduce(0, +) == 3)
        #expect(updated.counts.keys.contains { $0.hasPrefix("B.swift|") })
    }

    @Test func cancellationStopsTheRun() throws {
        let temp = try TempProject(config: "{}", files: ["A.swift": "let a = b!\n"])
        let result = try Project(root: temp.root).checkAll(options: CheckOptions(isCancelled: { true }))
        #expect(result.wasCancelled)
        #expect(result.violations.isEmpty)
    }

    @Test func customRulesCanBeAddedAndConfigured() throws {
        let noLegacy = Rule(
            id: "no-legacy", severity: .warning, message: "legacy call", description: "",
            kinds: [.functionCallExpr],
            examples: RuleExamples(triggering: [], nonTriggering: []),
            check: { node, _ in
                guard let call = node.as(FunctionCallExprSyntax.self),
                      SyntaxHelpers.freeFunctionName(call) == "legacy" else { return [] }
                return [Finding(at: call.calledExpression)]
            }
        )
        let temp = try TempProject(config: #"{"rules": {"no-legacy": "error"}}"#)
        #expect(try Project(root: temp.root).unknownRuleIDs == ["no-legacy"])

        let project = try Project(root: temp.root, rules: RuleRegistry.all + [noLegacy])
        #expect(project.unknownRuleIDs.isEmpty)
        let result = project.check(sources: [SourceInput(path: "A.swift", text: "func f() { legacy(1) }\n")])
        #expect(result.reported.map(\.rule) == ["no-legacy"])
        #expect(result.reported.first?.severity == .error)
    }

    @Test func programmaticConfigurationOverridesFile() throws {
        let temp = try TempProject(config: #"{"rules": ["force-try"]}"#)
        let project = try Project(root: temp.root, configuration: Configuration(onlyRules: ["force-cast"]))
        #expect(project.ruleSet.rules.map(\.rule.id) == ["force-cast"])
    }

    @Test func usableFromBackgroundTasks() async throws {
        let temp = try TempProject(config: "{}", files: ["A.swift": "let a = b!\n"])
        let project = try Project(root: temp.root)
        let count = await Task.detached { project.checkAll().reported.count }.value
        #expect(count == 1)
    }

    @Test func jsonReportMatchesResult() throws {
        let temp = try TempProject(config: "{}", files: ["A.swift": "let a = b!\n"])
        let result = try Project(root: temp.root).checkAll()
        let report = try JSONDecoder().decode(Report.JSONReport.self, from: Data(try result.jsonReport().utf8))
        #expect(report.version == Report.jsonVersion)
        #expect(report.files == ["A.swift"])
        #expect(report.violations.map(\.rule) == ["force-unwrap"])
        #expect(report.root == result.root.path)
    }
}
