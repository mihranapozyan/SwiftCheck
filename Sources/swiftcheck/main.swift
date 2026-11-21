//
//  main.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation
import SwiftCheckCore

/// Writes a line to stdout. The tool's output is its product, so it doesn't go through `print`.
func output(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

func printError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func run() -> Int32 {
    let options: CommandLineOptions
    do {
        options = try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst()))
    } catch {
        printError("error: \(error)\n\n\(CommandLineOptions.usage)")
        return 2
    }

    if options.help { output(CommandLineOptions.usage); return 0 }
    if options.version { output(SwiftCheck.version); return 0 }
    if options.listRules {
        for rule in RuleRegistry.all {
            output("\(rule.id.padding(toLength: 24, withPad: " ", startingAt: 0)) \(rule.severity.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(rule.description)")
        }
        return 0
    }

    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let rootURL = options.root.map { URL(fileURLWithPath: $0, relativeTo: cwd) }
        ?? Configuration.findRoot(from: cwd) ?? cwd

    let project: Project
    do { project = try Project(root: rootURL) } catch {
        printError("error: \(error)")
        return 2
    }
    for id in project.unknownRuleIDs { printError("warning: unknown rule `\(id)` in \(Configuration.fileName)") }

    let result: CheckResult
    switch options.mode {
    case .all:
        result = project.checkAll()
    case .files(let paths):
        result = project.check(paths: paths, relativeTo: cwd)
    case .diff(let base):
        do {
            let changed = try Git.changedFiles(since: base, in: project.root)
            let inside = project.files(atPaths: changed).filter { !$0.relativePath.hasPrefix("/") }
            result = project.check(inside)
        } catch {
            printError("error: \(error)")
            return 2
        }
    }

    if options.updateBaseline {
        do {
            let updated = try project.updateBaseline(with: result, replacingAll: options.mode == .all)
            printError("Baseline updated: \(updated.counts.values.reduce(0, +)) violations in \(project.baselineURL.path)")
            return 0
        } catch {
            printError("error: cannot write baseline: \(error)")
            return 2
        }
    }

    let shown = options.includeBaselined ? result.violations : result.reported
    if options.json {
        do { output(try result.jsonReport(includeBaselined: options.includeBaselined)) } catch {
            printError("error: \(error)")
            return 2
        }
    } else {
        for violation in shown { output(Report.xcodeLine(violation, root: result.root)) }
        printError("swiftcheck: \(result.files.count) files, \(result.errorCount) errors, \(result.warningCount) warnings, \(result.baselinedCount) baselined, \(result.durationMs) ms")
    }
    return result.hasErrors ? 1 : 0
}

exit(run())
