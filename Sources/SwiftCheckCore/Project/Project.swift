//
//  Project.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation

/// A project checked by SwiftCheck: a root folder, its configuration, the active rules and the baseline.
///
/// This is the entry point for embedding SwiftCheck in other tools. `Project` is an immutable snapshot:
/// create a new one to pick up edits to `.swiftcheck.json` or the baseline. It is cheap to create and
/// `Sendable`; `check` runs synchronously and in parallel, so call it off the main thread.
///
/// ```swift
/// let project = try Project(root: repositoryURL)
/// let result = project.check(paths: ["Sources/App/Loader.swift"])
/// for violation in result.reported { print(violation.file, violation.line, violation.message) }
/// ```
public struct Project: Sendable {
    /// Canonical root (symlinks resolved).
    public let root: URL
    public let configuration: Configuration
    /// Every rule this project knows about (built-in plus custom); the configuration picks the active ones.
    public let availableRules: [Rule]
    public let ruleSet: RuleSet
    /// The baseline file location, whether or not it exists.
    public let baselineURL: URL
    /// The baseline loaded when the project was created; `nil` if the file doesn't exist.
    public let baseline: Baseline?

    /// Opens the project at `root`.
    /// - Parameters:
    ///   - configuration: Overrides `.swiftcheck.json`. When `nil`, the file is read if present, otherwise defaults apply.
    ///   - rules: The rules to choose from; add custom rules to `RuleRegistry.all`.
    /// - Throws: `Configuration.ConfigError` for an invalid configuration, decoding errors for an invalid baseline.
    public init(root: URL, configuration: Configuration? = nil, rules: [Rule] = RuleRegistry.all) throws {
        let root = FileCollector.canonical(root)
        let configURL = root.appendingPathComponent(Configuration.fileName)
        let configuration = try configuration
            ?? (FileManager.default.fileExists(atPath: configURL.path) ? Configuration.load(from: configURL) : Configuration())
        self.root = root
        self.configuration = configuration
        self.availableRules = rules
        self.ruleSet = configuration.ruleSet(from: rules)
        self.baselineURL = URL(fileURLWithPath: configuration.baseline, relativeTo: root).standardizedFileURL
        self.baseline = FileManager.default.fileExists(atPath: baselineURL.path) ? try Baseline.load(from: baselineURL) : nil
    }

    /// Opens the nearest project at or above `directory` that has `.swiftcheck.json`, or `nil` if there is none.
    public static func discover(from directory: URL, rules: [Rule] = RuleRegistry.all) throws -> Project? {
        guard let root = Configuration.findRoot(from: directory) else { return nil }
        return try Project(root: root, rules: rules)
    }

    /// Whether `root` contains `.swiftcheck.json` — how tools decide that a project opted in.
    public static func hasConfiguration(at root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(Configuration.fileName).path)
    }

    /// Rule ids in the configuration that none of `availableRules` has.
    public var unknownRuleIDs: [String] { configuration.unknownRuleIDs(known: availableRules) }

    private var collector: FileCollector { FileCollector(root: root, configuration: configuration) }

    // MARK: - Files

    /// Every Swift file under the root that the configuration accepts.
    public func allFiles() -> [SourceFile] { collector.allFiles() }

    /// Resolves paths (absolute, or relative to `base`, default the root) to checkable files.
    public func files(atPaths paths: [String], relativeTo base: URL? = nil) -> [SourceFile] {
        collector.files(atPaths: paths, relativeTo: base ?? root)
    }

    /// Root-relative path for an absolute URL (absolute path for files outside the root).
    public func relativePath(of url: URL) -> String { collector.relativePath(of: FileCollector.canonical(url)) }

    // MARK: - Checking

    /// Checks every Swift file under the root.
    public func checkAll(options: CheckOptions = .default) -> CheckResult {
        check(allFiles(), skipped: [], options: options)
    }

    /// Checks files on disk. Paths are absolute or relative to `base` (default: the root).
    public func check(paths: [String], relativeTo base: URL? = nil, options: CheckOptions = .default) -> CheckResult {
        let files = files(atPaths: paths, relativeTo: base)
        let accepted = Set(files.map { $0.url.path })
        let skipped = paths.filter { path in
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : (base ?? root).appendingPathComponent(path)
            return !accepted.contains(FileCollector.canonical(url).path)
        }
        return check(files, skipped: skipped, options: options)
    }

    /// Checks already resolved files.
    public func check(_ files: [SourceFile], options: CheckOptions = .default) -> CheckResult {
        check(files, skipped: [], options: options)
    }

    /// Checks source code held in memory. Inputs that aren't `.swift` or are excluded by the configuration are skipped.
    public func check(sources: [SourceInput], options: CheckOptions = .default) -> CheckResult {
        let start = DispatchTime.now()
        var accepted: [SourceInput] = []
        var skipped: [String] = []
        for source in sources {
            let isSwift = source.path.hasSuffix(".swift")
            if isSwift, source.path.hasPrefix("/") || configuration.accepts(source.path) {
                accepted.append(source)
            } else {
                skipped.append(source.path)
            }
        }
        let linter = Linter(ruleSet: ruleSet)
        let (violations, cancelled) = linter.lint(sources: accepted, isCancelled: options.isCancelled)
        return finish(violations, files: accepted.map(\.path), skipped: skipped, cancelled: cancelled,
                      start: start, options: options)
    }

    private func check(_ files: [SourceFile], skipped: [String], options: CheckOptions) -> CheckResult {
        let start = DispatchTime.now()
        let (violations, cancelled) = Linter(ruleSet: ruleSet).lint(files, isCancelled: options.isCancelled)
        return finish(violations, files: files.map(\.relativePath), skipped: skipped, cancelled: cancelled,
                      start: start, options: options)
    }

    private func finish(_ violations: [Violation], files: [String], skipped: [String], cancelled: Bool,
                        start: DispatchTime, options: CheckOptions) -> CheckResult {
        let applied = options.applyBaseline ? (baseline?.apply(to: violations) ?? violations.sorted()) : violations.sorted()
        let durationMs = Int((DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        return CheckResult(root: root, violations: applied, files: files, skipped: skipped,
                           durationMs: durationMs, wasCancelled: cancelled)
    }

    // MARK: - Baseline

    /// Records `result` in the baseline file and returns the new baseline.
    /// With `replacingAll`, the baseline is replaced; otherwise only entries of `result.files` change.
    @discardableResult
    public func updateBaseline(with result: CheckResult, replacingAll: Bool) throws -> Baseline {
        let updated = (baseline ?? Baseline()).updated(with: result.violations,
                                                       checkedFiles: replacingAll ? nil : Set(result.files))
        try updated.save(to: baselineURL)
        return updated
    }
}
