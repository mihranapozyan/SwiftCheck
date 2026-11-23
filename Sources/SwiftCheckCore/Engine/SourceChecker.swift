//
//  SourceChecker.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import SwiftParser
import SwiftSyntax

/// Checks a single file: parses it, walks the tree once and resolves findings to violations.
public enum SourceChecker {
    public static func check(source: String, path: String, ruleSet: RuleSet) -> [Violation] {
        check(bytes: Array(source.utf8), path: path, ruleSet: ruleSet)
    }

    public static func check(bytes: [UInt8], path: String, ruleSet: RuleSet) -> [Violation] {
        guard !ruleSet.rules.isEmpty else { return [] }
        let tree = bytes.withUnsafeBufferPointer { Parser.parse(source: $0) }
        let dispatcher = RuleDispatcher(ruleSet: ruleSet, fileName: fileName(of: path),
                                        collectIgnores: contains(bytes, Suppression.markerBytes))
        dispatcher.walk(tree)
        var hits = dispatcher.hits
        if !ruleSet.sourceRules.isEmpty {
            let text = SourceText(bytes: bytes)
            for index in ruleSet.sourceRules {
                guard let check = ruleSet.rules[index].rule.sourceCheck else { continue }
                for finding in check(text) { hits.append(RuleDispatcher.Hit(ruleIndex: index, finding: finding)) }
            }
        }
        guard !hits.isEmpty else { return [] }

        let converter = SourceLocationConverter(fileName: path, tree: tree)
        var ignored: [Int: Set<String>] = [:]
        for ignore in dispatcher.ignores {
            let line = converter.location(for: ignore.position).line
            ignored[line, default: []].formUnion(ignore.ids)
            if ignore.coversNextLine { ignored[line + 1, default: []].formUnion(ignore.ids) }
        }

        var violations: [Violation] = []
        violations.reserveCapacity(hits.count)
        var seen: Set<[Int]> = []
        for hit in hits {
            let configured = ruleSet.rules[hit.ruleIndex]
            let id = configured.rule.id
            let location = converter.location(for: hit.finding.position)
            if let ids = ignored[location.line], ids.contains(id) || ids.contains("all") { continue }
            guard seen.insert([hit.ruleIndex, hit.finding.position.utf8Offset]).inserted else { continue }
            violations.append(Violation(
                rule: id,
                severity: configured.severity,
                file: path,
                line: location.line,
                column: location.column,
                message: hit.finding.message ?? configured.rule.message,
                offset: hit.finding.position.utf8Offset,
                lineText: lineText(in: bytes, at: hit.finding.position.utf8Offset)
            ))
        }
        return violations.sorted()
    }

    static func fileName(of path: String) -> String {
        path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
    }

