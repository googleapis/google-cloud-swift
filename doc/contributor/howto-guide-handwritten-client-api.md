# How-To Guide: Designing Hand-written Client APIs

This guide applies to **new public APIs** in hand-written packages, such as
`pkgs/swift-google-cloud-storage` and new packages like
`pkgs/swift-google-cloud-datastore`. It does not apply to generated code. Some
existing APIs predate this guide and do not follow every rule. Do not copy those
exceptions into new code, and do not change existing public APIs only to
conform; that requires a breaking change and a separate discussion.

[ARCHITECTURE.md](../../ARCHITECTURE.md) is binding for hand-written packages as
well as generated ones. In particular, read "No client-side validation",
"Separate namespace for fields vs. options", "Request configuration and the
`.with` idiom", and "Mocking and testing" before designing a new API.
[doc/public-api.md](../public-api.md) defines what is part of the public API.

Each rule below explains *why* it exists. Most rules prevent changes that would
otherwise require a breaking release when the service evolves, or when we
improve features shared across all client libraries (mocking, retries,
observability). Rule identifiers (for example, **E1**) are stable, so reviews
can refer to them.

## Evolving with the service

### E1: Protocol requirements return named structs

Applications implement the service protocols (and transaction or session
protocols) as mocks. Once released, **every requirement signature is frozen**:
changing a parameter, a return type, `throws`, `async`, or a closure attribute
breaks every downstream mock, even if the change is source-compatible for
callers.

Requirements that wrap an RPC, or a sequence of RPCs, return a named struct,
even if the response is empty or has a single field today (for example, an
`AllocateIDsResult` rather than `[Key]`, and a `ReserveIDsResult` rather than
`Void`). Never return a tuple: tuples cannot gain members. Convenience
requirements that are defined in terms of another requirement (for example,
`get()` defined in terms of `lookup()`) may return a model type, because the
full response is available through the other requirement.

```swift
// ❌ Adding commit metadata later breaks every mock.
func runInTransaction<T>(
  options: TransactionOptions,
  _ body: (any TransactionProtocol) async throws -> T
) async throws -> (value: T, commit: CommitResult)

// ❌ The RPC returns a version and timestamps; this discards them.
func insert(_ entity: Entity, options: InsertOptions) async throws -> Key
func delete(_ key: Key, options: DeleteOptions) async throws

// ✅
public struct TransactionResult<T> {
  public var value: T
  public var commit: CommitResult
}
func insert(_ entity: Entity, options: InsertOptions) async throws -> MutationResult
func delete(_ key: Key, options: DeleteOptions) async throws -> MutationResult
```

Do not discard parts of the server response because the first caller does not
need them. For example, a `delete()` that supports preconditions must return the
mutation result, so the caller can tell if the delete was skipped due to a
conflict. Use the same result shape for the same operation everywhere (for
example, `update()` on the client and on a transaction).

Every requirement has a default implementation in a protocol extension (see
"Mocking and testing" in ARCHITECTURE.md), so adding requirements is not a
breaking change.

### E2: Requirements end with an operation-specific options struct

Each requirement takes the data that identifies the operation (keys, entities,
queries) and ends with an `options:` struct specific to that operation. Do not
add positional knobs, they cannot evolve:

```swift
// ❌ A new read-only transaction option needs a new requirement.
func runReadOnlyTransaction<T>(
  readTime: WKTTimestamp?,
  options: RequestOptions,
  _ body: (any ReadOnlyTransactionProtocol) async throws -> T
) async throws -> T

// ❌ The second decoding option breaks every conformance.
init(entity: Entity, ignoreUnknownProperties: Bool) throws

// ✅
func runReadOnlyTransaction<T>(
  options: ReadOnlyTransactionOptions,
  _ body: (any ReadOnlyTransactionProtocol) async throws -> T
) async throws -> T
init(entity: Entity, options: DecodingOptions) throws
```

Introduce operation-specific option types even if they only contain
`GoogleGax.RequestOptions` today. Sharing one options type across operations
means changing the type of `options:` in a requirement when one of them gains a
new field. A family of methods that send the same RPC (for example, `get()`,
`getMulti()`, and `lookup()`) may share one options type; methods that send
different RPCs (for example, `insert()` and `allocateIDs()`) may not. Protocols
that applications implement for policies (retry, backoff, resume) follow the
same rule: they receive a state struct, not positional arguments.

