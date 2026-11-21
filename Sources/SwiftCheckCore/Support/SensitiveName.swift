//
//  SensitiveName.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// Heuristics for names that hold secret values (tokens, passwords, PIN codes…).
public enum SensitiveName {
    static let secretWords: Set<String> = ["token", "password", "passcode", "pin", "otp", "cvv", "secret"]

    /// Leading words that make a name a Bool flag rather than a value: `isTokenValid`, `hasPin`.
    static let flagPrefixes: Set<String> = [
        "is", "has", "have", "had", "should", "shows", "show", "can", "did", "will", "was", "were",
        "needs", "must", "allows", "uses", "supports", "requires",
    ]

    /// Trailing words that describe metadata about a secret, not the secret itself:
    /// `tokenCount`, `passwordField`, `pinEnabled`.
    static let metadataSuffixes: Set<String> = [
        "count", "length", "size", "enabled", "disabled", "required", "visible", "hidden", "valid",
        "invalid", "expired", "expiration", "expiry", "date", "error", "label", "title", "placeholder",
        "hint", "field", "button", "view", "key", "type", "kind", "style",
    ]

    /// A Swift identifier: lower-camel only (types and UPPER_CASE constants are skipped).
    public static func isSensitiveIdentifier(_ raw: String) -> Bool {
        var name = Substring(raw)
        if name.hasPrefix("`"), name.hasSuffix("`"), name.count > 2 { name = name.dropFirst().dropLast() }
        name = name.drop(while: { $0 == "_" || $0 == "$" })
        guard let first = name.first, first.isLetter, first.isLowercase else { return false }
        return isSensitive(words: words(in: name))
    }

    /// A storage key such as `"auth_token"` or `"userPassword"`; any letter case is accepted.
    public static func isSensitiveKey(_ key: String) -> Bool {
        isSensitive(words: words(in: Substring(key)))
    }

    static func isSensitive(words: [String]) -> Bool {
        guard let first = words.first, let last = words.last else { return false }
        if flagPrefixes.contains(first), words.count > 1 { return false }
        if metadataSuffixes.contains(last), words.count > 1 { return false }
        return words.contains { word in
            secretWords.contains(word) || (word.hasSuffix("s") && secretWords.contains(String(word.dropLast())))
        }
    }

    /// Splits `accessTokenURL`, `auth_token`, `PIN-code` into lowercase words.
    static func words(in name: Substring) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(name)
        for (i, ch) in chars.enumerated() {
            guard ch.isLetter || ch.isNumber else {
                if !current.isEmpty { result.append(current); current = "" }
                continue
            }
            if ch.isUppercase, !current.isEmpty {
                let prev = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if prev.isLowercase || prev.isNumber || (prev.isUppercase && nextIsLower) {
                    result.append(current)
                    current = ""
                }
            }
            current.append(ch)
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.lowercased() }
    }
}
