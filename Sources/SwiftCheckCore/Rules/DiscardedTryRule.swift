//
//  DiscardedTryRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let discardedTry = Rule(
        id: "discarded-try",
        severity: .warning,
        message: "`try?` as a statement silently drops the error; use `do/catch` or log the failure",
        description: "Flags try? used as a standalone statement, where the result and the error are both thrown away. "
            + "Opt-in.",
        kinds: [.tryExpr],
        examples: RuleExamples(
            triggering: [
                "func f() { ↓try? save() }",
                "func f() async { ↓try? await load() }",
                "func f() { ↓try? FileManager.default.removeItem(at: url); done() }",
                "if ready { ↓try? save() }",
            ],
            nonTriggering: [
                "let value = try? load()",
                "_ = try? save()",
                "if let value = try? load() { use(value) }",
                "guard let value = try? load() else { return }",
                "use(try? load())",
                "func f() -> Int? { return try? load() }",
                "func f() -> Int? { try? load() }",
                "let g = { try? load() }",
                "try save()",
            ]
        ),
        isOptIn: true,
        check: { node, _ in
            guard let expr = node.as(TryExprSyntax.self), expr.questionOrExclamationMark?.tokenKind == .postfixQuestionMark,
                  let item = expr.parent?.as(CodeBlockItemSyntax.self),
                  let list = item.parent?.as(CodeBlockItemListSyntax.self) else { return [] }
            // A lone expression in a closure or in a function that returns a value is an implicit return.
            if list.count == 1, let parent = list.parent {
                if parent.is(ClosureExprSyntax.self) { return [] }
                let owner = parent.parent
                if let function = owner?.as(FunctionDeclSyntax.self), function.signature.returnClause != nil { return [] }
                if let accessor = owner?.as(AccessorDeclSyntax.self), accessor.accessorSpecifier.text == "get" { return [] }
            }
            return [Finding(at: expr)]
        }
    )
}
