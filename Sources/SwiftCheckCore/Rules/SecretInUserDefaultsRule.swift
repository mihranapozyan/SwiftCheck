//
//  SecretInUserDefaultsRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    static func isDefaultsReceiver(_ base: ExprSyntax) -> Bool {
        SyntaxHelpers.nameComponents(base).contains { name in
            name == "UserDefaults" || name.lowercased().hasSuffix("defaults")
        }
    }

    /// The key is sensitive: `"auth_token"`, `Keys.password`, `.pinCode`.
    static func isSensitiveKey(_ expr: ExprSyntax) -> Bool {
        if let key = SyntaxHelpers.stringValue(expr) { return SensitiveName.isSensitiveKey(key) }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return SensitiveName.isSensitiveIdentifier(member.declName.baseName.text)
        }
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return SensitiveName.isSensitiveIdentifier(ref.baseName.text)
        }
        return false
    }

    static let userDefaultsMessage = "Secret value stored in UserDefaults; use the Keychain"

    public static let secretInUserDefaults = Rule(
        id: "secret-in-userdefaults",
        severity: .error,
        message: userDefaultsMessage,
        description: "Flags writes of secret values to UserDefaults (set / setValue, @AppStorage). "
            + "Reads and removals are allowed.",
        kinds: [.functionCallExpr, .attribute],
        examples: RuleExamples(
            triggering: [
                #"UserDefaults.standard.↓set(token, forKey: "token")"#,
                #"defaults.↓set(value, forKey: "auth_token")"#,
                "userDefaults.↓setValue(user.password, forKey: Keys.password)",
                #"UserDefaults(suiteName: "group")?.↓set(pin, forKey: "pin")"#,
                #"↓@AppStorage("pinCode") var pinCode = """#,
                #"struct V { ↓@AppStorage("session") var sessionToken: String = "" }"#,
            ],
            nonTriggering: [
                #"let token = UserDefaults.standard.string(forKey: "token")"#,
                #"UserDefaults.standard.removeObject(forKey: "token")"#,
                #"defaults.set(true, forKey: "hasSeenPin")"#,
                #"UserDefaults.standard.set(theme, forKey: "theme")"#,
                #"keychain.set(token, forKey: "token")"#,
                #"request.setValue(token, forHTTPHeaderField: "Authorization")"#,
                #"@AppStorage("isPinEnabled") var isPinEnabled = false"#,
                #"@AppStorage("pinEnabled") var usesPin: Bool = false"#,
                #"@AppStorage("theme") var theme = "dark""#,
            ]
        ),
        check: { node, _ in
            if let call = node.as(FunctionCallExprSyntax.self) {
                guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                      ["set", "setValue"].contains(member.declName.baseName.text),
                      let base = member.base, isDefaultsReceiver(base),
                      let value = call.arguments.first(where: { $0.label == nil })?.expression,
                      !value.is(BooleanLiteralExprSyntax.self) else { return [] }
                let key = call.arguments.first(where: { $0.label?.text == "forKey" })?.expression
                let valueIsSecret = !SyntaxHelpers.sensitiveReferences(in: value).isEmpty
                guard valueIsSecret || key.map(isSensitiveKey) == true else { return [] }
                return [Finding(at: member.declName)]
            }

            guard let attribute = node.as(AttributeSyntax.self),
                  attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "AppStorage",
                  let variable = attribute.parent?.parent?.as(VariableDeclSyntax.self) else { return [] }
            for binding in variable.bindings {
                let isBool = binding.typeAnnotation?.type.as(IdentifierTypeSyntax.self)?.name.text == "Bool"
                    || binding.initializer?.value.is(BooleanLiteralExprSyntax.self) == true
                if isBool { return [] }
            }
            var secret = false
            if case .argumentList(let arguments) = attribute.arguments, let key = arguments.first?.expression {
                secret = isSensitiveKey(key)
            }
            secret = secret || variable.bindings.contains { binding in
                binding.pattern.as(IdentifierPatternSyntax.self)
                    .map { SensitiveName.isSensitiveIdentifier($0.identifier.text) } ?? false
            }
            return secret ? [Finding(at: attribute)] : []
        }
    )
}
