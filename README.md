# Swift + SwiftUI iOS App

A native iOS application using SwiftUI and a shared SwiftPM AppCore library.

## Testing

Write tests with **XCTest** (`import XCTest`, `final class …: XCTestCase`,
`func testName()`). XCTest is the framework the editor's runner captures: the
editor parses the XCTest `--xunit-output` file, and **swift-testing** (`import
Testing`, `@Test func`) results do **not** reliably land there on Xcode 16.x /
Swift 6.x — under `--parallel`, the swift-testing run can overwrite the xunit
with `tests="0"`, so the editor sees no tests. Put your tests in
`Tests/AppCoreTests/` with a `//` comment directly above each `func testX()`
describing what it verifies (the editor parses that comment as the test's
description).

Tests run via:

    swift test --parallel --disable-swift-testing --xunit-output .codeyam/swift-tests.xml

- `--parallel` is required: modern SwiftPM only writes the XCTest xunit to
  `--xunit-output` when run in parallel, so without it the project reports
  zero tests.
- `--disable-swift-testing` makes the xunit deterministic: it stops the
  swift-testing harness from also claiming `--xunit-output` and racing the
  XCTest writer, which otherwise nondeterministically truncates the file to
  `tests="0"`.

To register your tests with the editor after writing them, run:

    codeyam-editor editor reconcile-registry --auto-apply

This diffs the runner output against the registry and auto-adds new tests —
line numbers and descriptions are resolved automatically, so you do not need
to pass `--line` by hand.
