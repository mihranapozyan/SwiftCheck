//
//  UnsafeBitCastRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    static let unsafeCastFunctions: Set<String> = ["unsafeBitCast", "unsafeDowncast"]

    public static let unsafeBitCastCall = Rule(
        id: "unsafe-bit-cast",
        severity: .warning,
        message: "`unsafeBitCast` / `unsafeDowncast` bypass type safety; use a checked cast or a proper conversion",
        description: "Flags unsafeBitCast and unsafeDowncast calls.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                "let n = ↓unsafeBitCast(value, to: Int.self)",
                "let view = ↓unsafeDowncast(object, to: MyView.self)",
                "let p = Swift.↓unsafeBitCast(ref, to: UnsafeRawPointer.self)",
            ],
            nonTriggering: [
                "let n = value as? Int",
                "let n = Int(bitPattern: pointer)",
                "let n = unsafeBitCastCount",
                "helper.unsafeBitCast(value)",
            ]
        ),
        check: { node, _ in
            guard let call = node.as(FunctionCallExprSyntax.self),
                  let name = SyntaxHelpers.freeFunctionName(call), unsafeCastFunctions.contains(name) else { return [] }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self) { return [Finding(at: member.declName)] }
            return [Finding(at: call.calledExpression)]
        }
    )
}
