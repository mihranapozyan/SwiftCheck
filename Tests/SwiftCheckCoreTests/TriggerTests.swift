//
//  TriggerTests.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26.
//

import Foundation
import SwiftSyntax
import Testing
@testable import SwiftCheckCore

private func check(_ source: String, rules: [Rule], path: String = "File.swift") -> [Violation] {
    SourceChecker.check(source: source, path: path, ruleSet: RuleSet(rules: rules))
}

/// A comment rule that reports every comment with its kind as the message.
private let commentProbe = Rule(
    id: "comment-probe", severity: .warning, message: "comment", description: "",
    examples: RuleExamples(triggering: [], nonTriggering: []),
    comments: { comment, _ in [Finding(comment.position, message: "\(comment.kind)")] }
)

/// A source rule that reports the start of every line containing `BAD`.
private let sourceProbe = Rule(
    id: "source-probe", severity: .error, message: "bad line", description: "",
    examples: RuleExamples(triggering: [], nonTriggering: []),
    source: { text in
        (0..<text.lineCount).compactMap { index in
            text.line(index).contains("BAD") ? Finding(AbsolutePosition(utf8Offset: text.lineStarts[index])) : nil
        }
    }
)

@Suite struct CommentTriggerTests {
    @Test func seesAllFourCommentKinds() {
        let source = "// a\n/* b */\n/// c\n/** d */\nlet x = 1 // e\n"
        let violations = check(source, rules: [commentProbe])
        #expect(violations.map(\.message) == ["line", "block", "docLine", "docBlock", "line"])
        #expect(violations.map(\.line) == [1, 2, 3, 4, 5])
        #expect(violations.map(\.column) == [1, 1, 1, 1, 11])
    }

    @Test func offsetsAreAbsoluteAfterNonAsciiText() {
        let source = "let s = \"héllo\" // x\n"
        let violation = check(source, rules: [commentProbe]).first
        #expect(violation?.offset == source.utf8.count - 5)
        #expect(violation?.lineText == source.trimmingCharacters(in: .newlines))
    }

    @Test func commentsInsideStringsAreNotComments() {
        #expect(check("let s = \"// no\"\n", rules: [commentProbe]).isEmpty)
    }

    @Test func tokensAreWalkedOnlyForCommentRules() {
        let syntaxOnly = RuleSet(rules: [.forceUnwrap])
        #expect(!RuleDispatcher(ruleSet: syntaxOnly, fileName: "A.swift", collectIgnores: false).scansTrivia)
        let withComments = RuleSet(rules: [.forceUnwrap, commentProbe])
        #expect(RuleDispatcher(ruleSet: withComments, fileName: "A.swift", collectIgnores: false).scansTrivia)
        let sourceOnly = RuleSet(rules: [sourceProbe])
        #expect(!RuleDispatcher(ruleSet: sourceOnly, fileName: "A.swift", collectIgnores: false).scansTrivia)
        #expect(RuleSet(rules: [.forceUnwrap]).commentRules.isEmpty)
        #expect(RuleSet(rules: [commentProbe]).commentRules == [0])
    }

    @Test func commentsInDebugCarryContext() {
        let rule = Rule(id: "debug-comment", severity: .warning, message: "m", description: "",
                        examples: RuleExamples(triggering: [], nonTriggering: []),
                        comments: { comment, context in context.inDebug ? [] : [Finding(comment.position)] })
        let source = "// outside\n#if DEBUG\n// inside\nlet a = 1\n#endif\n"
        #expect(check(source, rules: [rule]).map(\.line) == [1])
    }

    @Test func ignoreCommentSuppressesFindingOnTheNextLine() {
        let source = "// swiftcheck:ignore fixme-comment — tracked in the issue\n// FIXME: later\nlet a = 1\n"
        #expect(check(source, rules: [.fixmeComment]).isEmpty)
    }

    @Test func ignoreCommentDoesNotCoverLaterLines() {
        let source = "// swiftcheck:ignore fixme-comment\n// FIXME: first\n// FIXME: second\nlet a = 1\n"
        #expect(check(source, rules: [.fixmeComment]).map(\.line) == [3])
    }

    @Test func ignoreAllSuppressesCommentFindings() {
        let source = "let a = 1 // FIXME: x\n// swiftcheck:ignore all\n// XXX: y\nlet b = 2\n"
        #expect(check(source, rules: [.fixmeComment]).map(\.line) == [1])
    }

    @Test func baselineCoversCommentFindings() {
        let source = "// FIXME: old\nlet a = 1\n"
        let violations = check(source, rules: [.fixmeComment])
        #expect(violations.count == 1)
        #expect(violations.first?.lineText == "// FIXME: old")
        let applied = Baseline(violations: violations).apply(to: check("let b = 0\n" + source, rules: [.fixmeComment]))
        #expect(applied.map(\.baselined) == [true])
    }

