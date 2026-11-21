//
//  Severity.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// How serious a violation is. `error` makes the CLI exit with a non-zero status.
public enum Severity: String, Codable, Sendable, CaseIterable {
    case warning
    case error
}