The same applies to public convenience functions outside protocols: prefer an
options struct over `Bool` flags (`explainQuery(analyze: true)`), because a
second flag turns every call site into a guessing game, and the function cannot
gain options without a new overload.

### E3: Do not validate service limits on the client

See "No client-side validation" in [ARCHITECTURE.md](../../ARCHITECTURE.md).
Limits such as "at most 30 values in an `IN` filter", "at most 1,000 keys per
lookup", "at most 1,500 bytes in an indexed string", or "at most 50 request
tags" are service policies, and they change. Let the service reject the request.
If a limit is mentioned in documentation, quote the proto comments and describe
it as a current service limit.

Validation that is needed to build a well-formed request is fine. Examples
include rejecting a value that cannot be represented in the wire format, an
integer overflow while computing a request field, or a key that has the wrong
shape for the operation (an incomplete key where a complete key is required).

Constraints that are only documented in proto comments (maximum lengths, path
depths, "must be non-zero", "field A requires field B", "at most N elements")
are service policy, not request shape: let the service enforce them. When in
doubt, ask whether the library could send the request at all. If it could, the
service decides.

Never validate data decoded from the service. Unknown enum values, operators, or
value types must not fail a read: keep them in an `unknown`-style case or as an
opaque value. Checking that a response is consistent with the request (for
example, one result per mutation sent) is fine: it detects bugs, not new service
features.

### E4: Decide `throws` and `async` up front

Removing `throws` from a protocol requirement breaks conformers. Removing it
from a function or initializer produces "no calls to throwing functions occur
within 'try'" warnings, which break applications that build with
`-warnings-as-errors`. Adding `throws` or `async` breaks callers.

- Value-type initializers and factory functions (keys, filters, transforms,
  vectors) are non-throwing unless the conversion can genuinely fail. Do not
  make them `throws` to enforce service limits (see **E3**).
- Functions that buffer work, perform I/O, or could plausibly fail in the future
  are `throws` from the start.
- Handles that can outlive the scope they are valid in (for example, a
  transaction used after the transaction closure returned) report an error when
  used out of scope. They never silently drop work.

### E5: No `Codable` on hand-written public types

Applications persist `Codable` values (caches, queues, session state). Once they
do, the encoding is a compatibility contract for stored data, not just source
code, and `doc/public-api.md` prevents applications from replacing the
conformance with their own.

Do not add `Codable` to hand-written public types unless the encoding is the
canonical ProtoJSON of a proto message, which every language can read. If an
application needs a stable string form (for example, of a key), provide an
explicit, documented `encoded` property and initializer. Adding a conformance
later is additive; removing it is not.

### E6: Reuse the GAX retry and backoff abstractions

Veneer-level loops (transaction retries, deferred reads, resumable operations)
use `GoogleGax.RetryPolicy`, `GoogleGax.BackoffPolicy`, and
`GoogleGax.RetryState`, like `GoogleGax.ClientOptions` and the Storage resume
policies.

```swift
// ❌ Cannot express "retry for up to 30 seconds"; misses GAX retry telemetry.
public var maxTransactionAttempts: Int = 5

// ✅
public var transactionRetryPolicy: any GoogleGax.RetryPolicy
public var transactionBackoffPolicy: any GoogleGax.BackoffPolicy
```

Define a package-specific policy protocol only when the GAX protocol cannot
express the decision, and then give it a state struct of its own (see **E2**).

### E7: Opaque tokens stay opaque

Tokens returned by the library (pending keys, cursors, continuation state) do
not expose their representation. For example, a `PendingKey(index:)` initializer
documented as "an index into the commit results" ties the public API to the
current buffering strategy: deduplicating or splitting mutations would silently
change its meaning. Provide explicit constructors for mocks instead, such as
`PendingKey(resolvedKey:)`.

### E8: Define the error contract

Applications must know which errors to catch.

- Document, on the package error type, which failures are
  `GoogleGax.RequestError` (service and transport errors) and which are the
  package error type (input or decoding errors detected by the library).
- Every public error case is thrown somewhere, and a test produces it (see
  **T4**). Publishing cases that are never thrown leaves two options later:
  start throwing them (a behavior change for anyone catching other errors) or
  remove them (a breaking change).
- Use each case for its documented meaning. Do not report an exhausted retry
  loop, or an internal invariant violation, as an invalid argument.
- Loops that run out of attempts either rethrow the last
  `GoogleGax.RequestError` (consistent with `RequestError.exhausted`) or throw a
  package error that carries the underlying error. Pick one, and document it.

