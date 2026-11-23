//
//  FatalErrorRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    static let fatalErrorFunctions: Set<String> = ["fatalError", "preconditionFailure"]

    /// `fatalError` is an accepted way to mark code that must not run: required `init(coder:)`,
    /// unavailable declarations, impossible `default:` branches.
    static func isFatalErrorAllowed(_ node: Syntax) -> Bool {
        var current = node.parent
        while let ancestor = current {
            if let initializer = ancestor.as(InitializerDeclSyntax.self),
               initializer.signature.parameterClause.parameters.first?.firstName.text == "coder" {
                return true
            }
            if let switchCase = ancestor.as(SwitchCaseSyntax.self), switchCase.label.is(SwitchDefaultLabelSyntax.self) {
                return true
            }
            if let decl = ancestor.asProtocol(WithAttributesSyntax.self), isUnavailable(decl.attributes) {
                return true
            }
            current = ancestor.parent
        }
        return false
    }

    /// `@available(*, unavailable…)`
    private static func isUnavailable(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "available" else { return false }
            let text = attribute.trimmedDescription
            return text.contains("*") && text.contains("unavailable")
        }
    }

    public static let fatalErrorCall = Rule(
        id: "fatal-error",
        severity: .warning,
        message: "`fatalError` / `preconditionFailure` crashes the app; handle the error or use `assertionFailure`",
        description: "Flags fatalError and preconditionFailure calls. Allowed in required init(coder:), "
            + "@available(*, unavailable) declarations, default: branches and #if DEBUG.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                #"func run() { ↓fatalError("unreachable") }"#,
                #"func run() { ↓preconditionFailure("bad state") }"#,
                "func load() throws {\n    guard ready else { ↓fatalError() }\n}",
                #"init(name: String) { ↓fatalError("no") }"#,
                "switch value {\ncase .a: ↓fatalError(\"a\")\ndefault: break\n}",
            ],
            nonTriggering: [
                #"required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }"#,
                #"required init(coder: NSCoder) { fatalError() }"#,
                #"@available(*, unavailable) func old() { fatalError("unavailable") }"#,
                "switch value {\ncase .a: break\ndefault: fatalError(\"unexpected\")\n}",
                "switch value {\ncase .a: break\n@unknown default: fatalError(\"new case\")\n}",
                #"precondition(isReady, "not ready"); assert(ok); assertionFailure("x")"#,
                "#if DEBUG\nfunc run() { fatalError(\"debug only\") }\n#endif",
                #"logger.fatalError("x")"#,
            ]
        ),
        check: { node, context in
            guard !context.inDebug,
                  let call = node.as(FunctionCallExprSyntax.self),
                  let name = SyntaxHelpers.freeFunctionName(call), fatalErrorFunctions.contains(name),
                  !isFatalErrorAllowed(node) else { return [] }
            return [Finding(at: call.calledExpression)]
        }
    )
}
