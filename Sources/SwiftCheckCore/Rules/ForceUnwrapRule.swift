//
//  ForceUnwrapRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    /// Initializers that only fail on invalid input, which is safe when the input is a literal.
    static let forceUnwrapAllowlist: [String: [[String]]] = [
        "URL": [["string"]],
        "UIImage": [["named"], ["systemName"]],
        "UIFont": [["name", "size"]],
    ]

    public static let forceUnwrap = Rule(
        id: "force-unwrap",
        severity: .warning,
        message: "Force unwrap; use `if let`, `guard let` or `??`",
        description: "Flags `value!`. Literal-only calls to URL(string:), UIImage(named:), "
            + "UIImage(systemName:) and UIFont(name:size:) are allowed.",
        kinds: [.forceUnwrapExpr],
        examples: RuleExamples(
            triggering: [
                "let value = optional↓!",
                "let name = user↓!.name",
                #"let first = dict["key"]↓!"#,
                "let url = URL(string: base + path)↓!",
                #"let url = URL(string: "https://\(host)")↓!"#,
                "let image = UIImage(named: name)↓!",
                #"let font = UIFont(name: "Menlo", size: size)↓!"#,
                #"let data = UIImage(named: "a")!.pngData()↓!"#,
            ],
            nonTriggering: [
                #"let url = URL(string: "https://example.com")!"#,
                #"let image = UIImage(named: "icon")!"#,
                #"let symbol = UIImage(systemName: "star.fill")!"#,
                #"let font = UIFont(name: "Menlo", size: 12)!"#,
                "let value = optional ?? 0",
                "if a != b { }",
                "#Preview { Text(model!.name) }",
                "struct Row_Previews: PreviewProvider { static var previews: some View { Text(model!.name) } }",
            ]
        ),
        check: { node, _ in
            guard let unwrap = node.as(ForceUnwrapExprSyntax.self) else { return [] }
            if let call = unwrap.expression.as(FunctionCallExprSyntax.self),
               let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
               let signatures = forceUnwrapAllowlist[callee.baseName.text],
               call.trailingClosure == nil {
                let labels = call.arguments.map { $0.label?.text ?? "_" }
                if signatures.contains(labels),
                   call.arguments.allSatisfy({ SyntaxHelpers.isPlainLiteral($0.expression) }) {
                    return []
                }
            }
            return [Finding(at: unwrap.exclamationMark)]
        }
    )
}
