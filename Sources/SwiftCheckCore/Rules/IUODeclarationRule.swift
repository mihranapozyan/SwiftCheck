//
//  IUODeclarationRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    public static let iuoDeclaration = Rule(
        id: "iuo-declaration",
        severity: .warning,
        message: "Implicitly unwrapped optional; declare as `T?` or initialize the value",
        description: "Flags `T!` in declarations. `@IBOutlet` properties are allowed.",
        kinds: [.implicitlyUnwrappedOptionalType],
        examples: RuleExamples(
            triggering: [
                "var name: String↓!",
                "let value: Int↓! = 0",
                "func configure(with model: Model↓!) { }",
                "func make() -> View↓! { nil }",
                "class A { private var service: Service↓! }",
            ],
            nonTriggering: [
                "@IBOutlet weak var label: UILabel!",
                "@IBOutlet private var views: [UIView]!",
                "class A { @IBOutlet var title: UILabel!, subtitle: UILabel! }",
                "var name: String?",
                "let name = user!",
            ]
        ),
        check: { node, _ in
            guard let type = node.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) else { return [] }
            var current = type.parent
            while let parent = current {
                if let variable = parent.as(VariableDeclSyntax.self) {
                    if SyntaxHelpers.hasAttribute(variable.attributes, named: "IBOutlet") { return [] }
                    break
                }
                if parent.is(DeclSyntax.self) || parent.is(CodeBlockItemSyntax.self) { break }
                current = parent.parent
            }
            return [Finding(at: type.exclamationMark)]
        }
    )
}
