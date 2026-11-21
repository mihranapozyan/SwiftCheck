//
//  SourceInput.swift
//  SwiftCheck
//
//  Created by Mihran on 21.11.26.
//

import Foundation

/// Source code that doesn't have to be on disk: an editor buffer, a file from the git index, generated code.
public struct SourceInput: Sendable, Hashable {
    /// Path used for configuration matching, suppression and reporting. Relative to the project root,
    /// or absolute (then include / exclude don't apply).
    public let path: String
    public let bytes: [UInt8]

    public init(path: String, bytes: [UInt8]) {
        self.path = path
        self.bytes = bytes
    }

    public init(path: String, text: String) {
        self.init(path: path, bytes: Array(text.utf8))
    }

    public init(path: String, data: Data) {
        self.init(path: path, bytes: [UInt8](data))
    }
}
