//
//  Git.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// The few git queries needed for `--diff`.
public enum Git {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Absolute paths of Swift files changed relative to `base` (committed, staged and unstaged),
    /// plus untracked files that aren't ignored.
    public static func changedFiles(since base: String, in directory: URL) throws -> [String] {
        let topLevel = try run(["rev-parse", "--show-toplevel"], in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = try run(["diff", "--name-only", "--diff-filter=d", "-z", base, "--"], in: directory)
        let untracked = try run(["ls-files", "--others", "--exclude-standard", "--full-name", "-z"], in: directory)
        let top = URL(fileURLWithPath: topLevel)
        return (changed + untracked)
            .split(separator: "\0")
            .map { top.appendingPathComponent(String($0)).path }
    }

    static func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + arguments
        process.currentDirectoryURL = directory
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(description: "git \(arguments.joined(separator: " ")) failed: \(message)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
