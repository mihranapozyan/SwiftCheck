//
//  DebugCondition.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

/// Decides whether an `#if` / `#elseif` / `#else` clause is compiled only in debug builds.
///
/// A clause is "debug" when reaching it logically implies `DEBUG`:
/// `#if DEBUG`, `#if DEBUG && os(iOS)`, `#else` of `#if !DEBUG`, and so on.
enum DebugCondition {
    indirect enum Formula {
        case debug
        case unknown
        case not(Formula)
        case and(Formula, Formula)
        case or(Formula, Formula)
    }

    static func clauseIsDebug(_ clause: IfConfigClauseSyntax) -> Bool {
        if let condition = clause.condition, implies(formula(condition)) {
            return true
        }
        guard let list = clause.parent?.as(IfConfigClauseListSyntax.self) else { return false }
        for previous in list {
            if previous.id == clause.id { break }
            // Reaching this clause means `previous` was false.
            if let condition = previous.condition, impliedByNotDebug(formula(condition)) {
                return true
            }
        }
        return false
    }

    /// `f ⇒ DEBUG`
    static func implies(_ f: Formula) -> Bool {
        switch f {
        case .debug: true
        case .unknown: false
        case .not(let inner): impliedByNotDebug(inner)
        case .and(let a, let b): implies(a) || implies(b)
        case .or(let a, let b): implies(a) && implies(b)
        }
    }

    /// `¬DEBUG ⇒ f`
    static func impliedByNotDebug(_ f: Formula) -> Bool {
        switch f {
        case .debug, .unknown: false
        case .not(let inner): implies(inner)
        case .and(let a, let b): impliedByNotDebug(a) && impliedByNotDebug(b)
        case .or(let a, let b): impliedByNotDebug(a) || impliedByNotDebug(b)
        }
    }

    static func formula(_ expr: ExprSyntax) -> Formula {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text == "DEBUG" ? .debug : .unknown
        }
        if let prefix = expr.as(PrefixOperatorExprSyntax.self) {
            return prefix.operator.text == "!" ? .not(formula(prefix.expression)) : .unknown
        }
        if let tuple = expr.as(TupleExprSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first {
            return formula(only.expression)
        }
        if let infix = expr.as(InfixOperatorExprSyntax.self),
           let op = infix.operator.as(BinaryOperatorExprSyntax.self) {
            let lhs = formula(infix.leftOperand), rhs = formula(infix.rightOperand)
            switch op.operator.text {
            case "&&": return .and(lhs, rhs)
            case "||": return .or(lhs, rhs)
            default: return .unknown
            }
        }
        if let sequence = expr.as(SequenceExprSyntax.self) {
            return formula(sequence: Array(sequence.elements))
        }
        return .unknown
    }

    /// Unfolded `a && b || c`: `&&` binds tighter than `||`.
    private static func formula(sequence elements: [ExprSyntax]) -> Formula {
        var disjuncts: [Formula] = []
        var conjuncts: [Formula] = []
        var expectOperand = true
        for element in elements {
            if expectOperand {
                conjuncts.append(formula(element))
                expectOperand = false
                continue
            }
            guard let op = element.as(BinaryOperatorExprSyntax.self) else { return .unknown }
            switch op.operator.text {
            case "&&": break
            case "||":
                disjuncts.append(conjuncts.dropFirst().reduce(conjuncts[0]) { .and($0, $1) })
                conjuncts.removeAll()
            default: return .unknown
            }
            expectOperand = true
        }
        guard !conjuncts.isEmpty, !expectOperand else { return .unknown }
        disjuncts.append(conjuncts.dropFirst().reduce(conjuncts[0]) { .and($0, $1) })
        return disjuncts.dropFirst().reduce(disjuncts[0]) { .or($0, $1) }
    }
}