    static func lineText(in bytes: [UInt8], at offset: Int) -> String {
        let newline = UInt8(ascii: "\n")
        let clamped = min(max(offset, 0), bytes.count)
        var start = clamped
        while start > 0, bytes[start - 1] != newline { start -= 1 }
        var end = clamped
        while end < bytes.count, bytes[end] != newline { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func contains(_ haystack: [UInt8], _ needle: [UInt8]) -> Bool {
        haystack.withUnsafeBytes { h in
            needle.withUnsafeBytes { n in
                memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil
            }
        }
    }
}

/// The single-pass visitor: tracks context on a stack and dispatches nodes to rules by kind.
final class RuleDispatcher: SyntaxAnyVisitor {
    struct Hit {
        let ruleIndex: Int
        let finding: Finding
    }

    /// An `swiftcheck:ignore` comment: it applies to the line of `position`, and, for a comment on
    /// its own line, also to the line after it.
    struct Ignore {
        let position: AbsolutePosition
        let ids: Set<String>
        let coversNextLine: Bool
    }

    private let ruleSet: RuleSet
    private let collectIgnores: Bool
    /// Tokens (and their trivia) are visited only when a comment rule is active or ignores are needed.
    let scansTrivia: Bool
    private var context: RuleContext
    private var saved: [(id: SyntaxIdentifier, context: RuleContext)] = []
    private(set) var hits: [Hit] = []
    private(set) var ignores: [Ignore] = []

    init(ruleSet: RuleSet, fileName: String, collectIgnores: Bool) {
        self.ruleSet = ruleSet
        self.collectIgnores = collectIgnores
        self.scansTrivia = collectIgnores || !ruleSet.commentRules.isEmpty
        self.context = RuleContext(fileName: fileName)
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        switch node.kind {
        case .token:
            if scansTrivia, let token = node.as(TokenSyntax.self) { scanTrivia(token) }
            return .skipChildren
        case .functionDecl, .initializerDecl, .accessorDecl, .deinitializerDecl, .closureExpr:
            if let isAsync = AsyncContext.scope(of: node) {
                saved.append((node.id, context))
                context.inAsync = isAsync
            }
        case .macroExpansionDecl, .macroExpansionExpr, .structDecl, .classDecl, .enumDecl,
             .extensionDecl, .actorDecl:
            if PreviewDetector.isPreview(node) { return .skipChildren }
        case .ifConfigClause:
            if let clause = node.as(IfConfigClauseSyntax.self) {
                saved.append((node.id, context))
                if !context.inDebug, DebugCondition.clauseIsDebug(clause) { context.inDebug = true }
            }
        default:
            break
        }

        if let indices = ruleSet.table[node.kind] {
            for index in indices {
                for finding in ruleSet.rules[index].rule.check(node, context) {
                    hits.append(Hit(ruleIndex: index, finding: finding))
                }
            }
        }
        return .visitChildren
    }

    override func visitAnyPost(_ node: Syntax) {
        if let last = saved.last, last.id == node.id {
            context = last.context
            saved.removeLast()
        }
    }

    /// Walks the trivia of a token once, feeding ignore comments and comment rules.
    private func scanTrivia(_ token: TokenSyntax) {
        // Comments before `#if` belong to the code around the clause, not to the clause's own condition.
        var leadingContext = context
        if let clause = token.parent?.as(IfConfigClauseSyntax.self), clause.poundKeyword.id == token.id,
           let last = saved.last, last.id == clause.id {
            leadingContext = last.context
        }
        scan(token.leadingTrivia, from: token.position, token: token, isLeading: true, context: leadingContext)
        scan(token.trailingTrivia, from: token.endPositionBeforeTrailingTrivia, token: token, isLeading: false, context: context)
    }

    private func scan(_ trivia: Trivia, from start: AbsolutePosition, token: TokenSyntax, isLeading: Bool,
                      context: RuleContext) {
        var offset = start.utf8Offset
        for piece in trivia {
            defer { offset += piece.sourceLength.utf8Length }
            let comment: Comment
            switch piece {
            case .lineComment(let text): comment = Comment(kind: .line, text: text, position: AbsolutePosition(utf8Offset: offset))
            case .blockComment(let text): comment = Comment(kind: .block, text: text, position: AbsolutePosition(utf8Offset: offset))
            case .docLineComment(let text): comment = Comment(kind: .docLine, text: text, position: AbsolutePosition(utf8Offset: offset))
            case .docBlockComment(let text): comment = Comment(kind: .docBlock, text: text, position: AbsolutePosition(utf8Offset: offset))
            default: continue
            }
            if collectIgnores, comment.kind == .line,
               let ids = Suppression.ruleIDs(inComment: comment.text), !ids.isEmpty {
                // Trailing comments belong to the token's line; leading comments on their own line
                // belong to the following token's line, and to the line right below the comment.
                ignores.append(Ignore(position: token.positionAfterSkippingLeadingTrivia, ids: ids, coversNextLine: false))
                if isLeading { ignores.append(Ignore(position: comment.position, ids: ids, coversNextLine: true)) }
            }
            for index in ruleSet.commentRules {
                guard let check = ruleSet.rules[index].rule.commentCheck else { continue }
                for finding in check(comment, context) { hits.append(Hit(ruleIndex: index, finding: finding)) }
            }
        }
    }
}

enum PreviewDetector {
    static func isPreview(_ node: Syntax) -> Bool {
        if let macro = node.as(MacroExpansionDeclSyntax.self) { return macro.macroName.text == "Preview" }
        if let macro = node.as(MacroExpansionExprSyntax.self) { return macro.macroName.text == "Preview" }
        let inheritance: InheritanceClauseSyntax? =
            node.as(StructDeclSyntax.self)?.inheritanceClause
            ?? node.as(ClassDeclSyntax.self)?.inheritanceClause
            ?? node.as(EnumDeclSyntax.self)?.inheritanceClause
            ?? node.as(ExtensionDeclSyntax.self)?.inheritanceClause
            ?? node.as(ActorDeclSyntax.self)?.inheritanceClause
        guard let inheritance else { return false }
        return inheritance.inheritedTypes.contains { inherited in
            let name = inherited.type.as(IdentifierTypeSyntax.self)?.name.text
                ?? inherited.type.as(MemberTypeSyntax.self)?.name.text
            return name == "PreviewProvider"
        }
    }
}
