//
//  Finding.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

/// A raw hit produced by a rule: a position in the file and an optional message
/// that overrides the rule's default one.
public struct Finding: Sendable, Equatable {
    public let position: AbsolutePosition
    public let message: String?

    public init(_ position: AbsolutePosition, message: String? = nil) {
        self.position = position
        self.message = message
    }

    public init(at node: some SyntaxProtocol, message: String? = nil) {
        self.init(node.positionAfterSkippingLeadingTrivia, message: message)
    }
}

/// A finding resolved to a file location with an effective severity.
public struct Violation: Sendable, Equatable, Hashable {
    public let rule: String
    public var severity: Severity
    /// Path relative to the project root (absolute if the file is outside of it).
    public let file: String
    public let line: Int
    public let column: Int
    public let message: String
    /// UTF-8 offset of the violation inside the file.
    public let offset: Int
    /// Whitespace-trimmed text of the source line, used for baseline keys.
    public let lineText: String
    /// `true` when the violation is covered by the baseline.
    public var baselined: Bool

    public init(
        rule: String,
        severity: Severity,
        file: String,
        line: Int,
        column: Int,
        message: String,
        offset: Int,
        lineText: String,
        baselined: Bool = false
    ) {
        self.rule = rule
        self.severity = severity
        self.file = file
        self.line = line
        self.column = column
        self.message = message
        self.offset = offset
        self.lineText = lineText
        self.baselined = baselined
    }
}

extension Violation: Comparable {
    public static func < (lhs: Violation, rhs: Violation) -> Bool {
        (lhs.file, lhs.line, lhs.column, lhs.rule) < (rhs.file, rhs.line, rhs.column, rhs.rule)
    }
}
