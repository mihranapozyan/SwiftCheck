//
//  ExitCallRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let exitCall = Rule(
        id: "exit-call",
        severity: .warning,
        message: "`exit` / `abort` terminates the process abruptly; return an error or let the app quit normally",
        description: "Flags exit(…) and abort() calls. Allowed in main.swift.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                "func stop() { ↓exit(1) }",
                "func crash() { ↓abort() }",
                #"guard ok else { print("bad"); ↓exit(EXIT_FAILURE) }"#,
                "func stop() { Darwin.↓exit(0) }",
            ],
            nonTriggering: [
                "NSApplication.shared.terminate(nil)",
                "process.exit(1)",
                "let handler = exit",
                "func exit(_ code: Int) { }",
                "operation.abort(reason)",
                "abort(task)",
            ]
        ),
        check: { node, context in
            guard context.fileName != "main.swift", let call = node.as(FunctionCallExprSyntax.self) else { return [] }
            if let name = SyntaxHelpers.freeFunctionName(call) {
                // `exit(code)` takes one argument and `abort()` none, which tells them from same-named methods.
                guard (name == "exit" && call.arguments.count == 1) || (name == "abort" && call.arguments.isEmpty) else { return [] }
                return [Finding(at: call.calledExpression)]
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "Darwin",
               member.declName.baseName.text == "exit" || member.declName.baseName.text == "abort" {
                return [Finding(at: member.declName)]
            }
            return []
        }
    )
}