### E9: Define equality for types with inherited fields

If a public type has fields that are "inherited from the client" when `nil` (for
example, project, database, or namespace), document what `==` and `hash(into:)`
mean, and test that a value built by the application compares equal to the same
value returned by the service. Otherwise, applications that look up results in a
`Set` or `Dictionary` fail silently. Changing the semantics of `==` later is a
silent behavior change.

Prefer designs where the question does not arise: for example, require the full
partition when constructing a value directly, and offer inheritance only through
a client-bound factory. The rule also applies to types that contain such values
(entities, queries).

### E10: Input and output enums

`doc/public-api.md` documents that public enums are non-frozen. In addition:

- Enums that hold values decoded from the service have a catch-all case (for
  example, `unknown(UnknownValue)` or `unknownStringValue(String)`), so new
  service values do not fail a read (see **E3**).
- Document, on each catch-all case, that values found there today may be
  promoted to named cases in a future release, so applications should not match
  specific values in the catch-all.

## Mocking and decorators

### K1: Default implementations behave like the real client

Default protocol-extension implementations that do more than throw
`RequestError.unimplemented` (for example, `get()` implemented in terms of
`lookup()`) have the same semantics as the real client. If the client
canonicalizes keys, deduplicates inputs, or reports partial results, the default
does the same. If the default cannot match the client (for example, because it
needs client configuration), it throws `RequestError.unimplemented` instead.

Concrete clients do not re-declare methods that are only defined in a protocol
extension. Such methods are statically dispatched, so the behavior would depend
on whether the caller holds the concrete type or `any <Service>Protocol`.

### K2: Streamed results are mockable and wrappable

Applications wrap service protocols to add tracing, caching, auditing, or
request tags, forwarding every requirement to an inner implementation. That is
only possible if every result type can be built from public API.

Types that return results incrementally (`AsyncSequence` conformances, paged
results, download handles) either:

- are returned as a protocol existential, like `any ReadObjectHandleProtocol` in
  `StorageProtocol`, or
- provide a public initializer that takes a closure producing the next element
  and the associated state (cursor, metadata), so a wrapper can forward to the
  inner sequence.

A convenience initializer from an array of elements is useful for simple tests,
but it is not enough: tests must be able to simulate failures in the middle of
the stream. Document whether the sequence is single-pass, and when errors
(including request errors) are reported.

### K3: Use the minimum concurrency annotations on requirement closures

Closure parameters on requirements (transaction runners, retry helpers) use the
minimum annotations the implementation needs. With
`NonisolatedNonsendingByDefault`, a closure that the library calls sequentially
on the caller's executor does not need `@Sendable`, and its result does not need
`T: Sendable` (consider `sending T`). Unnecessary annotations force capture
lists and block non-`Sendable` results; relaxing them later changes the
requirement and breaks mocks (see **E1**).

### K4: Client initialization matches the other clients

Clients are initialized from an options struct whose transport configuration is
a `GoogleGax.ClientOptions`, so credentials, endpoints, universe domains,
loggers, and retry policies work the same way as in every other client. Emulator
support uses the service's documented environment variable, which then becomes
part of the public API (see `doc/public-api.md`).

## Macros

### M1: Macro expansions call only underscored helpers

Macro expansions run in the application's module, so every symbol they call must
be `public`. Unless those symbols are underscored, they are part of the public
API, and every future change to the expansion strategy becomes a breaking
change.

- Expansions call only `_`-prefixed declarations (for example,
  `_DatastoreFlattenable` or `_applyAllocatedKey(_:)`), annotated with
  `@_documentation(visibility: internal)` so DocC hides them.
- The user-facing extension point is small and documented. For example, a
  protocol with `init(datastoreValue:)` and `toDatastoreValue()`, which
  applications can implement for their own types.
- Ambiguous input (for example, two properties that map to the same property
  name after flattening) is never resolved silently. Report it as a compile-time
  diagnostic when the macro can detect it, and as a runtime error otherwise (for
  example, when the collision involves a nested type the macro cannot see).
- Expansions refer to types by fully qualified names only where needed, and are
  tested with the module name shadowed by a local type.

### M2: Macros live in a separate package

Macro targets depend on `swift-syntax`. Every application that depends on the
macro, even indirectly, resolves and builds `swift-syntax`, and inherits its
version range, which often conflicts with other macro packages in the dependency
graph.