    @Test func commentRulesCoexistWithSyntaxRules() {
        let source = "let a = b! // FIXME: unwrap\n"
        let violations = check(source, rules: [.forceUnwrap, .fixmeComment])
        #expect(Set(violations.map(\.rule)) == ["force-unwrap", "fixme-comment"])
    }
}

@Suite struct SourceTriggerTests {
    @Test func calledOncePerFileWithRawText() {
        let violations = check("ok\nBAD one\nfine\r\nBAD two\n", rules: [sourceProbe])
        #expect(violations.map(\.line) == [2, 4])
        #expect(violations.map(\.severity) == [.error, .error])
        #expect(violations.map(\.lineText) == ["BAD one", "BAD two"])
        #expect(violations.map(\.offset) == [3, 17])
    }

    @Test func lineRangesHandleCRLFAndMissingFinalNewline() {
        let text = SourceText(bytes: Array("a\r\nbb\nccc".utf8))
        #expect(text.lineCount == 3)
        #expect(text.line(0) == "a")
        #expect(text.line(1) == "bb")
        #expect(text.line(2) == "ccc")
    }

    @Test func ignoreCommentSuppressesSourceFindings() {
        #expect(check("BAD // swiftcheck:ignore source-probe\n", rules: [sourceProbe]).isEmpty)
        #expect(check("// swiftcheck:ignore source-probe\nBAD\n", rules: [sourceProbe]).isEmpty)
        #expect(check("// swiftcheck:ignore other-rule\nBAD\n", rules: [sourceProbe]).count == 1)
    }

    @Test func baselineCoversSourceFindings() {
        let violations = check("BAD thing\n", rules: [sourceProbe])
        let applied = Baseline(violations: violations).apply(to: check("// new\nBAD thing\n", rules: [sourceProbe]))
        #expect(applied.map(\.baselined) == [true])
    }

    @Test func conflictMarkersSurviveBrokenSyntax() {
        let source = "func f() {\n<<<<<<< HEAD\n    a()\n=======\n    b()\n>>>>>>> feature\n}\n"
        let violations = check(source, rules: [.conflictMarker])
        #expect(violations.map(\.line) == [2, 4, 6])
        #expect(violations.allSatisfy { $0.severity == .error })
    }

    @Test func separatorNeedsAnOpeningMarker() {
        #expect(check("=======\n", rules: [.conflictMarker]).isEmpty)
        #expect(check("<<<<<<< a\n>>>>>>> b\n=======\n", rules: [.conflictMarker]).map(\.line) == [1, 2])
    }
}

@Suite struct AsyncContextTests {
    private func lines(_ source: String) -> [Int] {
        check(source, rules: [.blockingInAsync]).map(\.line)
    }

    @Test func asyncFunctionsInitializersAndAccessors() {
        #expect(lines("func f() async {\nsleep(1)\n}") == [2])
        #expect(lines("struct S {\ninit() async {\nsleep(1)\n}\n}") == [3])
        #expect(lines("struct S {\nvar x: Int {\nget async {\nsleep(1)\nreturn 1\n}\n}\n}") == [4])
        #expect(lines("func f() {\nsleep(1)\n}").isEmpty)
    }

    @Test func taskClosures() {
        #expect(lines("Task {\nsleep(1)\n}") == [2])
        #expect(lines("Task.detached {\nsleep(1)\n}") == [2])
        #expect(lines("Task(priority: .high) {\nsleep(1)\n}") == [2])
        #expect(lines("Task(operation: {\nsleep(1)\n})") == [2])
        #expect(lines("Task<Void, Never> {\nsleep(1)\n}") == [2])
        #expect(lines("Task.detached(priority: .low) {\nsleep(1)\n}") == [2])
    }

    @Test func asyncClosureSignature() {
        #expect(lines("let f = { () async in\nsleep(1)\n}") == [2])
        #expect(lines("let f = {\nsleep(1)\n}").isEmpty)
    }

    @Test func plainClosuresAndNestedFunctionsReset() {
        #expect(lines("func f() async {\nqueue.async {\nsleep(1)\n}\n}").isEmpty)
        #expect(lines("func f() async {\nfunc inner() {\nsleep(1)\n}\n}").isEmpty)
        #expect(lines("Task {\nitems.forEach { _ in\nsleep(1)\n}\n}").isEmpty)
        #expect(lines("func f() async {\nsleep(1)\nqueue.async { sleep(2) }\nsleep(3)\n}") == [2, 4])
    }

    @Test func nestedAsyncFunctionInSyncContext() {
        #expect(lines("func f() {\nfunc g() async {\nsleep(1)\n}\nsleep(2)\n}") == [3])
    }

