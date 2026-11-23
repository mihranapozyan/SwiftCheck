//
//  MainSyncRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let mainSync = Rule(
        id: "main-sync",
        severity: .warning,
        message: "`DispatchQueue.main.sync` deadlocks when called on the main thread; use `async`",
        description: "Flags DispatchQueue.main.sync { } and DispatchQueue.main.sync(execute:).",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                "DispatchQueue.main.↓sync { update() }",
                "DispatchQueue.main.↓sync(execute: work)",
                "func f() { Dispatch.DispatchQueue.main.↓sync(flags: .barrier) { } }",
            ],
            nonTriggering: [
                "DispatchQueue.main.async { update() }",
                "DispatchQueue.global().sync { work() }",
                "queue.sync { work() }",
                "DispatchQueue(label: \"x\").sync { work() }",
                "DispatchQueue.main.asyncAfter(deadline: .now()) { }",
            ]
        ),
        check: { node, _ in
            guard let call = node.as(FunctionCallExprSyntax.self),
                  let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                  member.declName.baseName.text == "sync",
                  let base = member.base,
                  SyntaxHelpers.nameComponents(base).suffix(2) == ["DispatchQueue", "main"] else { return [] }
            return [Finding(at: member.declName)]
        }
    )
}
