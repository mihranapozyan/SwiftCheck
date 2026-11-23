//
//  RuleRegistry.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

/// All built-in rules, in the order they are listed by `--list-rules`.
public enum RuleRegistry {
    public static let all: [Rule] = [
        .forceUnwrap,
        .forceCast,
        .forceTry,
        .iuoDeclaration,
        .barePrint,
        .sensitiveLog,
        .secretInUserDefaults,
        // Crashes and unsafe constructs
        .fatalErrorCall,
        .exitCall,
        .mainSync,
        .blockingInAsync,
        .emptyCatch,
        .unsafeBitCastCall,
        // Merge leftovers and markers in comments
        .conflictMarker,
        .fixmeComment,
        // Secrets
        .hardcodedSecret,
        // Opt-in rules
        .todoComment,
        .unownedReference,
        .uncheckedSendable,
        .discardedTry,
        .insecureURL,
    ]

    public static func rule(withID id: String) -> Rule? {
        all.first { $0.id == id }
    }
}
