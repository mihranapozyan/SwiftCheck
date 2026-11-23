//
//  EmptyCatchRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let emptyCatch = Rule(
        id: "empty-catch",
        severity: .warning,
        message: "Empty `catch` swallows the error; handle it, log it or explain with a comment",
        description: "Flags catch clauses with an empty body. A comment inside the body counts as an explanation.",
        kinds: [.catchClause],
        examples: RuleExamples(
            triggering: [
                "do { try save() } ↓catch { }",
                "do { try save() } ↓catch {}",
                "do { try save() } ↓catch let error as CocoaError { }",
                "do {\n    try save()\n} ↓catch {\n\n}",
            ],
            nonTriggering: [
                "do { try save() } catch { log(error) }",
                "do { try save() } catch { /* the file may not exist */ }",
                "do { try save() } catch {\n    // best effort\n}",
                "do { try save() } catch { _ = error }",
                "do { try save() } catch {\n    // best effort\n    return\n}",
            ]
        ),
        check: { node, _ in
            guard let clause = node.as(CatchClauseSyntax.self), clause.body.statements.isEmpty else { return [] }
            let hasComment = clause.body.leftBrace.trailingTrivia.contains { $0.isComment }
                || clause.body.rightBrace.leadingTrivia.contains { $0.isComment }
            return hasComment ? [] : [Finding(at: clause.catchKeyword)]
        }
    )
}
