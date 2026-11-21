//
//  ForceCastRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    public static let forceCast = Rule(
        id: "force-cast",
        severity: .warning,
        message: "Force cast; use `as?` and handle the failure",
        description: "Flags `as!`.",
        kinds: [.asExpr, .unresolvedAsExpr],
        examples: RuleExamples(
            triggering: [
                "let cell = view ↓as! CustomCell",
                "let total = (value ↓as! Int) + 1",
                "configure(item ↓as! Model)",
            ],
            nonTriggering: [
                "let cell = view as? CustomCell",
                "let number = value as Int",
                "if let cell = view as? CustomCell { }",
            ]
        ),
        check: { node, _ in
            let pair: (TokenSyntax, TokenSyntax?)? =
                node.as(AsExprSyntax.self).map { ($0.asKeyword, $0.questionOrExclamationMark) }
                ?? node.as(UnresolvedAsExprSyntax.self).map { ($0.asKeyword, $0.questionOrExclamationMark) }
            guard let (keyword, mark) = pair, mark?.tokenKind == .exclamationMark else { return [] }
            return [Finding(at: keyword)]
        }
    )
}