In general, macros live in a separate package, which depends on the runtime
package. If they are included in the same package, the design document must
provide a detailed rationale, and the macros must be in a separate product, so
applications that do not use them do not depend on `swift-syntax`. Splitting the
macros out after a release is a breaking change.

## Observability

### O1: Reuse the generated logging decorator and its keys

Prefer the generated `Clients.<Service>Logging` decorator for per-attempt logs
(see "The structure of a client" in ARCHITECTURE.md). This keeps generator
improvements flowing into the package. Logs emitted by the veneer use the same
metadata keys as the generated layer (`gcp.artifact.id`, `gcp.client.service`,
and so on). Use a single artifact identifier for the whole package: the
identifier of the published package (for example, `google-cloud-datastore`),
configured on the generated decorator too if it is used internally. Do not
invent new key namespaces.

### O2: `rpc.method` names real RPCs

The `rpc.method` metadata always names an RPC that exists, for example
`google.datastore.v1.Datastore/Commit`. Veneer operations that span several RPCs
(transactions, paginated queries) use a separate attribute.

### O3: Test resource names with default values

Resource identifiers in logs (for example, `gcp.resource.destination.id`) handle
defaulted or empty values, such as the default database, by rendering them the
way the service names the resource (for example, `databases/(default)`). Tests
include those values.

### O4: Log terminal errors consistently

Apply a single rule for logging terminal errors at the operation boundary, for
every error type, and document it in the DocC observability article (see
**Doc3**). Do not log some failures only because they happen to be a
`GoogleGax.RequestError`, and do not log the same failure twice (for example,
once by a read inside a transaction and again by the transaction runner).

## Idiomatic Swift

### I1: Follow the Swift API Design Guidelines

Follow the [Swift API Design Guidelines] and the [Google Swift Style Guide]. In
particular:

- Do not carry proto or other-language artifacts into Swift names: no `Type`
  suffixes (`MoreResultsType`), no `getMulti`-style names. Overload on argument
  types instead (`get(_ keys: [Key])`).
- Avoid abbreviations (`op`); write `comparison` or `combinator`.
- Use throwing computed properties (`var metrics: Metrics { get throws }`)
  rather than nullary throwing methods.
- Methods that return metadata alongside results use consistent names (for
  example, `getWithMetadata()` and `runQueryWithMetadata()`).

### I2: Acronyms are uniformly cased in hand-written code

