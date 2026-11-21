# SwiftCheck

A fast static analyzer for Swift code. It ships a small set of checks that are useful in any
Swift project: crash-prone constructs (`!`, `as!`, `try!`), stray `print` calls in release
builds, and secrets that end up in logs or `UserDefaults`.

- Built on swift-syntax — real syntax trees, no regexes.
- One tree walk per file: every rule declares the syntax kinds it cares about and the engine
  dispatches nodes to rules in a single pass.
- Files are checked in parallel.
- Baseline support for adopting it in an existing codebase.
- Stable JSON output for editors, Git clients and CI.
- Usable as a Swift library (`SwiftCheckCore`) to run the checks inside other apps — no process, no JSON.

Requirements: macOS 14+ on Apple Silicon, Swift 6 (Xcode 16 or later).

## Installation

Pick the way that fits: the plugin for projects, the command-line tool for CI and scripts, the library
for tools that embed the checks. All of them read the same `.swiftcheck.json` (see
[Configuration](#configuration)); without one, every rule runs with its default severity.

### Xcode and SwiftPM projects: plugin (recommended)

The plugins live in a separate lightweight package, **SwiftCheckPlugins**. It downloads the prebuilt
`swiftcheck` binary from this repository's release instead of compiling it, so it adds no build time and
no swift-syntax dependency to your project.

**Xcode project:** File ▸ Add Package Dependencies…, enter
`https://github.com/mihranapozyan/SwiftCheckPlugins.git` and add it without linking any product. Then, in
the app target: Build Phases ▸ Run Build Tool Plug-ins ▸ + ▸ **SwiftCheckBuildToolPlugin**. On the first
build Xcode asks to trust the plugin — choose Trust & Enable.

**Swift package:**

```swift
dependencies: [
    .package(url: "https://github.com/mihranapozyan/SwiftCheckPlugins.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyLibrary",
        plugins: [.plugin(name: "SwiftCheckBuildToolPlugin", package: "SwiftCheckPlugins")]
    ),
]
```

Every build then checks the target's Swift files: violations show up as warnings and errors on the
right lines, and an error-severity violation fails the build. The plugin looks for `.swiftcheck.json`
in the package / project folder and above it, so one configuration can cover a whole repository.

To check on demand, use the command plugin: `swift package swiftcheck` (all targets),
`swift package swiftcheck --target MyLibrary`, or right-click the project in Xcode's navigator ▸
SwiftCheck. Options such as `--json`, `--include-baselined` or `--diff main` are passed to the tool.

### Command line (CI, git hooks, scripts)

Download the binary from the latest release:

```bash
curl -fsSL -o swiftcheck.zip https://github.com/mihranapozyan/SwiftCheck/releases/download/0.1.0/swiftcheck-0.1.0-macos-arm64.zip
unzip swiftcheck.zip && sudo mv swiftcheck /usr/local/bin/ && rm swiftcheck.zip
swiftcheck --version
```

A zip downloaded with a browser is quarantined by macOS; `curl` avoids that. If macOS blocks the binary,
run `xattr -d com.apple.quarantine /usr/local/bin/swiftcheck`. Each release also lists a `.sha256`
checksum for the archive.

Or build it from source: `swift build -c release`, then copy `.build/release/swiftcheck`.

Typical uses:

```bash
swiftcheck                        # every Swift file under the project root
swiftcheck --diff origin/main     # only files changed on this branch — for CI
swiftcheck --update-baseline      # accept existing violations when adopting SwiftCheck
```

### Library

Add this package and link the `SwiftCheckCore` product — see [Using as a library](#using-as-a-library).

## Rules

| Rule | Default | What it flags |
|---|---|---|
| `force-unwrap` | warning | `value!`. Calls with only literal arguments to `URL(string:)`, `UIImage(named:)`, `UIImage(systemName:)` and `UIFont(name:size:)` are allowed. |
| `force-cast` | warning | `as!` |
| `force-try` | error | `try!` |
| `iuo-declaration` | warning | `T!` in declarations (properties, parameters, return types). `@IBOutlet` properties are allowed. |
| `bare-print` | warning | `print`, `debugPrint`, `dump` outside `#if DEBUG`. Decided from the syntax tree: `#if DEBUG && os(iOS)`, the `#else` branch of `#if !DEBUG` and nested conditions are understood. |
| `sensitive-log` | error | Values named *token*, *password*, *passcode*, *pin*, *otp*, *cvv*, *secret* passed to `print`, `NSLog`, `os_log` or to a call on a receiver named `logger`, `log` or `*Logger`. |
| `secret-in-userdefaults` | error | Writes of such values to `UserDefaults` (`set`, `setValue` on `UserDefaults` or `*defaults`) and `@AppStorage` properties. Reads and `removeObject` are allowed. |

Code inside `#Preview { … }` and types conforming to `PreviewProvider` is skipped by all rules.

### What counts as a secret

A name is considered secret when one of its camel-case words is `token`, `password`, `passcode`,
`pin`, `otp`, `cvv` or `secret` (plurals included): `accessToken`, `userPIN`, `otpCode`.
Not considered secret:

- types and UPPER_CASE constants (`Token`, `TOKEN_KEY`) — only lower-camel identifiers count;
- Bool flags starting with `is`, `has`, `should`, `shows`, `can`, `did`, `will`, `needs`, `uses`… (`isTokenValid`, `hasPin`);
- metadata about a secret ending in `count`, `length`, `enabled`, `field`, `key`, `type`… (`tokenCount`, `passwordField`);
- words that merely contain a secret word (`tokenizer`, `pinned`, `spinner`).

`sensitive-log` allows interpolations redacted with a non-public privacy level:
`logger.info("\(token, privacy: .private)")`.

For UserDefaults keys (`"auth_token"`, `Keys.password`) any letter case is accepted.
Writing a Bool literal is never flagged.

## Suppressing a violation

```swift
let url = URL(string: input)! // swiftcheck:ignore force-unwrap — validated by the form

// swiftcheck:ignore force-cast, force-unwrap — legacy API, removed in 2.0
let cell = table.dequeue(id) as! Cell
```

The comment applies to its own line, or — on a line of its own — to the next line of code.
Several rules are separated by commas; `all` suppresses every rule. Everything after the rule
list (`—`, `-`, `--` or any free text) is the reason.

## Configuration

`.swiftcheck.json` in the root of the checked project. The root is the folder that contains the
config: `swiftcheck` looks for it from the current directory upwards, or takes `--root`.
Without a config the current directory is the root and all rules run with defaults.

```json
{
  "include": ["Sources", "App"],
  "exclude": ["**/Generated", "App/Legacy", "**/*.pb.swift"],
  "baseline": ".swiftcheck-baseline.json",
  "rules": {
    "force-unwrap": "error",
    "iuo-declaration": "off"
  }
}
```

| Key | Meaning |
|---|---|
| `include` | Paths or globs relative to the root. If present, only matching files are checked. |
| `exclude` | Paths or globs to skip. |
| `baseline` | Baseline file path relative to the root. Default `.swiftcheck-baseline.json`. |
| `rules` | Either an object `id → "warning" \| "error" \| "off"` (unlisted rules keep defaults) or an array of ids (only these rules run). |

Globs: `*` matches within one path component, `?` one character, `**` any number of components.
A pattern also matches everything below a matching folder, so `Pods` and `**/Generated` exclude
whole directories. `.build`, `.swiftpm`, `DerivedData`, `Pods`, `Carthage`, `node_modules` and
hidden folders are never scanned by `--all`.

## Baseline

```bash
swiftcheck --update-baseline
```

The baseline is a JSON object `{ "file|rule|trimmed line text": count }`. Line numbers are not
part of the key, so moving code around doesn't bring old violations back. For each key only
occurrences beyond `count` are reported — adding a second copy of a baselined line is reported.

With `--files` or `--diff`, `--update-baseline` replaces entries only for the checked files and
keeps the rest. `--include-baselined` reports baselined violations too (`"baselined": true` in JSON).

## Command line

```
swiftcheck [--all] [--files a.swift b.swift] [--diff <base>] [--xcode] [--json]
           [--update-baseline] [--include-baselined] [--list-rules] [--root <path>]
```

| Flag | |
|---|---|
| `--all` | Check every Swift file under the root (default). |
| `--files <paths…>` | Check only these files (relative to the current directory or absolute). `include` / `exclude` still apply. |
| `--diff <base>` | Files changed since `<base>` (committed, staged and unstaged, `git diff --name-only <base>`) plus untracked files (`git ls-files --others --exclude-standard --full-name`). |
| `--xcode` | `path:line:col: warning\|error: [rule] message` — clickable in Xcode build logs. |
| `--json` | Machine-readable report, see below. |
| `--update-baseline` | Write current violations to the baseline. |
| `--include-baselined` | Also report baselined violations. |
| `--list-rules` | Print rule ids, default severities and descriptions. |
| `--root <path>` | Project root. |

Without `--json` the output is the `--xcode` format plus a summary line on stderr.

Exit status: `0` — no errors (warnings are fine), `1` — at least one non-baselined error,
`2` — invalid arguments, configuration or git failure.

As an Xcode build phase:

```bash
swiftcheck --xcode --diff HEAD
```

## JSON output

`--json` prints a single object. The schema is versioned; fields are only ever added.

```json
{
  "version": 1,
  "root": "/path/to/project",
  "violations": [
    {
      "rule": "force-unwrap",
      "severity": "warning",
      "file": "Sources/App/Loader.swift",
      "line": 42,
      "column": 17,
      "message": "Force unwrap; use `if let`, `guard let` or `??`",
      "baselined": false
    }
  ],
  "files": ["Sources/App/Loader.swift"],
  "durationMs": 12
}
```

| Field | |
|---|---|
| `version` | Schema version, currently `1`. |
| `root` | Absolute project root. |
| `violations[].file` | Path relative to `root` (absolute for files outside of it). |
| `violations[].line`, `column` | 1-based; the column counts UTF-8 bytes. |
| `violations[].severity` | `"warning"` or `"error"`, after configuration overrides. |
| `violations[].baselined` | `true` only with `--include-baselined`. |
| `files` | Every file that was checked (relative paths), so clients can clear stale results. |
| `durationMs` | Time spent checking the files (excludes process start and git queries). |

## Using as a library

SwiftCheck is a Swift package with two products: the `swiftcheck` executable and the `SwiftCheckCore`
library. Tools such as editors, Git clients or build plugins can link the library and run the checks
in-process.

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/mihranapozyan/SwiftCheck.git", exact: "0.1.0"),
],
targets: [
    .target(name: "MyTool", dependencies: [.product(name: "SwiftCheckCore", package: "SwiftCheck")]),
]
```

In an Xcode app project: File ▸ Add Package Dependencies…, enter the repository URL and add the
`SwiftCheckCore` product to the app target.

### Checking files

```swift
import SwiftCheckCore

// Opt-in: only projects that have .swiftcheck.json.
guard Project.hasConfiguration(at: repositoryURL) else { return }

let project = try Project(root: repositoryURL)       // reads .swiftcheck.json and the baseline
let result = project.check(paths: ["Sources/App/Loader.swift", "Sources/App/Store.swift"])

for violation in result.reported {                     // non-baselined, sorted by file / line / column
    print(violation.file, violation.line, violation.column, violation.severity, violation.rule, violation.message)
}
print(result.errorCount, result.warningCount, result.durationMs)
```

`Project` is an immutable, `Sendable` snapshot of the configuration, rules and baseline. Create a new
one to pick up edits to `.swiftcheck.json` or the baseline — it is cheap. `check` is synchronous and
uses all cores, so call it from a background task:

```swift
let result = await Task.detached(priority: .userInitiated) { project.check(paths: paths) }.value
```

### API overview

| API | |
|---|---|
| `Project(root:configuration:rules:)` | Opens a project. `configuration` overrides `.swiftcheck.json`; `rules` adds custom rules. Throws on an invalid configuration or baseline. |
| `Project.discover(from:)` | Nearest folder at or above a directory that has `.swiftcheck.json`. |
| `Project.hasConfiguration(at:)` | Whether a folder opted in. |
| `project.checkAll()` | Every Swift file under the root (same as `swiftcheck --all`). |
| `project.check(paths:relativeTo:)` | Files on disk; paths are absolute or relative to the root. |
| `project.check(sources:)` | Code held in memory (`SourceInput(path:text:)`): unsaved editor buffers, files from the git index. |
| `project.updateBaseline(with:replacingAll:)` | Writes the baseline (all entries, or only the checked files). |
| `CheckOptions(applyBaseline:isCancelled:)` | Skip the baseline; stop early when `isCancelled` returns `true`. |
| `result.reported` / `result.violations` | Non-baselined violations / all of them with `baselined` set. |
| `result.files` / `result.skipped` | Checked inputs / inputs that aren't Swift, are missing or are excluded by the configuration. |
| `result.errorCount`, `warningCount`, `hasErrors`, `violationsByFile` | Summaries for UI. |
| `result.jsonReport()` | The same JSON as `swiftcheck --json`. |
| `RuleRegistry.all` | Built-in rules with ids, default severities, descriptions and examples — for settings screens. |

Paths in results are relative to `project.root`, which is canonical (symlinks resolved, `/var` is
`/private/var`). `Violation.column` counts UTF-8 bytes, like the CLI.

Checking code from the git index lets a Git client check exactly what will be committed:

```swift
let staged = SourceInput(path: "Sources/App/Loader.swift", data: indexBlob) // e.g. output of `git show :path`
let result = project.check(sources: [staged])
```

## Performance

Release build, Apple M5 Max (18 cores), all rules:

| Input | Files | Time |
|---|---|---|
| Several app projects + swift-syntax sources | 1332 (≈ 5 MB, 137k lines) | ≈ 95 ms in-process, ≈ 130 ms wall incl. process start |
| swift-syntax repository (`--all`) | 716 | ≈ 60 ms in-process, ≈ 70 ms wall |

The target of 1000 files under 0.5 s holds with a wide margin. Parsing dominates; the rule pass
itself is a single walk with a dictionary lookup per node.

## Releasing

`scripts/release.sh <version> --plugins ../SwiftCheckPlugins` runs the tests, builds `swiftcheck` for
arm64, and writes to `dist/`:

- `swiftcheck-<version>-macos-arm64.zip` — the CLI;
- `SwiftCheckBinary.artifactbundle.zip` — the CLI as a SwiftPM binary target, used by SwiftCheckPlugins;
- a `.sha256` file for each.

It also generates SwiftCheckPlugins' `Package.swift` with the release URL and checksum. Then: tag and push
this repository, create the GitHub release with the two archives, and commit, tag and push
SwiftCheckPlugins with the same version. `SwiftCheck.version` must match the version being released.

## Architecture

```
Sources/
  SwiftCheckCore/
    Project/    Project, CheckResult, CheckOptions, SourceInput — the public entry point
    Engine/     Rule, RuleSet, SourceChecker (single-pass visitor), Linter (parallel), DebugCondition
    Rules/      one file per rule + RuleRegistry
    Support/    Configuration, Baseline, Glob, FileCollector, Git, Report, SyntaxHelpers
  swiftcheck/   CLI: argument parsing and output on top of Project
Tests/SwiftCheckCoreTests/
```

- `SourceChecker` parses a file and walks it once with a `SyntaxAnyVisitor`. A `RuleSet` holds a
  table `SyntaxKind → [rule]`; each node is handed only to the rules registered for its kind.
- The traversal context (`inDebug`, `inPreview`) lives on a stack: it is pushed when entering an
  `#if` clause and restored when leaving it. Preview declarations are not descended into.
- `Linter` runs `SourceChecker` for each file with `DispatchQueue.concurrentPerform`.
- `Project` ties configuration, file selection, `Linter` and the baseline together. The CLI is a thin
  layer over it, so the tool and embedding apps behave identically.
- Ignore comments are collected from token trivia during the same walk (only for files that
  contain the marker at all), so a marker inside a string literal is not a suppression.

## Adding a rule

Built-in rules live in this package; tools that embed `SwiftCheckCore` can also pass their own rules
to `Project(root:rules:)` (`RuleRegistry.all + [myRule]`) and configure them in `.swiftcheck.json` like
built-in ones. A target that defines rules also imports `SwiftSyntax`, so its package must list
swift-syntax with a version SwiftCheck accepts (`.package(url: "https://github.com/swiftlang/swift-syntax.git", "602.0.0"..<"603.0.0")`)
and add the `SwiftSyntax` product to the target.

To add a built-in rule:

1. Create `Sources/SwiftCheckCore/Rules/MyRule.swift`:

```swift
import SwiftSyntax

extension Rule {
    public static let noFatalError = Rule(
        id: "no-fatal-error",
        severity: .warning,
        message: "`fatalError` crashes the app; handle the error",
        description: "Flags fatalError calls.",
        kinds: [.functionCallExpr],
        examples: RuleExamples(
            triggering: [#"func f() { ↓fatalError("x") }"#],
            nonTriggering: [#"func f() { assertionFailure("x") }"#]
        ),
        check: { node, _ in
            guard let call = node.as(FunctionCallExprSyntax.self),
                  SyntaxHelpers.freeFunctionName(call) == "fatalError" else { return [] }
            return [Finding(at: call.calledExpression)]
        }
    )
}
```

2. Add it to `RuleRegistry.all`.
3. Run `swift test`. Every triggering example must produce violations exactly at the `↓`
   markers and every non-triggering example must produce none — the examples are the tests.

Guidelines: keep `check` cheap and local to the node (look at children and a few parents, don't
walk the whole file); use `context.inDebug` instead of searching for `#if` yourself; return a
custom `message` in `Finding` when the default one is too generic.
