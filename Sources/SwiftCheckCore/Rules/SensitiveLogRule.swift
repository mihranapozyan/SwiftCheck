//
//  SensitiveLogRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    static let logFunctions: Set<String> = ["print", "debugPrint", "dump", "NSLog", "os_log"]

    /// `logger.info(…)`, `log.debug(…)`, `self.networkLogger.error(…)`, `Log.d(…)`.
    static func isLoggerReceiver(_ base: ExprSyntax) -> Bool {
        SyntaxHelpers.nameComponents(base).contains { name in
            let lower = name.lowercased()
            return lower == "logger" || lower == "log" || name.hasSuffix("Logger")
        }
    }

    public static let sensitiveLog = Rule(
        id: "sensitive-log",
        severity: .error,
        message: "Sensitive value is logged",
        description: "Flags values named token / password / passcode / pin / otp / cvv / secret passed to "
            + "print, NSLog, os_log or a logger. Interpolations with a non-public `privacy:` are allowed.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                #"print("token: \(↓token)")"#,
                #"logger.debug("password=\(user.↓password)")"#,
                #"NSLog("%@", ↓accessToken)"#,
                #"os_log("%{public}@", ↓otpCode)"#,
                #"networkLogger.info("\(↓pinCode)")"#,
                #"Log.d(↓clientSecret)"#,
                #"self.log.error("cvv \(↓cardCvv) \(↓passcode)")"#,
                #"logger.info("\(↓token, privacy: .public)")"#,
            ],
            nonTriggering: [
                #"print("token refreshed")"#,
                #"logger.info("\(isTokenValid)")"#,
                "print(hasPin)",
                "print(Token.self)",
                "print(TOKEN_KEY)",
                #"logger.info("\(token, privacy: .private)")"#,
                #"logger.info("\(token, privacy: .private(mask: .hash))")"#,
                "print(tokenizer)",
                "print(tokenCount)",
                "analytics.track(token)",
                "let value = log(token)",
            ]
        ),
        check: { node, _ in
            guard let call = node.as(FunctionCallExprSyntax.self) else { return [] }
            let isLogCall: Bool
            if let name = SyntaxHelpers.freeFunctionName(call) {
                isLogCall = logFunctions.contains(name)
            } else if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
                isLogCall = isLoggerReceiver(base)
            } else {
                isLogCall = false
            }
            guard isLogCall else { return [] }
            return SyntaxHelpers.sensitiveReferences(in: call.arguments).map { ref in
                Finding(at: ref, message: "Sensitive value `\(ref.baseName.text)` is logged")
            }
        }
    )
}
