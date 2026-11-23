//
//  UnownedReferenceRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let unownedReference = Rule(
        id: "unowned-reference",
        severity: .warning,
        message: "`unowned` crashes if the referenced object is gone; prefer `weak` unless the lifetime is guaranteed",
        description: "Flags unowned and unowned(unsafe) in declarations and closure capture lists. Opt-in.",
        kinds: [.declModifier, .closureCaptureSpecifier],
        examples: RuleExamples(
            triggering: [
                "final class A { ↓unowned let owner: Owner }",
                "final class A { ↓unowned(unsafe) var owner: Owner }",
                "let f = { [↓unowned self] in self.run() }",
                "let f = { [↓unowned(unsafe) self, weak other] in run() }",
            ],
            nonTriggering: [
                "final class A { weak var owner: Owner? }",
                "let f = { [weak self] in self?.run() }",
                "let f = { [self] in run() }",
                "final class A { let unownedName = 1 }",
            ]
        ),
        isOptIn: true,
        check: { node, _ in
            if let modifier = node.as(DeclModifierSyntax.self) {
                return modifier.name.text == "unowned" ? [Finding(at: modifier)] : []
            }
            if let specifier = node.as(ClosureCaptureSpecifierSyntax.self) {
                return specifier.specifier.text == "unowned" ? [Finding(at: specifier)] : []
            }
            return []
        }
    )
}
