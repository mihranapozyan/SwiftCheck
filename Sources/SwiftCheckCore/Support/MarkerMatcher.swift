//
//  MarkerMatcher.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

/// Finds marker words such as `FIXME` in comment text, Xcode style. Shared by `fixme-comment` and
/// `todo-comment` so both treat the syntax identically.
///
/// A marker counts only when, on a comment line, it comes right after the comment opener and optional
/// whitespace, and is followed by an optional `(owner)` and then `:`. Openers are `//`, `///`, `//!`,
/// `#`, `/*`, `/**`, `*` (a continuation line of a block comment), `--`, `<!--` and `;`. Block comments
/// are processed line by line. Matching is case-sensitive; `// TODO: x`, `// TODO(anna): x`,
/// ` * FIXME: x` and `//TODO:x` match, `// TODO x`, `// todo: x` and `// See FIXME: below` do not.
/// At most one marker per line is reported.
public struct MarkerMatcher: Sendable {
    public struct Match: Sendable, Equatable {
        public let tag: String
        /// UTF-8 offset of the marker inside the examined text.
        public let offset: Int
    }

    public static let fixme = MarkerMatcher(tags: ["FIXME", "XXX"])
    public static let todo = MarkerMatcher(tags: ["TODO", "HACK"])

    /// Longest first, so `///` wins over `//` and `/**` over `/*`.
    private static let openers: [[UInt8]] = ["<!--", "///", "//!", "/**", "//", "/*", "--", "*", "#", ";"]
        .map { Array($0.utf8) }

    private let tags: [(name: String, bytes: [UInt8])]

    public init(tags: [String]) {
        self.tags = tags.map { ($0, Array($0.utf8)) }
    }

    public func matches(in text: String) -> [Match] {
        let bytes = Array(text.utf8)
        var result: [Match] = []
        var lineStart = 0
        while lineStart <= bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count, bytes[lineEnd] != 0x0A { lineEnd += 1 }
            if let match = match(in: bytes, from: lineStart, to: lineEnd) { result.append(match) }
            lineStart = lineEnd + 1
        }
        return result
    }

    private func match(in bytes: [UInt8], from start: Int, to end: Int) -> Match? {
        var index = MarkerMatcher.skipBlanks(bytes, start, end)
        guard let opener = MarkerMatcher.openers.first(where: { opener in
            index + opener.count <= end && bytes[index..<index + opener.count].elementsEqual(opener)
        }) else { return nil }
        index = MarkerMatcher.skipBlanks(bytes, index + opener.count, end)
        for tag in tags {
            let tagEnd = index + tag.bytes.count
            guard tagEnd <= end, bytes[index..<tagEnd].elementsEqual(tag.bytes) else { continue }
            var cursor = tagEnd
            if cursor < end, bytes[cursor] == UInt8(ascii: "(") {
                while cursor < end, bytes[cursor] != UInt8(ascii: ")") { cursor += 1 }
                guard cursor < end else { continue }
                cursor += 1
            }
            if cursor < end, bytes[cursor] == UInt8(ascii: ":") { return Match(tag: tag.name, offset: index) }
        }
        return nil
    }

    private static func skipBlanks(_ bytes: [UInt8], _ from: Int, _ end: Int) -> Int {
        var index = from
        while index < end, bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0D { index += 1 }
        return index
    }

    /// Findings for every marker in `comment`, positioned at the marker itself.
    func findings(in comment: Comment) -> [Finding] {
        matches(in: comment.text).map { match in
            Finding(AbsolutePosition(utf8Offset: comment.position.utf8Offset + match.offset),
                    message: "Unresolved `\(match.tag)` marker")
        }
    }
}
