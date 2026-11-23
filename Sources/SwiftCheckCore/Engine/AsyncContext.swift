//
//  AsyncContext.swift
//  SwiftCheck
//
//  Created by Mihran on 22.11.26.
//

import SwiftSyntax

/// Decides whether a node opens an asynchronous scope (see `RuleContext.inAsync`).
enum AsyncContext {
    /// `true` / `false` when `node` starts a new function-like scope that is / isn't asynchronous;
    /// `nil` when `node` doesn't change the scope.
    static func scope(of node: Syntax) -> Bool? {
        switch node.kind {
        case .functionDecl:
            return node.as(FunctionDeclSyntax.self)?.signature.effectSpecifiers?.asyncSpecifier != nil
        case .initializerDecl:
            return node.as(InitializerDeclSyntax.self)?.signature.effectSpecifiers?.asyncSpecifier != nil
        case .accessorDecl:
            return node.as(AccessorDeclSyntax.self)?.effectSpecifiers?.asyncSpecifier != nil
        case .deinitializerDecl:
            return false
        case .closureExpr:
            guard let closure = node.as(ClosureExprSyntax.self) else { return false }
            return closure.signature?.effectSpecifiers?.asyncSpecifier != nil || isTaskClosure(closure)
        default:
            return nil
        }
    }

    /// The closure is the body of `Task { }`, `Task(priority:) { }` or `Task.detached { }`
    /// (trailing closure or an argument).
    static func isTaskClosure(_ closure: ClosureExprSyntax) -> Bool {
        guard let parent = closure.parent else { return false }
        let call: FunctionCallExprSyntax?
        if let direct = parent.as(FunctionCallExprSyntax.self) {
            call = direct.trailingClosure?.id == closure.id ? direct : nil
        } else if let element = parent.as(MultipleTrailingClosureElementSyntax.self) {
            // Only the first closure is the body; labeled extras (`onCancel:`) are not.
            call = element.parent?.parent?.as(FunctionCallExprSyntax.self)
        } else if let argument = parent.as(LabeledExprSyntax.self) {
            call = argument.parent?.parent?.as(FunctionCallExprSyntax.self)
        } else {
            call = nil
        }
        guard let call else { return false }
        return isTaskInitializer(call.calledExpression)
    }

    private static func isTaskInitializer(_ expr: ExprSyntax) -> Bool {
        var expr = expr
        if let specialization = expr.as(GenericSpecializationExprSyntax.self) { expr = specialization.expression }
        if let ref = expr.as(DeclReferenceExprSyntax.self) { return ref.baseName.text == "Task" }
        guard let member = expr.as(MemberAccessExprSyntax.self) else { return false }
        var components = SyntaxHelpers.nameComponents(ExprSyntax(member))
        if components.first == "Swift" { components.removeFirst() }
        return components == ["Task", "detached"] || components == ["Task"]
    }
}