New hand-written APIs follow the Swift API Design Guidelines and use uniformly
cased acronyms: `projectID`, `databaseID`, `allocateIDs()`, `endpointURL`, like
`swift-google-auth` (`clientID`, `quotaProjectID`). Generated code keeps the
casing of the source specification (see "Casing and naming conventions in
generated code" in ARCHITECTURE.md); this rule does not apply to it.

### I3: Use `Int` for counts, sizes, offsets, and limits

Proto `int32` and `int64` fields that represent counts, sizes, offsets, or
limits are `Int` in the hand-written API, converted at the wire boundary.
Changing the type later is a breaking change. Opaque server values (versions,
identifiers) may stay `Int64`.

### I4: Avoid overloads that differ only subtly

Do not add overloads that differ only by the return type of a closure parameter
(for example, a generic `T` overload and a `Void` overload of a transaction
runner), or only by `inout`. The overload that applies depends on details of the
call site, such as whether a single-expression closure returns a
`@discardableResult` value.

### I5: Use one level of options

Each options struct contains a single `GoogleGax.RequestOptions` field plus the
operation-specific fields. Do not nest options inside a field with the same
name, which leads to `options.request.request.attemptTimeout`.

### I6: Make invalid states unrepresentable

Prefer distinct types over runtime checks. For example, use a dedicated options
type for transactional reads, without a `readOptions` field, rather than
documenting that the field "must be `nil` inside a transaction" and throwing at
runtime.

### I7: Option and data types use `var`, `init()`, and `.with`

Option bags and data types follow "Request configuration and the `.with` idiom"
in ARCHITECTURE.md: `var` properties, a parameterless `init()` (or one that
takes only the required values), and `with(_:)`. Avoid long memberwise-style
initializers, and avoid `let` properties with throwing initializers: adding a
field later forces a new initializer overload.

## Required tests

In addition to the usual unit tests, new public APIs need these tests, in the
same pull request as the API:

- **T1: A request-level test for every option field.** Use a fake server or stub
  and assert that the request it receives reflects the option. If the option
  overrides a client-level default (database, namespace, timeout), test that the
  override wins, for every request kind that accepts it. Options with no wire
  effect (retry and backoff policies, attempt limits) are tested through their
  observable behavior, for example the number of attempts.
- **T2: A downstream mocking test.** A test file that uses plain
  `import <Module>` (never `@testable import`) implements a mock *and* a
  forwarding decorator of every public protocol, including streamed results.
- **T3: Failure tests for multi-RPC operations** (pagination, continuation
  batches, deferred lookups, transactions, resumable reads): a transient failure
  that recovers, retries running out, the behavior of the object after the
  terminal error, and the exact error type thrown in each case.
- **T4: Every public error case is produced by at least one test.**
- **T5: Cancellation tests** for APIs that hold server resources (transactions,
  sessions): cancelling the task has documented and tested behavior, for example
  a rollback.
- **T6: Observability tests** that check the log metadata, including defaulted
  or empty values (see **O3**).
- **T7: Equality tests** for types with inherited fields (see **E9**).

## Documentation

- **Doc1:** Every public symbol has a docstring, including members that
  implement protocol conformances (for example, `init(datastoreValue:)` on
  `Int`). Symbols that should not be documented are underscored and hidden (see
  **M1**).
- **Doc2:** Types with non-trivial usage (keys, entities, queries, filters,
  mutations, result sequences, options) have an inline `swift` code example or a
  snippet. A `@Snippet` attached to a symbol must call that symbol: do not reuse
  a snippet that does not show the API it documents.
- **Doc3:** The DocC catalog has articles on:
  - testing with mocks, using the service protocols,
  - the emulator, if the service has one,
  - retries and idempotency defaults,
  - error handling: the error types, which modules to `import` to match
    `GoogleGax.RequestError` codes, and examples for common codes,
  - observability (logging metadata),
  - each major feature (for example, transactions, pagination, typed entities).
- **Doc4:** Functions that run a closure more than once (transaction runners,
  retry helpers) warn that side effects outside the service must be idempotent.
  Batch operations that are not atomic say so. Multi-RPC operations document
  consistency: for example, whether all batches read from the same snapshot.
- **Doc5:** `- Throws:` sections name the concrete error types and how to match
  them.
- **Doc6:** Snippets and samples use application-defined errors; they never
  construct library errors. The README and the snippets show the same style.
- **Doc7:** Service limits are quoted from the proto comments, not restated from
  memory (see **E3**).

## Design documents

If the package has a design document in `doc/design/`, a change that diverges
from it updates the document in the same pull request. Any behavior promised in
the design document (for example, "transactions are rolled back when the closure
throws") must have a test. If the design document conflicts with this guide, the
guide wins for new public APIs: update the design document, or record the
exception and its rationale there.

## Review checklist

Use this list when reviewing a pull request that adds public APIs to a
hand-written package:

- [ ] Protocol requirements return named structs; no tuples; no server data is
  discarded; the same operation has the same result shape everywhere (**E1**).
- [ ] Requirements end with an operation-specific options struct; no positional
  knobs or `Bool` flags (**E2**).
- [ ] No client-side validation of service limits; decoding is lenient (**E3**).
- [ ] Initializers do not `throw` for validation; `throws`/`async` decided up
  front (**E4**).
- [ ] No `Codable` unless the encoding is canonical ProtoJSON (**E5**).
- [ ] Veneer loops use GAX `RetryPolicy` and `BackoffPolicy` (**E6**).
- [ ] Opaque tokens stay opaque (**E7**); every public error case is thrown and
  tested (**E8**); equality is defined for inherited fields (**E9**).
- [ ] Default implementations match the real client (**K1**); streamed results
  are mockable and wrappable with plain `import` (**K2**); minimal concurrency
  annotations on requirement closures (**K3**).
- [ ] Macro expansions call only underscored, hidden helpers; macros are in a
  separate package, or a separate product with a documented rationale (**M1**,
  **M2**).
- [ ] Logging keys match the generated layer; `rpc.method` is a real RPC;
  default values are tested (**O1**–**O4**).
- [ ] Names follow the Swift API Design Guidelines; acronyms are uniformly
  cased; `Int` for counts; one level of options (**I1**–**I7**).
- [ ] Tests **T1**–**T7** exist.
- [ ] Documentation **Doc1**–**Doc7** is complete.
- [ ] The design document matches the implementation.

[google swift style guide]: https://google.github.io/swift/
[swift api design guidelines]: https://www.swift.org/documentation/api-design-guidelines/
