//
//  BlockingInAsyncRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let blockingInAsync = Rule(
        id: "blocking-in-async",
        severity: .warning,
        message: "Blocking call in an async context stalls a cooperative thread; use `Task.sleep` or `await`",
        description: "Flags Thread.sleep, sleep, usleep and semaphore / dispatch group wait() inside async functions "
            + "and Task closures.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                "func load() async { Thread.↓sleep(forTimeInterval: 1) }",
                "func load() async { ↓sleep(1) }",
                "func load() async { ↓usleep(1000) }",
                "func load() async { semaphore.↓wait() }",
                "func load() async { dispatchGroup.↓wait() }",
                "Task { Thread.↓sleep(forTimeInterval: 1) }",
                "Task.detached { group.↓wait(timeout: .now()) }",
                "#if DEBUG\nfunc load() async { ↓sleep(1) }\n#endif",
            ],
            nonTriggering: [
                "func load() { Thread.sleep(forTimeInterval: 1) }",
                "func load() { semaphore.wait() }",
                "func load() async throws { try await Task.sleep(for: .seconds(1)) }",
                "func load() async { DispatchQueue.global().async { sleep(1) } }",
                "func load() async { func inner() { sleep(1) }; inner() }",
                "func load() async { condition.wait() }",
                "func load() async { await group.waitForAll() }",
            ]
        ),
        check: { node, context in
            guard context.inAsync, let call = node.as(FunctionCallExprSyntax.self) else { return [] }
            if let name = SyntaxHelpers.freeFunctionName(call) {
                return name == "sleep" || name == "usleep" ? [Finding(at: call.calledExpression)] : []
            }
            guard let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base else { return [] }
            let components = SyntaxHelpers.nameComponents(base)
            switch member.declName.baseName.text {
            case "sleep" where components.last == "Thread":
                return [Finding(at: member.declName)]
            case "wait":
                let receiver = components.last?.lowercased() ?? ""
                return receiver.contains("semaphore") || receiver.contains("group") ? [Finding(at: member.declName)] : []
            default:
                return []
            }
        }
    )
}
