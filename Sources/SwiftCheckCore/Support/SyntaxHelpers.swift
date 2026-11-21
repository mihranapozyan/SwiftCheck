//
//  SyntaxHelpers.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

/// Small syntax utilities shared by the built-in rules and useful for custom ones.
public enum SyntaxHelpers {
    /// Identifier components of a receiver chain: `self.network.logger` → `["self", "network", "logger"]`.
    public static func nameComponents(_ expr: ExprSyntax) -> [String] {
        if let ref = expr.as(DeclReferenceExprSyntax.self) { return [ref.baseName.text] }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return (member.base.map(nameComponents) ?? []) + [member.declName.baseName.text]
        }
        if let call = expr.as(FunctionCallExprSyntax.self) { return nameComponents(call.calledExpression) }
        if let unwrap = expr.as(ForceUnwrapExprSyntax.self) { return nameComponents(unwrap.expression) }
        if let chain = expr.as(OptionalChainingExprSyntax.self) { return nameComponents(chain.expression) }
        if let subscriptCall = expr.as(SubscriptCallExprSyntax.self) { return nameComponents(subscriptCall.calledExpression) }
        if expr.is(SuperExprSyntax.self) { return ["super"] }
        return []
    }

    /// The plain function name of a free-function call (`print(…)` → `print`, `Swift.print(…)` → `print`).
    public static func freeFunctionName(_ call: FunctionCallExprSyntax) -> String? {
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) { return ref.baseName.text }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self), base.baseName.text == "Swift" {
            return member.declName.baseName.text
        }
        return nil
    }

    /// A literal with no interpolation: `"text"`, `12`, `1.5`, `-3`.
    public static func isPlainLiteral(_ expr: ExprSyntax) -> Bool {
        if let string = expr.as(StringLiteralExprSyntax.self) {
            return string.segments.allSatisfy { $0.is(StringSegmentSyntax.self) }
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "-" {
            return isPlainLiteral(prefix.expression)
        }
        return expr.is(IntegerLiteralExprSyntax.self) || expr.is(FloatLiteralExprSyntax.self)
    }

    /// Content of a string literal without interpolation.
    public static func stringValue(_ expr: ExprSyntax) -> String? {
        guard let string = expr.as(StringLiteralExprSyntax.self) else { return nil }
        var value = ""
        for segment in string.segments {
            guard let text = segment.as(StringSegmentSyntax.self) else { return nil }
            value += text.content.text
        }
        return value
    }

    /// Identifier references inside `node` that look like secret values.
    /// Interpolations redacted with `privacy:` (anything but `.public`) are skipped.
    public static func sensitiveReferences(in node: some SyntaxProtocol) -> [DeclReferenceExprSyntax] {
        var result: [DeclReferenceExprSyntax] = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            guard case .identifier = token.tokenKind,
                  let ref = token.parent?.as(DeclReferenceExprSyntax.self), ref.baseName.id == token.id,
                  SensitiveName.isSensitiveIdentifier(token.text),
                  !isRedacted(ref, within: Syntax(node)) else { continue }
            result.append(ref)
        }
        return result
    }

    private static func isRedacted(_ ref: DeclReferenceExprSyntax, within root: Syntax) -> Bool {
        var current = ref.parent
        while let node = current, node.id != root.id {
            if let segment = node.as(ExpressionSegmentSyntax.self) {
                return segment.expressions.contains { argument in
                    guard argument.label?.text == "privacy" else { return false }
                    let value = argument.expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
                        ?? argument.expression.as(FunctionCallExprSyntax.self)
                            .flatMap { $0.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text }
                    return value != "public"
                }
            }
            current = node.parent
        }
        return false
    }

    public static func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == name
        }
    }
}
