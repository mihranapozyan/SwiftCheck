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
        let dispatcher = RuleDispatcher(ruleSet: ruleSet, collectIgnores: contains(bytes, Suppression.markerBytes))
        dispatcher.walk(tree)
        guard !dispatcher.hits.isEmpty else { return [] }

        let converter = SourceLocationConverter(fileName: path, tree: tree)
        var ignored: [Int: Set<String>] = [:]
        for (position, ids) in dispatcher.ignores {
            ignored[converter.location(for: position).line, default: []].formUnion(ids)
        }

        var violations: [Violation] = []
        violations.reserveCapacity(dispatcher.hits.count)
        var seen: Set<[Int]> = []
        for hit in dispatcher.hits {
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

    private let ruleSet: RuleSet
    private let collectIgnores: Bool
    private var context = RuleContext()
    private var saved: [(id: SyntaxIdentifier, context: RuleContext)] = []
    private(set) var hits: [Hit] = []
    /// Start position of the token whose line an ignore comment applies to.
    private(set) var ignores: [(AbsolutePosition, Set<String>)] = []

    init(ruleSet: RuleSet, collectIgnores: Bool) {
        self.ruleSet = ruleSet
        self.collectIgnores = collectIgnores
        super.init(viewMode: .sourceAccurate)
    }

    override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
        switch node.kind {
        case .token:
            if collectIgnores, let token = node.as(TokenSyntax.self) { scanIgnores(token) }
            return .skipChildren
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

    private func scanIgnores(_ token: TokenSyntax) {
        for trivia in [token.leadingTrivia, token.trailingTrivia] {
            for piece in trivia {
                guard case .lineComment(let text) = piece,
                      let ids = Suppression.ruleIDs(inComment: text), !ids.isEmpty else { continue }
                // Trailing comments belong to the token's line; leading comments on their
                // own line belong to the following token's line. Both are the token's line.
                ignores.append((token.positionAfterSkippingLeadingTrivia, ids))
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
