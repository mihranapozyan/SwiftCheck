//
//  Baseline.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Known violations that are tolerated: `{ "file|rule|trimmed line text": count }`.
///
/// Keys don't include line numbers, so moving code doesn't resurrect old violations.
/// Only occurrences beyond `count` for a key are reported.
public struct Baseline: Sendable, Equatable {
    public var counts: [String: Int]

    public init(counts: [String: Int] = [:]) {
        self.counts = counts
    }

    public init(violations: [Violation]) {
        self.counts = [:]
        for violation in violations { counts[Self.key(for: violation), default: 0] += 1 }
    }

    public static func key(for violation: Violation) -> String {
        "\(violation.file)|\(violation.rule)|\(violation.lineText)"
    }

    public static func load(from url: URL) throws -> Baseline {
        let data = try Data(contentsOf: url)
        return Baseline(counts: try JSONDecoder().decode([String: Int].self, from: data))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(counts).write(to: url, options: .atomic)
    }

    /// Marks the first `count` violations of each key (in file order) as baselined.
    public func apply(to violations: [Violation]) -> [Violation] {
        var remaining = counts
        return violations.sorted().map { violation in
            var violation = violation
            let key = Self.key(for: violation)
            if let left = remaining[key], left > 0 {
                remaining[key] = left - 1
                violation.baselined = true
            }
            return violation
        }
    }

    /// Replaces the entries of `checkedFiles` with `violations`; entries of other files stay.
    /// With `checkedFiles == nil` the whole baseline is replaced.
    public func updated(with violations: [Violation], checkedFiles: Set<String>?) -> Baseline {
        var result = Baseline(violations: violations)
        guard let checkedFiles else { return result }
        for (key, count) in counts {
            let file = String(key.prefix(while: { $0 != "|" }))
            if !checkedFiles.contains(file) { result.counts[key, default: 0] += count }
        }
        return result
    }
}