    @Test func otherCallsInTaskAreNotTaskBodies() {
        #expect(lines("DispatchQueue.main.async {\nsleep(1)\n}").isEmpty)
        #expect(lines("Tasks {\nsleep(1)\n}").isEmpty)
    }

    @Test func debugIsNotExcluded() {
        #expect(lines("func f() async {\n#if DEBUG\nsleep(1)\n#endif\n}") == [3])
    }
}

@Suite struct OptInTests {
    private func ids(_ json: String) throws -> Set<String> {
        try Configuration.parse(Data(json.utf8)).ruleSet().ids
    }

    private let optIn = Set(RuleRegistry.all.filter(\.isOptIn).map(\.id))

    @Test func optInRulesExist() {
        #expect(optIn == ["todo-comment", "unowned-reference", "unchecked-sendable", "discarded-try", "insecure-url"])
    }

    @Test func emptyConfigurationDoesNotEnableThem() throws {
        #expect(Configuration().ruleSet().ids.isDisjoint(with: optIn))
        #expect(try ids("{}").isDisjoint(with: optIn))
        #expect(try ids(#"{"include": ["Sources"]}"#).isDisjoint(with: optIn))
        #expect(try ids(#"{"rules": {"force-unwrap": "error"}}"#).isDisjoint(with: optIn))
        #expect(try ids("{}").count == RuleRegistry.all.count - optIn.count)
    }

