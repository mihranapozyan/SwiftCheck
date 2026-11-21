//
//  CommandLineOptions.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// Parsed command-line flags of `swiftcheck`.
struct CommandLineOptions: Equatable, Sendable {
enum Mode: Equatable, Sendable {
        case all
        case files([String])
        case diff(String)
    }

var mode: Mode = .all
var xcode = false
var json = false
var updateBaseline = false
var includeBaselined = false
var listRules = false
var help = false
var version = false
var root: String?

init() {}

struct ParseError: Error, CustomStringConvertible, Equatable {
        let description: String
    }

static let usage = """
        Usage: swiftcheck [--all] [--files a.swift b.swift] [--diff <base>] [--xcode] [--json]
                          [--update-baseline] [--include-baselined] [--list-rules] [--root <path>]

          --all                 Check every Swift file under the root (default).
          --files <paths…>      Check only these files.
          --diff <base>         Check files changed since <base> plus untracked files.
          --xcode               Print `path:line:col: severity: [rule] message`.
          --json                Print a JSON report (stable schema, see README).
          --update-baseline     Record current violations in the baseline file.
          --include-baselined   Also report violations covered by the baseline.
          --list-rules          Print the available rules.
          --root <path>         Project root (default: nearest folder with .swiftcheck.json).
          --version             Print the version.
        """

static func parse(_ arguments: [String]) throws -> CommandLineOptions {
        var options = CommandLineOptions()
        var modeSet = false
        func setMode(_ mode: Mode) throws {
            guard !modeSet else { throw ParseError(description: "Use only one of --all, --files, --diff") }
            modeSet = true
            options.mode = mode
        }

        var index = 0
        func value(for flag: String) throws -> String {
            index += 1
            guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                throw ParseError(description: "\(flag) expects a value")
            }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--all": try setMode(.all)
            case "--files":
                var paths: [String] = []
                while index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    index += 1
                    paths.append(arguments[index])
                }
                try setMode(.files(paths))
            case "--diff": try setMode(.diff(try value(for: argument)))
            case "--xcode": options.xcode = true
            case "--json": options.json = true
            case "--update-baseline": options.updateBaseline = true
            case "--include-baselined": options.includeBaselined = true
            case "--list-rules": options.listRules = true
            case "--root": options.root = try value(for: argument)
            case "--help", "-h": options.help = true
            case "--version": options.version = true
            default: throw ParseError(description: "Unknown argument `\(argument)`")
            }
            index += 1
        }
        if options.json, options.xcode { throw ParseError(description: "Use only one of --json, --xcode") }
        return options
    }
}
