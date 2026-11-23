//
//  ConflictMarkerRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    private static func lineStarts(_ line: ArraySlice<UInt8>, with prefix: StaticString) -> Bool {
        let length = prefix.utf8CodeUnitCount
        guard line.count >= length else { return false }
        return prefix.withUTF8Buffer { buffer in
            zip(line.prefix(length), buffer).allSatisfy { $0 == $1 }
        }
    }

    public static let conflictMarker = Rule(
        id: "conflict-marker",
        severity: .error,
        message: "Unresolved merge conflict marker",
        description: "Flags lines starting with <<<<<<< , ||||||| or >>>>>>> and a ======= separator that follows "
            + "an opening marker. Works on the raw text, because a file with markers doesn't parse.",
        examples: RuleExamples(
            triggering: [
                "let a = 1\n↓<<<<<<< HEAD\nlet b = 2\n↓=======\nlet b = 3\n↓>>>>>>> feature\n",
                "↓<<<<<<< ours\n↓||||||| base\n↓=======\n↓>>>>>>> theirs",
                "func f() {}\n↓>>>>>>> stray",
            ],
            nonTriggering: [
                "let s = \"\"\"\n=======\n\"\"\"",
                "let a = 1 // <<<<<<< not at line start",
                "let line = \"=======\"",
                "// <<<<<<<\nlet a = 1",
                "let rule = \"\"\"\nTitle\n=======\nBody\n\"\"\"",
            ]
        ),
        source: { text in
            var findings: [Finding] = []
            var isOpen = false
            for index in 0..<text.lineCount {
                let line = text.lineBytes(index)
                let start = text.lineStarts[index]
                if lineStarts(line, with: "<<<<<<< ") {
                    isOpen = true
                    findings.append(Finding(AbsolutePosition(utf8Offset: start)))
                } else if lineStarts(line, with: "||||||| ") || lineStarts(line, with: ">>>>>>> ") {
                    if lineStarts(line, with: ">>>>>>> ") { isOpen = false }
                    findings.append(Finding(AbsolutePosition(utf8Offset: start)))
                } else if isOpen, line.count == 7, lineStarts(line, with: "=======") {
                    findings.append(Finding(AbsolutePosition(utf8Offset: start)))
                }
            }
            return findings
        }
    )
}
