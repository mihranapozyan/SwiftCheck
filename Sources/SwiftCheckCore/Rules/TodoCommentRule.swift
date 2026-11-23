//
//  TodoCommentRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let todoComment = Rule(
        id: "todo-comment",
        severity: .warning,
        message: "Unresolved TODO / HACK marker",
        description: "Flags TODO and HACK markers in comments, Xcode style: right after the comment opener, then an optional (owner) and a colon. Opt-in: enable it to keep a clean tree before a release.",
        examples: RuleExamples(
            triggering: [
                "// ↓TODO: write tests\nlet a = 1",
                "let a = 1 // ↓HACK(anna): workaround",
                "/* ↓TODO: later */ let a = 1",
                "/// ↓TODO: document\nfunc f() {}",
                "/*\n * ↓TODO: second line\n */\nlet a = 1",
                "//↓TODO:tight",
            ],
            nonTriggering: [
                "// TODOS: not a marker\nlet a = 1",
                "// todo: lower case",
                "// MYHACK: part of a word",
                "let message = \"TODO: in a string\"",
                "// HACKER News",
                "// User settings of the TODO tab",
                "// TODO without a colon",
                "// MARK: - TODO list",
                "// See TODO: below",
            ]
        ),
        isOptIn: true,
        comments: { comment, _ in MarkerMatcher.todo.findings(in: comment) }
    )
}
