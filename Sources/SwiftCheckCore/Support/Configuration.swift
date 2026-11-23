//
//  Configuration.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation

/// Contents of `.swiftcheck.json` at the project root.
///
/// ```json
/// {
///   "include": ["Sources", "App"],
///   "exclude": ["**/Generated", "Pods"],
///   "baseline": ".swiftcheck-baseline.json",
///   "rules": { "force-unwrap": "error", "bare-print": "off" }
/// }
/// ```
/// `rules` is either an object (`id` → `"warning"` | `"error"` | `"off"`, unlisted rules keep
/// their defaults) or an array of ids (only these rules run, with default severities).
/// Opt-in rules (`Rule.isOptIn`) are off unless listed in the array, or set to a severity / `"on"` in the object.
public struct Configuration: Sendable, Equatable {
    public static let fileName = ".swiftcheck.json"
    public static let defaultBaseline = ".swiftcheck-baseline.json"

    public enum RuleSetting: Sendable, Equatable {
        case off
        case on(Severity?)
    }

    public var include: [String]
    public var exclude: [String]
    public var baseline: String
    /// `nil` means "all rules"; otherwise only listed rules are enabled.
    public var onlyRules: Set<String>?
    public var overrides: [String: RuleSetting]

    public init(
        include: [String] = [],
        exclude: [String] = [],
        baseline: String = Configuration.defaultBaseline,
        onlyRules: Set<String>? = nil,
        overrides: [String: RuleSetting] = [:]
    ) {
        self.include = include
        self.exclude = exclude
        self.baseline = baseline
        self.onlyRules = onlyRules
        self.overrides = overrides
    }

    public enum ConfigError: Error, CustomStringConvertible {
        case invalid(String)
        public var description: String {
            switch self { case .invalid(let message): message }
        }
    }

    public static func load(from url: URL) throws -> Configuration {
        try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> Configuration {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError.invalid("\(fileName) must contain a JSON object")
        }
        var config = Configuration()
        for (key, value) in object {
            switch key {
            case "include": config.include = try strings(value, key)
            case "exclude": config.exclude = try strings(value, key)
            case "baseline":
                guard let path = value as? String else { throw ConfigError.invalid("`baseline` must be a string") }
                config.baseline = path
            case "rules":
                if let list = value as? [String] {
                    config.onlyRules = Set(list)
                } else if let map = value as? [String: String] {
                    for (id, setting) in map {
                        switch setting {
                        case "off": config.overrides[id] = .off
                        case "on": config.overrides[id] = .on(nil)
                        default:
                            guard let severity = Severity(rawValue: setting) else {
                                throw ConfigError.invalid("Unknown severity `\(setting)` for rule `\(id)`")
                            }
                            config.overrides[id] = .on(severity)
                        }
                    }
                } else {
                    throw ConfigError.invalid("`rules` must be an array of ids or an object of id → severity")
                }
            default:
                throw ConfigError.invalid("Unknown key `\(key)` in \(fileName)")
            }
        }
        return config
    }

    private static func strings(_ value: Any, _ key: String) throws -> [String] {
        guard let list = value as? [String] else { throw ConfigError.invalid("`\(key)` must be an array of strings") }
        return list
    }

    /// Rule ids mentioned in the configuration that none of `known` has.
    public func unknownRuleIDs(known rules: [Rule] = RuleRegistry.all) -> [String] {
        let known = Set(rules.map(\.id))
        return (Set(overrides.keys).union(onlyRules ?? [])).subtracting(known).sorted()
    }

    public func ruleSet(from rules: [Rule] = RuleRegistry.all) -> RuleSet {
        RuleSet(rules.compactMap { rule in
            if let onlyRules, !onlyRules.contains(rule.id) { return nil }
            switch overrides[rule.id] {
            case .off: return nil
            case .on(let severity): return ConfiguredRule(rule, severity: severity)
            case nil:
                // Opt-in rules run only when named in the array form of `rules`.
                if rule.isOptIn, onlyRules?.contains(rule.id) != true { return nil }
                return ConfiguredRule(rule)
            }
        })
    }

    /// Whether a root-relative path passes include / exclude.
    public func accepts(_ relativePath: String) -> Bool {
        if !include.isEmpty, !include.contains(where: { Glob.matches($0, path: relativePath) }) { return false }
        return !exclude.contains { Glob.matches($0, path: relativePath) }
    }

    /// Whether a directory can be skipped entirely while enumerating.
    func excludesDirectory(_ relativePath: String) -> Bool {
        exclude.contains { Glob.matches($0, path: relativePath) }
    }

    /// Walks up from `directory` looking for `.swiftcheck.json`.
    public static func findRoot(from directory: URL) -> URL? {
        var current = directory.standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(fileName).path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { return nil }
            current = parent
        }
    }
}
