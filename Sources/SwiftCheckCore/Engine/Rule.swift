//
//  Rule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

/// State of the traversal at the node being checked. Maintained by the engine on a stack.
public struct RuleContext: Sendable, Equatable {
    /// The node is inside an `#if DEBUG` branch (or an `#else` of `#if !DEBUG`, etc.).
    public var inDebug: Bool = false
    /// The node is inside `#Preview` or a `PreviewProvider` type.
    /// The engine does not dispatch such nodes, so rules normally never see `true`.
    public var inPreview: Bool = false

    public init(inDebug: Bool = false, inPreview: Bool = false) {
        self.inDebug = inDebug
        self.inPreview = inPreview
    }
}

/// Code samples documenting a rule. They double as the rule's test suite.
/// In `triggering` samples `↓` marks every position where a violation is expected.
public struct RuleExamples: Sendable {
    public let triggering: [String]
    public let nonTriggering: [String]

    public init(triggering: [String], nonTriggering: [String]) {
        self.triggering = triggering
        self.nonTriggering = nonTriggering
    }
}

/// A single check. Rules don't walk the tree themselves: the engine walks each file once
/// and hands every node whose kind is listed in `kinds` to `check`.
public struct Rule: Sendable, Identifiable {
    public typealias Check = @Sendable (Syntax, RuleContext) -> [Finding]

    public let id: String
    public let severity: Severity
    public let message: String
    public let description: String
    public let kinds: [SyntaxKind]
    public let examples: RuleExamples
    public let check: Check

    public init(
        id: String,
        severity: Severity,
        message: String,
        description: String,
        kinds: [SyntaxKind],
        examples: RuleExamples,
        check: @escaping Check
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.description = description
        self.kinds = kinds
        self.examples = examples
        self.check = check
    }
}

/// A rule with the severity chosen by the configuration.
public struct ConfiguredRule: Sendable {
    public let rule: Rule
    public let severity: Severity

    public init(_ rule: Rule, severity: Severity? = nil) {
        self.rule = rule
        self.severity = severity ?? rule.severity
    }
}

/// The set of active rules plus a dispatch table from syntax kind to rule indices.
public struct RuleSet: Sendable {
    public let rules: [ConfiguredRule]
    let table: [SyntaxKind: [Int]]

    public init(_ rules: [ConfiguredRule]) {
        self.rules = rules
        var table: [SyntaxKind: [Int]] = [:]
        for (index, configured) in rules.enumerated() {
            for kind in Set(configured.rule.kinds) {
                table[kind, default: []].append(index)
            }
        }
        self.table = table
    }

    public init(rules: [Rule]) {
        self.init(rules.map { ConfiguredRule($0) })
    }

    public var ids: Set<String> { Set(rules.map(\.rule.id)) }
}
