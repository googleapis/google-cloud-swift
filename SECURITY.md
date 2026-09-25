# Security Policy

To report a security issue, please use [g.co/vulnz](https://g.co/vulnz).

The Google Security Team will respond within 5 working days of your report on
g.co/vulnz.

We use g.co/vulnz for our intake, and do coordination and disclosure here using
GitHub Security Advisory to privately discuss and fix the issue.

## Memory Safety

All handcrafted packages in this repository compile under Swift 6 with strict
concurrency and opt into `-strict-memory-safety` ([SE-0458]) via
`.strictMemorySafety()` in `Package.swift`. Under `-warnings-as-errors` in CI,
any unannotated use of unsafe pointers, buffers, or memory-unsafe constructs
fails the build, ensuring all low-level memory operations are explicitly audited
and marked with `@safe`, `@unsafe`, and `unsafe`.

[SE-0458]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md
