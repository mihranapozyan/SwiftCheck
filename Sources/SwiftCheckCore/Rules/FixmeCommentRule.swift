//
//  FixmeCommentRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    public static let fixmeComment = Rule(
        id: "fixme-comment",
        severity: .warning,
        message: "Unresolved FIXME / XXX marker",
        description: "Flags FIXME and XXX markers in comments, Xcode style: right after the comment opener, then an optional (owner) and a colon.",
        examples: RuleExamples(
            triggering: [
                "// ↓FIXME: handle the error\nlet a = 1",
                "let a = 1 // ↓FIXME(anna): later",
                "/* ↓XXX: dangerous */ let a = 1",
                "/// ↓FIXME: document\nfunc f() {}",
                "/*\n * text\n * ↓FIXME: second line\n */\nlet a = 1",
                "//↓XXX:tight",
            ],
            nonTriggering: [
                "// FIXMEX: not a marker\nlet a = 1",
                "// fixme: lower case",
                "// MYXXX: part of a word",
                "let message = \"FIXME: in a string\"",
                "// XXX without a colon",
                "// FIXME. needs a colon",
                "// See FIXME: below",
                "// MARK: - FIXME list",
                "// Tracks the FIXME: in prose",
            ]
        ),
        comments: { comment, _ in MarkerMatcher.fixme.findings(in: comment) }
    )
}
