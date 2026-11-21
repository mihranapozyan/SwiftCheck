//
//  Glob.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// Minimal path globbing for include / exclude patterns.
///
/// - `*` matches within a path component, `?` matches one character, `**` matches any number
///   of components.
/// - A pattern matches a path if it matches the whole path or any of its parent directories,
///   so `Pods` and `**/Generated` exclude everything below those folders.
public enum Glob {
    public static func matches(_ pattern: String, path: String) -> Bool {
        var trimmed = Substring(pattern)
        while trimmed.hasPrefix("./") { trimmed = trimmed.dropFirst(2) }
        while trimmed.hasSuffix("/") { trimmed = trimmed.dropLast() }
        let p = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        let s = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !p.isEmpty else { return false }
        for end in stride(from: s.count, through: 1, by: -1) where match(p[...], s[..<end]) {
            return true
        }
        return false
    }

    private static func match(_ p: ArraySlice<Substring>, _ s: ArraySlice<Substring>) -> Bool {
        guard let head = p.first else { return s.isEmpty }
        if head == "**" {
            var rest = s
            while true {
                if match(p.dropFirst(), rest) { return true }
                guard !rest.isEmpty else { return false }
                rest = rest.dropFirst()
            }
        }
        guard let component = s.first, wildcard(Array(head), Array(component)) else { return false }
        return match(p.dropFirst(), s.dropFirst())
    }

    private static func wildcard(_ p: [Character], _ s: [Character]) -> Bool {
        var pi = 0, si = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1; si += 1
            } else if pi < p.count, p[pi] == "*" {
                star = pi; mark = si; pi += 1
            } else if star >= 0 {
                pi = star + 1; mark += 1; si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
