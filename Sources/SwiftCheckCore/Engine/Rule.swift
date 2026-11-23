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
    /// The node runs in an asynchronous context: the body of an `async` function, initializer or
    /// accessor, a closure passed to `Task { }` / `Task.detached { }`, or a closure with `async` in its
    /// signature. Any other closure, and any nested non-async function, resets the flag.
    public var inAsync: Bool = false
    /// Last path component of the file being checked (`main.swift`).
    public var fileName: String = ""

    public init(inDebug: Bool = false, inPreview: Bool = false, inAsync: Bool = false, fileName: String = "") {
        self.inDebug = inDebug
        self.inPreview = inPreview
        self.inAsync = inAsync
        self.fileName = fileName
    }
}

/// A comment found in the trivia of a token, handed to rules that subscribe with `comments:`.
public struct Comment: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// `// text`
        case line
        /// `/* text */`
        case block
        /// `/// text`
        case docLine
        /// `/** text */`
        case docBlock
    }

    public let kind: Kind
    /// The full comment text including its delimiters.
    public let text: String
    /// Position of the first character of the comment (the `/`).
    public let position: AbsolutePosition

    public init(kind: Kind, text: String, position: AbsolutePosition) {
        self.kind = kind
        self.text = text
        self.position = position
    }
}

/// The raw contents of a file, handed once per file to rules that subscribe with `source:`.
/// Unlike the syntax tree it stays reliable when the file doesn't parse (merge conflict markers).
public struct SourceText: Sendable {
    public let bytes: [UInt8]
    /// UTF-8 offset where each line starts; the first element is always `0`.
    public let lineStarts: [Int]

    public init(bytes: [UInt8]) {
        self.bytes = bytes
        var starts = [0]
        for (index, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") { starts.append(index + 1) }
        self.lineStarts = starts
    }

    public var lineCount: Int { lineStarts.count }

    /// Byte range of a line without its terminator (`\n` or `\r\n`).
    public func lineRange(_ index: Int) -> Range<Int> {
        let start = lineStarts[index]
        var end = index + 1 < lineStarts.count ? lineStarts[index + 1] - 1 : bytes.count
        if end > start, bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
        return start..<end
    }

    public func lineBytes(_ index: Int) -> ArraySlice<UInt8> { bytes[lineRange(index)] }

    public func line(_ index: Int) -> String { String(decoding: lineBytes(index), as: UTF8.self) }
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
///
/// A rule subscribes to exactly one source of input:
/// - syntax nodes (`kinds` + `check`);
/// - comments (`commentCheck`): every comment in the file, with its position;
/// - the raw source (`sourceCheck`): once per file, independent of the parser.
public struct Rule: Sendable, Identifiable {
    public typealias Check = @Sendable (Syntax, RuleContext) -> [Finding]
    public typealias CommentCheck = @Sendable (Comment, RuleContext) -> [Finding]
    public typealias SourceCheck = @Sendable (SourceText) -> [Finding]

    public let id: String
    public let severity: Severity
    public let message: String
    public let description: String
    public let kinds: [SyntaxKind]
    public let examples: RuleExamples
    public let check: Check
    /// Set for comment rules; such rules have no `kinds`.
    public let commentCheck: CommentCheck?
    /// Set for source rules; such rules have no `kinds`.
    public let sourceCheck: SourceCheck?
    /// An opt-in rule is off until the configuration enables it (`"id": "warning"`, `"error"`, `"on"`,
    /// or listing it in the array form of `rules`).
    public let isOptIn: Bool

    /// A syntax rule.
    public init(
        id: String,
        severity: Severity,
        message: String,
        description: String,
        kinds: [SyntaxKind],
        examples: RuleExamples,
        isOptIn: Bool = false,
        check: @escaping Check
    ) {
        self.init(id: id, severity: severity, message: message, description: description, kinds: kinds,
                  examples: examples, isOptIn: isOptIn, check: check, commentCheck: nil, sourceCheck: nil)
    }

    /// A comment rule: the engine walks tokens only when at least one comment rule is active.
    public init(
        id: String,
        severity: Severity,
        message: String,
        description: String,
        examples: RuleExamples,
        isOptIn: Bool = false,
        comments: @escaping CommentCheck
    ) {
        self.init(id: id, severity: severity, message: message, description: description, kinds: [],
                  examples: examples, isOptIn: isOptIn, check: { _, _ in [] }, commentCheck: comments, sourceCheck: nil)
    }

    /// A source rule: called once per file with the raw text.
    public init(
        id: String,
        severity: Severity,
        message: String,
        description: String,
        examples: RuleExamples,
        isOptIn: Bool = false,
        source: @escaping SourceCheck
    ) {
        self.init(id: id, severity: severity, message: message, description: description, kinds: [],
                  examples: examples, isOptIn: isOptIn, check: { _, _ in [] }, commentCheck: nil, sourceCheck: source)
    }

    private init(
        id: String, severity: Severity, message: String, description: String, kinds: [SyntaxKind],
        examples: RuleExamples, isOptIn: Bool, check: @escaping Check,
        commentCheck: CommentCheck?, sourceCheck: SourceCheck?
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.description = description
        self.kinds = kinds
        self.examples = examples
        self.isOptIn = isOptIn
        self.check = check
        self.commentCheck = commentCheck
        self.sourceCheck = sourceCheck
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
    /// Indices of rules subscribed to comments. Tokens are only visited when this is non-empty.
    let commentRules: [Int]
    /// Indices of rules subscribed to the raw source.
    let sourceRules: [Int]

    public init(_ rules: [ConfiguredRule]) {
        self.rules = rules
        var table: [SyntaxKind: [Int]] = [:]
        var commentRules: [Int] = []
        var sourceRules: [Int] = []
        for (index, configured) in rules.enumerated() {
            if configured.rule.commentCheck != nil { commentRules.append(index) }
            if configured.rule.sourceCheck != nil { sourceRules.append(index) }
            for kind in Set(configured.rule.kinds) {
                table[kind, default: []].append(index)
            }
        }
        self.table = table
        self.commentRules = commentRules
        self.sourceRules = sourceRules
    }

    public init(rules: [Rule]) {
        self.init(rules.map { ConfiguredRule($0) })
    }

    public var ids: Set<String> { Set(rules.map(\.rule.id)) }
}
