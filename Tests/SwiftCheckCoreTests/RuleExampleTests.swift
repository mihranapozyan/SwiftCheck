//
//  RuleExampleTests.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import Testing
@testable import SwiftCheckCore

/// One documented example of a rule.
struct RuleExample: Sendable, CustomTestStringConvertible {
    let rule: Rule
    let source: String
    let triggers: Bool

    var testDescription: String { "\(rule.id) \(triggers ? "↓" : "✓") \(source.debugDescription)" }

    static let all: [RuleExample] = RuleRegistry.all.flatMap { rule in
        rule.examples.triggering.map { RuleExample(rule: rule, source: $0, triggers: true) }
            + rule.examples.nonTriggering.map { RuleExample(rule: rule, source: $0, triggers: false) }
    }
}

/// Removes `↓` markers and returns the cleaned source with the UTF-8 offsets they marked.
func stripMarkers(_ marked: String) -> (source: String, offsets: [Int]) {
    var source = ""
    var offsets: [Int] = []
    for character in marked {
        if character == "↓" { offsets.append(source.utf8.count) } else { source.append(character) }
    }
    return (source, offsets)
}

@Test(arguments: RuleExample.all)
func ruleExample(_ example: RuleExample) {
    let (source, expected) = stripMarkers(example.source)
    let violations = SourceChecker.check(source: source, path: "Example.swift", ruleSet: RuleSet(rules: [example.rule]))
    if example.triggers {
        #expect(!expected.isEmpty, "Triggering example must contain ↓")
    } else {
        #expect(expected.isEmpty, "Non-triggering example must not contain ↓")
    }
    #expect(violations.map(\.offset).sorted() == expected.sorted(), "\(violations)")
}

@Test func everyRuleHasExamples() {
    for rule in RuleRegistry.all {
        #expect(!rule.examples.triggering.isEmpty, "\(rule.id)")
        #expect(!rule.examples.nonTriggering.isEmpty, "\(rule.id)")
    }
}

@Test func ruleIDsAreUnique() {
    let ids = RuleRegistry.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}
