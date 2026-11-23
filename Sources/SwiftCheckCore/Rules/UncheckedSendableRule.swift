//
//  UncheckedSendableRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let uncheckedSendable = Rule(
        id: "unchecked-sendable",
        severity: .warning,
        message: "Opting out of Sendable checking hides data races; make the type genuinely Sendable if possible",
        description: "Flags @unchecked Sendable conformances and nonisolated(unsafe). Opt-in.",
        kinds: [.attributedType, .declModifier],
        examples: RuleExamples(
            triggering: [
                "final class Cache: ↓@unchecked Sendable { }",
                "extension Cache: ↓@unchecked Sendable { }",
                "↓nonisolated(unsafe) var shared = Cache()",
                "struct S: Equatable, ↓@unchecked Sendable { }",
            ],
            nonTriggering: [
                "struct S: Sendable { }",
                "final class Cache: Sendable { }",
                "nonisolated let value = 1",
                "@MainActor final class Model { }",
                "func f(_ g: @escaping @Sendable () -> Void) { }",
            ]
        ),
        isOptIn: true,
        check: { node, _ in
            if let modifier = node.as(DeclModifierSyntax.self) {
                guard modifier.name.text == "nonisolated", modifier.detail?.detail.text == "unsafe" else { return [] }
                return [Finding(at: modifier)]
            }
            guard let type = node.as(AttributedTypeSyntax.self),
                  type.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Sendable",
                  SyntaxHelpers.hasAttribute(type.attributes, named: "unchecked") else { return [] }
            return [Finding(at: type)]
        }
    )
}
