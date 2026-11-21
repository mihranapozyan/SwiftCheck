//
//  ForceTryRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    public static let forceTry = Rule(
        id: "force-try",
        severity: .error,
        message: "Force try; use `do`/`catch` or `try?`",
        description: "Flags `try!`.",
        kinds: [.tryExpr],
        examples: RuleExamples(
            triggering: [
                "let data = ↓try! Data(contentsOf: url)",
                "func load() { let model = ↓try! decoder.decode(Model.self, from: data) }",
            ],
            nonTriggering: [
                "let data = try? Data(contentsOf: url)",
                "let data = try Data(contentsOf: url)",
            ]
        ),
        check: { node, _ in
            guard let expr = node.as(TryExprSyntax.self),
                  expr.questionOrExclamationMark?.tokenKind == .exclamationMark else { return [] }
            return [Finding(at: expr.tryKeyword)]
        }
    )
}
