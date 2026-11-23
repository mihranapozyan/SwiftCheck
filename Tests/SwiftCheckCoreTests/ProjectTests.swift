//
//  ProjectTests.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import Testing
@testable import SwiftCheckCore
@testable import swiftcheck

private func violation(_ file: String, _ line: Int, _ text: String, rule: String = "force-unwrap") -> Violation {
    Violation(rule: rule, severity: .warning, file: file, line: line, column: 1, message: "m", offset: 0, lineText: text)
}

@Suite struct BaselineTests {
    @Test func reportsOnlyOccurrencesBeyondCount() {
        let baseline = Baseline(counts: ["A.swift|force-unwrap|let a = b!": 1])
        let applied = baseline.apply(to: [violation("A.swift", 10, "let a = b!"), violation("A.swift", 20, "let a = b!")])
        #expect(applied.map(\.baselined) == [true, false])
    }

    @Test func movedCodeStaysBaselined() {
        let baseline = Baseline(violations: [violation("A.swift", 3, "let a = b!")])
        #expect(baseline.apply(to: [violation("A.swift", 42, "let a = b!")]).allSatisfy { $0.baselined })
    }

    @Test func otherRuleOrFileIsNotBaselined() {
        let baseline = Baseline(violations: [violation("A.swift", 3, "let a = b!")])
        let applied = baseline.apply(to: [violation("B.swift", 3, "let a = b!"), violation("A.swift", 3, "let a = b!", rule: "x")])
        #expect(applied.allSatisfy { !$0.baselined })
    }

    @Test func partialUpdateKeepsOtherFiles() {
        let baseline = Baseline(counts: ["A.swift|r|x": 2, "B.swift|r|y": 1])
        let updated = baseline.updated(with: [violation("A.swift", 1, "z", rule: "r")], checkedFiles: ["A.swift"])
        #expect(updated.counts == ["A.swift|r|z": 1, "B.swift|r|y": 1])
        #expect(baseline.updated(with: [], checkedFiles: nil).counts.isEmpty)
    }

    @Test func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let baseline = Baseline(counts: ["A.swift|r|let a = b!": 3])
        try baseline.save(to: url)
        let loaded = try Baseline.load(from: url)
        #expect(loaded == baseline)
    }
}

@Suite struct ConfigurationTests {
    @Test func parsesObjectRules() throws {
        let json = #"{"include":["Sources"],"exclude":["**/Generated"],"baseline":"b.json","rules":{"force-unwrap":"error","bare-print":"off"}}"#
        let config = try Configuration.parse(Data(json.utf8))
        #expect(config.include == ["Sources"])
        #expect(config.baseline == "b.json")
        let rules = config.ruleSet().rules
        #expect(!rules.contains { $0.rule.id == "bare-print" })
        #expect(rules.first { $0.rule.id == "force-unwrap" }?.severity == .error)
        #expect(rules.count == RuleRegistry.all.count { !$0.isOptIn } - 1)
    }

    @Test func parsesRuleList() throws {
        let config = try Configuration.parse(Data(#"{"rules":["force-try","nope"]}"#.utf8))
        #expect(config.ruleSet().rules.map(\.rule.id) == ["force-try"])
        #expect(config.unknownRuleIDs() == ["nope"])
    }

    @Test func rejectsBadInput() {
        #expect(throws: Configuration.ConfigError.self) { try Configuration.parse(Data(#"{"rules":{"x":"loud"}}"#.utf8)) }
        #expect(throws: Configuration.ConfigError.self) { try Configuration.parse(Data(#"{"includes":[]}"#.utf8)) }
    }

    @Test func includeExclude() {
        let config = Configuration(include: ["Sources", "App/*.swift"], exclude: ["**/Generated", "Sources/Legacy"])
        #expect(config.accepts("Sources/A/B.swift"))
        #expect(config.accepts("App/Main.swift"))
        #expect(!config.accepts("App/Deep/Main.swift"))
        #expect(!config.accepts("Tests/A.swift"))
        #expect(!config.accepts("Sources/Generated/A.swift"))
        #expect(!config.accepts("Sources/Legacy/A.swift"))
    }

    @Test func globs() {
        #expect(Glob.matches("**/*.generated.swift", path: "a/b/c.generated.swift"))
        #expect(Glob.matches("*.swift", path: "a.swift"))
        #expect(!Glob.matches("*.swift", path: "dir/a.swift"))
        #expect(Glob.matches("Pods", path: "Pods/X/a.swift"))
        #expect(Glob.matches("./Sources/", path: "Sources/a.swift"))
        #expect(Glob.matches("Sour?es/**", path: "Sources/a/b.swift"))
        #expect(!Glob.matches("Sources", path: "SourcesExtra/a.swift"))
    }
}

@Suite struct CommandLineTests {
    @Test func parsesFlags() throws {
        let options = try CommandLineOptions.parse(["--files", "a.swift", "b.swift", "--json", "--root", "/x"])
        #expect(options.mode == .files(["a.swift", "b.swift"]))
        #expect(options.json)
        #expect(options.root == "/x")
        let diff = try CommandLineOptions.parse(["--diff", "main", "--xcode"])
        #expect(diff.mode == .diff("main"))
        let empty = try CommandLineOptions.parse([])
        #expect(empty.mode == .all)
    }

    @Test func rejectsConflicts() {
        #expect(throws: CommandLineOptions.ParseError.self) { try CommandLineOptions.parse(["--all", "--diff", "x"]) }
        #expect(throws: CommandLineOptions.ParseError.self) { try CommandLineOptions.parse(["--json", "--xcode"]) }
        #expect(throws: CommandLineOptions.ParseError.self) { try CommandLineOptions.parse(["--diff"]) }
        #expect(throws: CommandLineOptions.ParseError.self) { try CommandLineOptions.parse(["--bogus"]) }
    }
}

@Suite struct ReportTests {
    @Test func jsonSchema() throws {
        let root = URL(fileURLWithPath: "/project")
        let text = try Report.json(root: root, violations: [violation("A.swift", 2, "x")],
                                   files: ["A.swift"],
                                   durationMs: 7)
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["version", "root", "violations", "files", "durationMs"])
        #expect(object["version"] as? Int == 1)
        let first = try #require((object["violations"] as? [[String: Any]])?.first)
        #expect(Set(first.keys) == ["rule", "severity", "file", "line", "column", "message", "baselined"])
    }

    @Test func xcodeFormat() {
        let line = Report.xcodeLine(violation("A.swift", 2, "x"), root: URL(fileURLWithPath: "/p"))
        #expect(line == "/p/A.swift:2:1: warning: [force-unwrap] m")
    }
}

@Suite struct LinterTests {
    @Test func collectsAndLintsDirectory() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        for path in ["Sources/A.swift", "Sources/Generated/B.swift", ".build/C.swift", "Pods/D.swift", "readme.md"] {
            let url = root.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "let a = b!\n".write(to: url, atomically: true, encoding: .utf8)
        }
        let collector = FileCollector(root: root, configuration: Configuration(exclude: ["**/Generated"]))
        let files = collector.allFiles()
        #expect(files.map(\.relativePath) == ["Sources/A.swift"])
        let violations = Linter(ruleSet: RuleSet(rules: RuleRegistry.all)).lint(files)
        #expect(violations.map(\.file) == ["Sources/A.swift"])

        let explicit = collector.files(atPaths: ["Sources/A.swift", "Sources/Generated/B.swift", "readme.md"], relativeTo: collector.root)
        #expect(explicit.map(\.relativePath) == ["Sources/A.swift"])
    }
}
