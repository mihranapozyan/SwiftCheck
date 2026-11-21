//
//  Suppression.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// Parses `// swiftcheck:ignore <rule>[, <rule>] — reason` comments.
///
/// The comment applies to the line it is on, or — when it stands on its own line —
/// to the next line of code. `all` suppresses every rule.
public enum Suppression {
    public static let marker = "swiftcheck:ignore"
    static let markerBytes = Array(marker.utf8)

    /// Returns the rule ids listed in a line comment, or `nil` if it isn't an ignore comment.
    public static func ruleIDs(inComment text: String) -> Set<String>? {
        var body = Substring(text)
        guard body.hasPrefix("//") else { return nil }
        body = body.drop(while: { $0 == "/" }).drop(while: \.isWhitespace)
        guard body.hasPrefix(marker) else { return nil }
        body = body.dropFirst(marker.count)

        var ids: Set<String> = []
        let words = body.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        for word in words {
            guard isRuleID(word) else { break } // reason separator or free text
            ids.insert(String(word))
        }
        return ids
    }

    private static func isRuleID(_ word: Substring) -> Bool {
        guard let first = word.first, first.isLetter, first.isLowercase else { return false }
        return word.allSatisfy { ($0.isLetter && $0.isLowercase) || $0.isNumber || $0 == "-" }
    }
}
