//
//  Report.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Output formats of the CLI. The JSON schema is versioned and kept stable for other tools.
public enum Report {
    public static let jsonVersion = 1

    public struct JSONViolation: Codable, Equatable, Sendable {
        public let rule: String
        public let severity: Severity
        public let file: String
        public let line: Int
        public let column: Int
        public let message: String
        public let baselined: Bool
    }

    public struct JSONReport: Codable, Equatable, Sendable {
        public let version: Int
        public let root: String
        public let violations: [JSONViolation]
        public let files: [String]
        public let durationMs: Int
    }

    public static func json(root: URL, violations: [Violation], files: [String], durationMs: Int) throws -> String {
        let report = JSONReport(
            version: jsonVersion,
            root: root.path,
            violations: violations.map {
                JSONViolation(rule: $0.rule, severity: $0.severity, file: $0.file, line: $0.line,
                              column: $0.column, message: $0.message, baselined: $0.baselined)
            },
            files: files,
            durationMs: durationMs
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    /// `path:line:col: warning|error: [rule] message` — understood by Xcode and most editors.
    public static func xcodeLine(_ violation: Violation, root: URL) -> String {
        let path = violation.file.hasPrefix("/") ? violation.file : root.appendingPathComponent(violation.file).path
        return "\(path):\(violation.line):\(violation.column): \(violation.severity.rawValue): [\(violation.rule)] \(violation.message)"
    }
}
