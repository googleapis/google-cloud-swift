# Gemini Code Assist Style Guide for `google-cloud-swift`

Follow the rules in [AGENTS.md](../AGENTS.md) and
[ARCHITECTURE.md](../ARCHITECTURE.md) when reviewing pull requests. Do not
comment on code in the `generated/` directory, which is produced by `librarian`.

## Public APIs in Hand-written Packages

New public APIs in hand-written packages (`pkgs/swift-google-cloud-*`) must
follow
[howto-guide-handwritten-client-api.md](../doc/contributor/howto-guide-handwritten-client-api.md).
Use its "Review checklist" when reviewing such changes, and refer to rules by
their identifier (for example, **E1**). Existing APIs predate the guide; only
comment on new or changed public APIs.

Call out, in particular:

- Changes to protocol requirements that applications implement as mocks: tuples
  or discarded server data in return types, positional parameters instead of an
  options struct, missing default implementations, and unnecessary `@Sendable`
  or `Sendable` constraints on closure parameters.
- Client-side validation of service limits, and initializers that `throw` only
  to enforce them.
- New `Codable` conformances on hand-written public types.
- Retry loops that do not use `GoogleGax.RetryPolicy` and `BackoffPolicy`.
- Streamed results (`AsyncSequence`) that applications cannot construct or wrap
  using only public API.
- Public, non-underscored symbols called by macro expansions.
- Public error cases that are never thrown, or errors reported with the wrong
  case.
- Logging metadata keys that differ from the generated `<Service>+Logging`
  layer, and `rpc.method` values that are not real RPCs.
- Missing tests: option fields reaching the request, a plain-`import` mock and
  forwarding decorator, failure tests for multi-RPC operations, and tests that
  produce every public error case.
- Public symbols without docstrings, `@Snippet`s that do not call the symbol
  they document, and design documents in `doc/design/` that no longer match the
  implementation.
