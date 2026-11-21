//
//  Linter.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Dispatch
import Foundation

/// A source file to check: its absolute location and the path reported to the user.
public struct SourceFile: Sendable, Hashable {
    public let url: URL
    public let relativePath: String

    public init(url: URL, relativePath: String) {
        self.url = url
        self.relativePath = relativePath
    }
}

/// Checks many files in parallel, one tree walk per file.
public struct Linter: Sendable {
    public let ruleSet: RuleSet

    public init(ruleSet: RuleSet) {
        self.ruleSet = ruleSet
    }

    public func lint(_ files: [SourceFile]) -> [Violation] {
        lint(files, isCancelled: nil).violations
    }

    /// Checks files on disk. `isCancelled` is polled before each file; skipped files contribute nothing.
    public func lint(_ files: [SourceFile], isCancelled: (@Sendable () -> Bool)?) -> (violations: [Violation], cancelled: Bool) {
        run(count: files.count, isCancelled: isCancelled) { index in
            let file = files[index]
            guard let data = FileManager.default.contents(atPath: file.url.path) else { return [] }
            return SourceChecker.check(bytes: [UInt8](data), path: file.relativePath, ruleSet: ruleSet)
        }
    }

    /// Checks source code held in memory.
    public func lint(sources: [SourceInput], isCancelled: (@Sendable () -> Bool)? = nil) -> (violations: [Violation], cancelled: Bool) {
        run(count: sources.count, isCancelled: isCancelled) { index in
            SourceChecker.check(bytes: sources[index].bytes, path: sources[index].path, ruleSet: ruleSet)
        }
    }

    private func run(count: Int, isCancelled: (@Sendable () -> Bool)?,
                     _ work: @Sendable (Int) -> [Violation]) -> (violations: [Violation], cancelled: Bool) {
        let results = ResultSlots(count: count)
        let cancelled = CancelFlag()
        DispatchQueue.concurrentPerform(iterations: count) { index in
            if cancelled.isSet { return }
            if let isCancelled, isCancelled() { cancelled.set(); return }
            results.store(work(index), at: index)
        }
        return (results.values.flatMap { $0 }, cancelled.isSet)
    }
}

/// Set once by any worker; read by all.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Preallocated storage where each concurrent iteration writes exactly one slot.
private final class ResultSlots: @unchecked Sendable {
    private let buffer: UnsafeMutableBufferPointer<[Violation]>

    init(count: Int) {
        buffer = .allocate(capacity: count)
        buffer.initialize(repeating: [])
    }

    deinit {
        buffer.deinitialize()
        buffer.deallocate()
    }

    func store(_ value: [Violation], at index: Int) {
        buffer[index] = value
    }

    var values: [[Violation]] { Array(buffer) }
}
