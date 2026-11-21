//
//  FileCollector.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Finds the Swift files to check under a root, honoring the configuration.
public struct FileCollector: Sendable {
    /// Directories never descended into.
    public static let skippedDirectories: Set<String> = [
        ".build", ".swiftpm", "DerivedData", "Pods", "Carthage", "node_modules",
    ]

    public let root: URL
    public let configuration: Configuration

    public init(root: URL, configuration: Configuration) {
        self.root = Self.canonical(root)
        self.configuration = configuration
    }

    /// Every `.swift` file under the root.
    public func allFiles() -> [SourceFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [SourceFile] = []
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        for case let url as URL in enumerator {
            let path = url.path
            guard path.hasPrefix(prefix) else { continue }
            let relative = String(path.dropFirst(prefix.count))
            if (try? url.resourceValues(forKeys: Set(keys)))?.isDirectory == true {
                if Self.skippedDirectories.contains(url.lastPathComponent) || configuration.excludesDirectory(relative) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension == "swift", configuration.accepts(relative) {
                files.append(SourceFile(url: url, relativePath: relative))
            }
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    /// The given paths (absolute or relative to `base`) that are Swift files accepted by the configuration.
    public func files(atPaths paths: [String], relativeTo base: URL) -> [SourceFile] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            let url = Self.canonical(path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path))
            guard url.pathExtension == "swift",
                  FileManager.default.fileExists(atPath: url.path),
                  seen.insert(url.path).inserted else { return nil }
            let relative = relativePath(of: url)
            if relative.hasPrefix("/") || configuration.accepts(relative) {
                return SourceFile(url: url, relativePath: relative)
            }
            return nil
        }
    }

    /// Absolute path with symlinks resolved (`/var` → `/private/var`), like `realpath(3)`.
    public static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        guard let resolved = realpath(standardized.path, nil) else { return standardized }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    /// Root-relative path, or the absolute path for files outside the root.
    public func relativePath(of url: URL) -> String {
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }
}
