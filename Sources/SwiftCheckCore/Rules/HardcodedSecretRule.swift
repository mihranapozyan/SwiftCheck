//
//  HardcodedSecretRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import Foundation
import SwiftSyntax

extension Rule {
    /// The shape of a well-known credential: a fixed prefix followed by a run of at least `minimum` allowed characters.
    private struct SecretShape: Sendable {
        let prefix: [UInt8]
        let allowed: @Sendable (UInt8) -> Bool
        let minimum: Int

        init(_ prefix: String, minimum: Int, allowed: @escaping @Sendable (UInt8) -> Bool) {
            self.prefix = Array(prefix.utf8)
            self.minimum = minimum
            self.allowed = allowed
        }

        func matches(_ bytes: [UInt8]) -> Bool {
            var start = 0
            while start + prefix.count <= bytes.count {
                if bytes[start..<start + prefix.count].elementsEqual(prefix) {
                    var end = start + prefix.count
                    while end < bytes.count, allowed(bytes[end]) { end += 1 }
                    let run = end - start - prefix.count
                    if run >= minimum { return true }
                }
                start += 1
            }
            return false
        }
    }

    private static let upperDigit: @Sendable (UInt8) -> Bool = { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) }
    private static let alnum: @Sendable (UInt8) -> Bool = { upperDigit($0) || ($0 >= 0x61 && $0 <= 0x7A) }
    private static let alnumDash: @Sendable (UInt8) -> Bool = { alnum($0) || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_") }

    private static let secretShapes: [SecretShape] = [
        SecretShape("AKIA", minimum: 16, allowed: upperDigit),
        SecretShape("ghp_", minimum: 36, allowed: alnum),
        SecretShape("gho_", minimum: 36, allowed: alnum),
        SecretShape("ghu_", minimum: 36, allowed: alnum),
        SecretShape("ghs_", minimum: 36, allowed: alnum),
        SecretShape("ghr_", minimum: 36, allowed: alnum),
        SecretShape("github_pat_", minimum: 22, allowed: { alnum($0) || $0 == UInt8(ascii: "_") }),
        SecretShape("sk-ant-", minimum: 20, allowed: alnumDash),
        SecretShape("sk-", minimum: 20, allowed: alnum),
        SecretShape("xoxa-", minimum: 10, allowed: { alnum($0) || $0 == UInt8(ascii: "-") }),
        SecretShape("xoxb-", minimum: 10, allowed: { alnum($0) || $0 == UInt8(ascii: "-") }),
        SecretShape("xoxp-", minimum: 10, allowed: { alnum($0) || $0 == UInt8(ascii: "-") }),
        SecretShape("xoxr-", minimum: 10, allowed: { alnum($0) || $0 == UInt8(ascii: "-") }),
        SecretShape("AIza", minimum: 35, allowed: alnumDash),
    ]

    static func looksLikeKnownSecret(_ value: String) -> Bool {
        if value.contains("-----BEGIN "), value.contains("PRIVATE KEY-----") { return true }
        let bytes = Array(value.utf8)
        return secretShapes.contains { $0.matches(bytes) }
    }

    /// Values that stand in for a secret: empty, `<token>`, `YOUR_API_KEY`, `xxxxxxxx`, `••••••••`, `EXAMPLE`.
    static func isSecretPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") { return true }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("YOUR_") || upper.hasPrefix("YOUR-") || upper.contains("EXAMPLE") || upper.contains("PLACEHOLDER") {
            return true
        }
        return trimmed.allSatisfy { "xX*•".contains($0) }
    }

    /// The name a literal is assigned to: `let apiToken = "…"`, `self.password = "…"`,
    /// `login(password: "…")`, `func f(token: String = "…")`.
    private static func assignedName(of literal: StringLiteralExprSyntax) -> String? {
        guard let parent = literal.parent else { return nil }
        if let initializer = parent.as(InitializerClauseSyntax.self) {
            if let binding = initializer.parent?.as(PatternBindingSyntax.self) {
                return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
            }
            if let parameter = initializer.parent?.as(FunctionParameterSyntax.self) {
                return (parameter.secondName ?? parameter.firstName).text
            }
            return nil
        }
        if let argument = parent.as(LabeledExprSyntax.self) { return argument.label?.text }
        if let sequence = parent.as(ExprListSyntax.self), sequence.parent?.is(SequenceExprSyntax.self) == true {
            let elements = Array(sequence)
            guard elements.count == 3, elements[2].id == literal.id, elements[1].is(AssignmentExprSyntax.self) else { return nil }
            return SyntaxHelpers.nameComponents(elements[0]).last
        }
        return nil
    }

    public static let hardcodedSecret = Rule(
        id: "hardcoded-secret",
        severity: .warning,
        message: "Hardcoded secret in source; load it from the Keychain, the environment or a build setting",
        description: "Flags string literals shaped like API keys and private keys (AWS, GitHub, Anthropic, OpenAI, Slack, "
            + "Google) and literals of 8+ characters assigned to a secret-named variable, property or argument.",
        kinds: [.stringLiteralExpr],
        examples: RuleExamples(
            triggering: [
                #"let id = ↓"AKIAIOSFODNN7ABCDEFG""#, // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
                #"let key = ↓"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789""#, // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
                #"let key = ↓"sk-ant-api03-aBcDeFgHiJkLmNoPqRsT""#, // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
                #"let key = ↓"xoxb-1234567890-abcdefghij""#, // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
                #"let key = ↓"AIzaSyA1B2C3D4E5F6G7H8I9J0K1L2M3N4O5P6Q""#, // swiftcheck:ignore hardcoded-secret — fake key used as a test fixture
                #"let apiToken = ↓"a8f3b2c1d4e5""#,
                #"config.password = ↓"hunter2hunter2""#,
                #"login(secret: ↓"s3cr3t-value")"#,
                #"func connect(token: String = ↓"a8f3b2c1d4e5") { }"#,
                "#if DEBUG\nlet apiToken = ↓\"a8f3b2c1d4e5\"\n#endif",
            ],
            nonTriggering: [
                #"let apiToken = """#,
                #"let apiToken = "<your token>""#,
                #"let apiToken = "YOUR_API_TOKEN""#,
                #"let password = "xxxxxxxx""#,
                #"let password = "••••••••""#,
                #"defaults.set(value, forKey: "token")"#,
                #"let tokenKey = "auth_token_value""#,
                #"let password = "short""#,
                #"let passwordHint = "Use at least eight characters""#,
                #"let token = "\(prefix)-abcdefgh""#,
                #"let tokenURL = "https://example.org/oauth/token""#,
                #"let key = "AKIAIOSFODNN7EXAMPLE""#,
                #"let title = "Enter your password here""#,
                #"let apiToken = "Bearer abcdefgh""#,
            ]
        ),
        check: { node, _ in
            guard let literal = node.as(StringLiteralExprSyntax.self),
                  let value = SyntaxHelpers.stringValue(ExprSyntax(literal)), value.count >= 8,
                  !isSecretPlaceholder(value) else { return [] }
            if looksLikeKnownSecret(value) { return [Finding(at: literal)] }
            // Free text and URLs are not credentials.
            guard !value.contains(where: \.isWhitespace), !value.contains("://"),
                  let name = assignedName(of: literal), SensitiveName.isSensitiveIdentifier(name) else { return [] }
            return [Finding(at: literal)]
        }
    )
}
