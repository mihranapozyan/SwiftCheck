//
//  InsecureURLRule.swift
//  SwiftCheck
//
//  Created by Mihran on 23.11.26
//

import SwiftSyntax

extension Rule {
    /// Prefixes of identifiers that look like URLs but are XML / vocabulary namespaces, not endpoints.
    private static let namespacePrefixes = [
        "http://www.w3.org/", "http://schemas.", "http://purl.org/", "http://ns.adobe.com/",
        "http://www.apple.com/dtds/",
    ]

    private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "[::1]", "0.0.0.0"]

    static func isInsecureURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard lower.hasPrefix("http://") else { return false }
        if namespacePrefixes.contains(where: { lower.hasPrefix($0) }) { return false }
        let rest = lower.dropFirst("http://".count)
        let authority = rest.prefix { !"/?#".contains($0) }
        guard !authority.isEmpty else { return false }
        var host = Substring(authority)
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if host.hasPrefix("[") {
            if let close = host.firstIndex(of: "]") { host = host[...close] }
        } else if let colon = host.firstIndex(of: ":") {
            host = host[..<colon]
        }
        return !(localHosts.contains(String(host)) || host.hasSuffix(".local"))
    }

    public static let insecureURL = Rule(
        id: "insecure-url",
        severity: .warning,
        message: "Plain `http://` URL; use `https://`",
        description: "Flags string literals starting with http://. localhost, loopback addresses, *.local hosts "
            + "and well-known XML namespaces are allowed. Opt-in.",
        kinds: [.stringLiteralExpr],
        examples: RuleExamples(
            triggering: [
                #"let url = URL(string: ↓"http://api.example.com/v1")"#,
                #"let url = ↓"http://example.com""#,
                #"let url = ↓"HTTP://Example.com/path""#,
                #"let url = ↓"http://\(host)/v1""#,
            ],
            nonTriggering: [
                #"let url = "https://api.example.com""#,
                #"let url = "http://localhost:8080/api""#,
                #"let url = "http://127.0.0.1:3000""#,
                #"let url = "http://[::1]:8080/""#,
                #"let url = "http://0.0.0.0""#,
                #"let url = "http://printer.local/status""#,
                #"let ns = "http://www.w3.org/2000/svg""#,
                #"let ns = "http://schemas.microsoft.com/office""#,
                #"let ns = "http://purl.org/dc/elements/1.1/""#,
                #"let ns = "http://ns.adobe.com/xap/1.0/""#,
                #"let dtd = "http://www.apple.com/DTDs/PropertyList-1.0.dtd""#,
                #"let scheme = "http://""#,
            ]
        ),
        isOptIn: true,
        check: { node, _ in
            guard let literal = node.as(StringLiteralExprSyntax.self),
                  let first = literal.segments.first?.as(StringSegmentSyntax.self) else { return [] }
            let text = first.content.text
            // `"http://\(host)/x"`: the host is unknown, so the literal is flagged; a bare `"http://"` is a prefix check.
            let hostIsInterpolated = literal.segments.count > 1 && text.lowercased() == "http://"
            return hostIsInterpolated || isInsecureURL(text) ? [Finding(at: literal)] : []
        }
    )
}
