//
//  BarePrintRule.swift
//  SwiftCheck
//
//  Created by Mihran on 20.11.26.
//

import SwiftSyntax

extension Rule {
    static let printFunctions: Set<String> = ["print", "debugPrint", "dump"]

    public static let barePrint = Rule(
        id: "bare-print",
        severity: .warning,
        message: "`print` outside `#if DEBUG`; use a logger or wrap it in `#if DEBUG`",
        description: "Flags print / debugPrint / dump calls that are compiled into release builds.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [
                #"func run() { ↓print("hello") }"#,
                "↓debugPrint(value)",
                "↓dump(model)",
                "↓Swift.print(1)",
                "#if !DEBUG\n↓print(1)\n#endif",
                "#if DEBUG\nlet a = 1\n#else\n↓print(1)\n#endif",
                "#if DEBUG || targetEnvironment(simulator)\n↓print(1)\n#endif",
                "#if os(iOS)\n↓print(1)\n#endif",
            ],
            nonTriggering: [
                #"#if DEBUG\nprint("debug")\n#endif"#,
                "#if DEBUG && os(iOS)\nprint(1)\n#endif",
                "#if (DEBUG)\nprint(1)\n#endif",
                "#if !DEBUG\nlet a = 1\n#else\nprint(1)\n#endif",
                "#if os(macOS)\nlet a = 1\n#elseif DEBUG\nprint(1)\n#endif",
                "#if DEBUG\nfunc f() {\n#if os(iOS)\nprint(1)\n#endif\n}\n#endif",
                #"logger.print("x")"#,
                "func print(_ text: String) { }",
                "#Preview { let _ = print(1) }",
                "struct Row_Previews: PreviewProvider { static var previews: some View { let _ = print(1) } }",
            ]
        ),
        check: { node, context in
            guard !context.inDebug,
                  let call = node.as(FunctionCallExprSyntax.self),
                  let name = SyntaxHelpers.freeFunctionName(call), printFunctions.contains(name) else { return [] }
            return [Finding(at: call.calledExpression)]
        }
    )
}
