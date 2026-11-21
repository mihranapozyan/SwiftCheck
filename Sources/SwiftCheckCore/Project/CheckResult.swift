//
//  CheckResult.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation

/// Options for a single check run.
public struct CheckOptions: Sendable {
    /// Mark violations covered by the project's baseline (`Violation.baselined`).
    public var applyBaseline: Bool
    /// Polled between files; returning `true` stops the run early (`CheckResult.wasCancelled`).
    public var isCancelled: (@Sendable () -> Bool)?

    public init(applyBaseline: Bool = true, isCancelled: (@Sendable () -> Bool)? = nil) {
        self.applyBaseline = applyBaseline
        self.isCancelled = isCancelled
    }

    public static let `default` = CheckOptions()
}

/// The outcome of checking a set of files.
public struct CheckResult: Sendable, Equatable {
    /// Canonical project root; `Violation.file` and `files` are relative to it.
    public let root: URL
    /// All violations sorted by file, line and column, including baselined ones (see `Violation.baselined`).
    public let violations: [Violation]
    /// Files that were checked (relative paths). Inputs rejected by include / exclude are in `skipped`.
    public let files: [String]
    /// Requested inputs that weren't checked: not Swift, missing, or excluded by the configuration.
    public let skipped: [String]
    public let durationMs: Int
    /// The run was stopped through `CheckOptions.isCancelled`; results are incomplete.
    public let wasCancelled: Bool

    public init(root: URL, violations: [Violation], files: [String], skipped: [String] = [],
                durationMs: Int, wasCancelled: Bool = false) {
        self.root = root
        self.violations = violations
        self.files = files
        self.skipped = skipped
        self.durationMs = durationMs
        self.wasCancelled = wasCancelled
    }

    /// Violations that should be shown: not covered by the baseline.
    public var reported: [Violation] { violations.filter { !$0.baselined } }
    public var errorCount: Int { reported.count { $0.severity == .error } }
    public var warningCount: Int { reported.count { $0.severity == .warning } }
    public var baselinedCount: Int { violations.count { $0.baselined } }
    /// At least one non-baselined error: the CLI exits with status 1.
    public var hasErrors: Bool { reported.contains { $0.severity == .error } }

    /// Reported violations grouped by file.
    public var violationsByFile: [String: [Violation]] { Dictionary(grouping: reported, by: \.file) }

    public func absolutePath(of violation: Violation) -> String {
        violation.file.hasPrefix("/") ? violation.file : root.appendingPathComponent(violation.file).path
    }

    /// The stable JSON report (see README, "JSON output").
    public func jsonReport(includeBaselined: Bool = false) throws -> String {
        try Report.json(root: root, violations: includeBaselined ? violations : reported,
                        files: files, durationMs: durationMs)
    }
}