    @Test func objectFormEnablesWithSeverityOrOn() throws {
        let config = try Configuration.parse(Data(#"{"rules": {"todo-comment": "error", "discarded-try": "on", "insecure-url": "warning"}}"#.utf8))
        let rules = config.ruleSet().rules
        #expect(rules.first { $0.rule.id == "todo-comment" }?.severity == .error)
        #expect(rules.first { $0.rule.id == "discarded-try" }?.severity == .warning)
        #expect(rules.first { $0.rule.id == "insecure-url" } != nil)
        #expect(rules.first { $0.rule.id == "unowned-reference" } == nil)
    }

    @Test func offKeepsThemDisabled() throws {
        #expect(try ids(#"{"rules": {"todo-comment": "off"}}"#).isDisjoint(with: optIn))
    }

    @Test func arrayFormEnablesListedRules() throws {
        #expect(try ids(#"{"rules": ["todo-comment", "force-try"]}"#) == ["todo-comment", "force-try"])
        #expect(try ids(#"{"rules": ["force-try"]}"#) == ["force-try"])
    }

    @Test func projectDefaultsLeaveThemOff() throws {
        let project = try Project(root: FileManager.default.temporaryDirectory, configuration: Configuration())
        #expect(project.ruleSet.ids.isDisjoint(with: optIn))
        let enabled = try Project(root: FileManager.default.temporaryDirectory,
                                  configuration: Configuration(overrides: ["todo-comment": .on(nil)]))
        #expect(enabled.ruleSet.ids.contains("todo-comment"))
        let result = enabled.check(sources: [SourceInput(path: "A.swift", text: "// TODO: x\nlet a = 1\n")])
        #expect(result.reported.map(\.rule) == ["todo-comment"])
    }

    @Test func customRulesKeepTheirSourceCompatibleInitializer() {
        let rule = Rule(id: "x", severity: .warning, message: "m", description: "d", kinds: [.functionCallExpr],
                        examples: RuleExamples(triggering: [], nonTriggering: []), check: { _, _ in [] })
        #expect(!rule.isOptIn)
        #expect(rule.commentCheck == nil && rule.sourceCheck == nil)
    }
}

@Suite struct MarkerMatcherTests {
    @Test func acceptsXcodeStyleMarkers() {
        let matcher = MarkerMatcher.fixme
        #expect(matcher.matches(in: "// FIXME: x").map(\.offset) == [3])
        #expect(matcher.matches(in: "// FIXME(anna): x").map(\.tag) == ["FIXME"])
        #expect(matcher.matches(in: "/// FIXME: x").count == 1)
        #expect(matcher.matches(in: "//! XXX: x").map(\.tag) == ["XXX"])
        #expect(matcher.matches(in: "/* XXX: x */").map(\.offset) == [3])
        #expect(matcher.matches(in: "/** FIXME: x */").count == 1)
        #expect(matcher.matches(in: "//FIXME:x").map(\.offset) == [2])
        #expect(MarkerMatcher.todo.matches(in: "# TODO: x").count == 1)
        #expect(MarkerMatcher.todo.matches(in: "-- TODO: x").count == 1)
        #expect(MarkerMatcher.todo.matches(in: "<!-- TODO: x -->").count == 1)
        #expect(MarkerMatcher.todo.matches(in: "; HACK: x").count == 1)
    }

    @Test func rejectsLooseMentions() {
        let matcher = MarkerMatcher.todo
        #expect(matcher.matches(in: "// User settings of the TODO tab").isEmpty)
        #expect(matcher.matches(in: "// TODO x").isEmpty)
        #expect(matcher.matches(in: "// todo: x").isEmpty)
        #expect(matcher.matches(in: "// MARK: - TODO list").isEmpty)
        #expect(matcher.matches(in: "// See TODO: below").isEmpty)
        #expect(matcher.matches(in: "// TODOS: x").isEmpty)
        #expect(matcher.matches(in: "// TODO").isEmpty)
        #expect(matcher.matches(in: "// TODO(anna x").isEmpty)
        #expect(matcher.matches(in: "TODO: no opener").isEmpty)
    }

    @Test func blockCommentsAreProcessedLineByLine() {
        let text = "/*\n * text\n * FIXME: a\n   * XXX: b\n * see FIXME: c\n */"
        #expect(MarkerMatcher.fixme.matches(in: text).map(\.tag) == ["FIXME", "XXX"])
    }

    @Test func offsetsAreInUTF8() {
        #expect(MarkerMatcher.todo.matches(in: "// é\n// TODO: x").map(\.offset) == [9])
    }

    @Test func fixmeAndTodoAreDisjoint() {
        #expect(MarkerMatcher.fixme.matches(in: "// TODO: x\n// HACK: y").isEmpty)
        #expect(MarkerMatcher.todo.matches(in: "// FIXME: x\n// XXX: y").isEmpty)
    }
}

@Suite struct NewRuleDetailTests {
    @Test func exitIsAllowedInMainSwift() {
        let source = "func stop() { exit(1) }\n"
        #expect(check(source, rules: [.exitCall], path: "Sources/App/main.swift").isEmpty)
        #expect(check(source, rules: [.exitCall], path: "main.swift").isEmpty)
        #expect(check(source, rules: [.exitCall], path: "Sources/App/Other.swift").count == 1)
        #expect(check(source, rules: [.exitCall], path: "Sources/App/domain.swift").count == 1)
    }

    @Test func fileNameIsReportedInContext() {
        #expect(SourceChecker.fileName(of: "a/b/main.swift") == "main.swift")
        #expect(SourceChecker.fileName(of: "main.swift") == "main.swift")
    }

    @Test func fatalErrorInNestedClosureInsideDefaultIsAllowed() {
        let source = "switch x {\ncase .a: break\ndefault: items.forEach { _ in fatalError() }\n}\n"
        #expect(check(source, rules: [.fatalErrorCall]).isEmpty)
    }

    @Test func fatalErrorInUnavailableType() {
        let source = "@available(*, unavailable)\nfinal class Old {\n    func f() { fatalError() }\n}\n"
        #expect(check(source, rules: [.fatalErrorCall]).isEmpty)
        #expect(check("@available(iOS 17, *)\nfunc f() { fatalError() }\n", rules: [.fatalErrorCall]).count == 1)
    }

    @Test func secretReportedOncePerLiteral() {
        let source = "let apiToken = \"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789\"\n" // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
        #expect(check(source, rules: [.hardcodedSecret]).count == 1)
    }

    @Test func privateKeyBlock() {
        let source = "let key = \"\"\"\n-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----\n\"\"\"\n" // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
        #expect(check(source, rules: [.hardcodedSecret]).count == 1)
    }

    @Test func secretInSecretNamedPlacesOnly() {
        #expect(check("let name = \"a8f3b2c1d4e5\"\n", rules: [.hardcodedSecret]).isEmpty)
        #expect(check("self.sessionToken = \"a8f3b2c1d4e5\"\n", rules: [.hardcodedSecret]).count == 1)
        #expect(check("api.login(password: \"a8f3b2c1d4e5\")\n", rules: [.hardcodedSecret]).count == 1)
    }

    @Test func unownedInCaptureListAndDeclaration() {
        let source = "final class A {\n    unowned let a: B\n    func f() { run { [unowned self, weak b] in } }\n}\n"
        #expect(check(source, rules: [.unownedReference]).map(\.line) == [2, 3])
    }

    @Test func insecureURLWithInterpolation() {
        #expect(check("let u = \"http://\\(host)/x\"\n", rules: [.insecureURL]).count == 1)
        #expect(check("let u = \"http://localhost:\\(port)/x\"\n", rules: [.insecureURL]).isEmpty)
        #expect(check("let u = \"https://\\(host)/x\"\n", rules: [.insecureURL]).isEmpty)
    }

    @Test func discardedTryImplicitReturns() {
        #expect(check("func f() -> Int? {\n    try? load()\n}\n", rules: [.discardedTry]).isEmpty)
        #expect(check("func f() {\n    try? load()\n}\n", rules: [.discardedTry]).count == 1)
        #expect(check("var x: Int? {\n    get { try? load() }\n}\n", rules: [.discardedTry]).isEmpty)
    }
}
