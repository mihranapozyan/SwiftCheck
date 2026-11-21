//
//  EngineTests.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Testing
@testable import SwiftCheckCore

private func check(_ source: String, rules: [Rule] = RuleRegistry.all) -> [Violation] {
    SourceChecker.check(source: source, path: "File.swift", ruleSet: RuleSet(rules: rules))
}

@Suite struct SuppressionTests {
    @Test func sameLine() {
        #expect(check("let a = b! // swiftcheck:ignore force-unwrap — checked above", rules: [.forceUnwrap]).isEmpty)
    }

    @Test func lineAbove() {
        let source = """
            // swiftcheck:ignore force-unwrap — checked above
            let a = b!
            let c = d!
            """
        #expect(check(source, rules: [.forceUnwrap]).map(\.line) == [3])
    }

    @Test func multipleRules() {
        let source = "let a = b as! C; let d = e! // swiftcheck:ignore force-cast, force-unwrap - legacy"
        #expect(check(source, rules: [.forceCast, .forceUnwrap]).isEmpty)
    }

    @Test func otherRulesStillReported() {
        let source = "let a = b as! C; let d = e! // swiftcheck:ignore force-cast"
        #expect(check(source, rules: [.forceCast, .forceUnwrap]).map(\.rule) == ["force-unwrap"])
    }

    @Test func allKeyword() {
        #expect(check("let a = try! b as! C // swiftcheck:ignore all").isEmpty)
    }

    @Test func markerInsideStringIsNotAComment() {
        #expect(check(#"let a = b!; let s = "// swiftcheck:ignore force-unwrap""#, rules: [.forceUnwrap]).count == 1)
    }

    @Test func parsing() {
        #expect(Suppression.ruleIDs(inComment: "// swiftcheck:ignore a-b, c — reason with words") == ["a-b", "c"])
        #expect(Suppression.ruleIDs(inComment: "//swiftcheck:ignore x -- why") == ["x"])
        #expect(Suppression.ruleIDs(inComment: "// regular comment") == nil)
    }
}

@Suite struct ContextTests {
    @Test func debugConditions() {
        let cases: [(String, Bool)] = [
            ("#if DEBUG\nprint(1)\n#endif", false),
            ("#if !DEBUG\nprint(1)\n#endif", true),
            ("#if DEBUG && os(iOS) || DEBUG\nprint(1)\n#endif", false),
            ("#if os(iOS) || DEBUG\nprint(1)\n#endif", true),
            ("#if !(DEBUG || os(iOS))\nlet a = 1\n#else\nprint(1)\n#endif", true),
            ("#if !DEBUG || os(iOS)\nlet a = 1\n#else\nprint(1)\n#endif", false),
        ]
        for (source, triggers) in cases {
            #expect(!check(source, rules: [.barePrint]).isEmpty == triggers, "\(source)")
        }
    }

    @Test func contextIsRestoredAfterIfConfig() {
        let source = "#if DEBUG\nprint(1)\n#endif\nprint(2)"
        #expect(check(source, rules: [.barePrint]).map(\.line) == [4])
    }

    @Test func previewsAreSkippedForAllRules() {
        let source = """
            #Preview { let _ = print(token!) }
            extension Row: PreviewProvider { static var previews: some View { Text(x as! String) } }
            let after = value!
            """
        #expect(check(source).map(\.rule) == ["force-unwrap"])
    }
}

@Suite struct SensitiveNameTests {
    @Test func identifiers() {
        for name in ["token", "accessToken", "userPIN", "otpCode", "_password", "refreshTokens", "cardCvv"] {
            #expect(SensitiveName.isSensitiveIdentifier(name), "\(name)")
        }
        for name in ["Token", "TOKEN", "isTokenValid", "hasPin", "shouldShowPasscode", "tokenizer", "pinned",
                     "spinner", "tokenCount", "passwordField", "options"] {
            #expect(!SensitiveName.isSensitiveIdentifier(name), "\(name)")
        }
    }

    @Test func keys() {
        #expect(SensitiveName.isSensitiveKey("auth_token"))
        #expect(SensitiveName.isSensitiveKey("PIN_CODE"))
        #expect(!SensitiveName.isSensitiveKey("has_seen_pin"))
        #expect(!SensitiveName.isSensitiveKey("theme"))
    }
}

@Suite struct ViolationLocationTests {
    @Test func lineAndColumn() throws {
        let violation = try #require(check("\n  let a = b!", rules: [.forceUnwrap]).first)
        #expect(violation.line == 2)
        #expect(violation.column == 12)
        #expect(violation.lineText == "let a = b!")
        #expect(violation.severity == .warning)
    }
}
