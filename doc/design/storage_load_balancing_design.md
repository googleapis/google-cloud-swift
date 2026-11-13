# Google Cloud Storage HTTP Connection Pool & Load Balancing Design

**Issue:** [#651](https://github.com/googleapis/google-cloud-swift/issues/651)
**Package:** `GoogleCloudStorage`

## 1. Problem Statement

`StorageClient` executes JSON/REST data-plane requests (`writeObject` and `readObject`) through `GoogleGax._HTTPClient`, which by default delegates to a single `AsyncHTTPClient.HTTPClient` instance (`HTTPClientHolder`).

Inside `AsyncHTTPClient`'s HTTP/2 state machine (`HTTPConnectionPool+HTTP2StateMachine`), when no explicit event loop affinity (`requiredEventLoop`) is forced, the pool maintains **at most one active HTTP/2 TCP+TLS connection per remote host** (`storage.googleapis.com`). Under high concurrency or large object transfers from Compute Engine VMs with high NIC bandwidth (25–100+ Gbps), a single HTTP/2 connection encounters three bottlenecks:

1. **Stream concurrency cap:** Servers typically advertise `SETTINGS_MAX_CONCURRENT_STREAMS` around 100. Concurrent uploads and downloads above that limit queue inside `AsyncHTTPClient` waiting for an open stream ID.
2. **Per-connection / stream flow control:** A single TCP socket and 64 KiB initial HTTP/2 window serialize packet loss recovery and cap achievable throughput per connection.
3. **Single-event-loop affinity:** All TLS encryption, frame parsing, and buffer copies for the single HTTP/2 connection execute on one NIO `EventLoop` thread, saturating one CPU core while other cores remain idle.

## 2. Architecture Overview

Rather than creating multiple `StorageClient` instances at the application layer—which would duplicate `GoogleAuth.Credentials` token caches, quota project configuration, and retry policies—we implement connection-pool load balancing inside `GoogleCloudStorage` behind `GoogleGax._HTTPClientProtocol`:

```text
StorageClient
  └─ GoogleGax._HTTPClient (shared Credentials/TokenCache, endpoint, headers, logger)
       └─ _HTTPClientProtocol transport:
            ├─ RoundRobinHTTPClient (default, when poolSize > 1)
            ├─ P2CHTTPClient (when poolSize > 1 and loadBalancer == .p2c)
            └─ clients[0] directly (when poolSize == 1)
                 └─ StorageHTTPClientHolder[0..<poolSize]
                      └─ AsyncHTTPClient.HTTPClient() (shared defaultEventLoopGroup)
```

### Key Design Decisions

1. **Shared `GoogleGax._HTTPClient` and Authentication:**
   `StorageClient` resolves `GoogleAuth.Credentials` once (when `options.client.credentials == nil`) and injects the pooled `_HTTPClientProtocol` transport into a single `GoogleGax._HTTPClient`. Every pooled connection slot therefore shares the same OAuth2 `TokenCache` and request header configuration.
2. **Shared `EventLoopGroup`:**
   Each `StorageHTTPClientHolder` constructs `AsyncHTTPClient.HTTPClient()` with default settings, which reuses `HTTPClient.defaultEventLoopGroup` across all holders while giving each holder an independent `HTTPConnectionPool.Manager` (and thus an independent HTTP/2 connection to `storage.googleapis.com`). Each holder shuts down its inner `HTTPClient` asynchronously in `deinit`.
   Because endpoint validation (`_HTTPClient.validateEndpoint`) runs before allocating the pool holders, invalid endpoints fail fast without spawning temporary `HTTPClient` instances.
3. **Pool Size Heuristic:**
   `StorageClientOptions.resolveConnectionPoolSize(_:coreCount:)` computes the number of HTTP client slots as:
   - Explicit override: `max(1, configured)` when `connectionPoolSize != nil`.
   - Default (`nil`): `min(max(4, NIOCore.System.coreCount), 16)` (clamped to `[4, 16]` across common workstation and GCE machine types).
4. **Public Configuration on `StorageClientOptions`:**
   Because the two load-balancing algorithms exhibit meaningfully different median vs. tail latency
   tradeoffs across uploads and downloads, `StorageClientOptions` exposes both pool sizing and
   load-balancer selection publicly without leaking `AsyncHTTPClient` types:
   - `public var connectionPoolSize: Int? = nil`
   - `public var loadBalancer: StorageLoadBalancer = .roundRobin`

## 3. Load Balancing Strategies

When the resolved pool size is `1`, `StorageClient.makeTransport` bypasses the balancer wrapper and returns the single holder directly. When the pool size is `> 1`, two strategies are supported.

### 3.1 Round-Robin (`RoundRobinHTTPClient`)

`RoundRobinHTTPClient` uses a single lock-free `Synchronization.Atomic<UInt64>` counter:

```swift
let index = Int(
  self.nextIndex.wrappingAdd(1, ordering: .relaxed).oldValue % UInt64(self.clients.count)
)
```

- **Strengths:** Zero lock contention, zero per-response wrapper allocation, and uniform request-count distribution under identical request durations.
- **Weaknesses:** Blind to actual in-flight load. Under mixed object sizes or heterogeneous workloads (such as W1R3 mixed metadata + streaming reads + chunked resumable uploads, or partial cancellation), long-lived transfers stack up on slots that happen to be hit at a stride multiple of `poolSize`, increasing tail latency.

### 3.2 Power of Two Random Choices (`P2CHTTPClient`)

Inspired by [Tower's P2C load balancer](https://docs.rs/tower/latest/tower/balance/p2c/index.html) (`tower::balance::p2c`), `P2CHTTPClient` balances by **active in-flight requests (`PendingRequests`)**:

1. **Selection (`acquireSlot`):** Inside `Mutex<State>`, sample two distinct indices `a != b` uniformly from `0..<count` using an internal `SplitMix64` PRNG (also seedable in tests):
   - Sample `a` uniformly in `0..<count`.
   - Sample `rawB` uniformly in `0..<(count - 1)`, then set `b = rawB >= a ? rawB + 1 : rawB`.
   - Select the slot with fewer active requests (`inFlightCounts[a] <= inFlightCounts[b] ? a : b`) and increment its count immediately before issuing the request.
2. **Why `PendingRequests` over `PeakEwma`:**
   - **Correctness first:** Active concurrency directly prevents piling onto connections already occupied by slow/large reads or stalled HTTP/2 streams without requiring tuning of EWMA decay windows or handling response-body-vs-header timing skew.
   - **Header-to-body lifecycle:** `HTTPClient.execute` resolves as soon as response headers arrive, **before** the response body stream finishes downloading. Incrementing on `execute` and decrementing when headers return would ignore active multi-megabyte streaming downloads.

To track the full lifecycle safely without leaks under cancellation or early drop, `P2CHTTPClient` pairs each acquired slot with a single-release `LoadLease` (`Atomic<Bool>` compare-exchange) wrapped inside `TrackedResponseBody`:

| Event | When It Occurs | Load Lease Behavior |
| :--- | :--- | :--- |
| Pre-header error | `clients[slotIndex].execute` throws before returning headers | `lease.release()` called immediately in `catch` |
| Stream EOF | `TrackedResponseBody.AsyncIterator.next()` returns `nil` | `lease.release()` called immediately (before outer `HTTPClientResponse` drops) |
| Mid-stream error | `TrackedResponseBody.AsyncIterator.next()` throws | `lease.release()` called immediately in `catch` |
| Cancelled / unread body | Caller cancels task or drops `HTTPClientResponse` without draining EOF | `LoadLease.deinit` invokes `lease.release()` once |

All transitions go through the same atomic idempotent `release()`, guaranteeing each acquired request decrements `inFlightCounts[slotIndex]` **exactly once**.

## 4. Benchmarking & Experimental Results

To determine empirically on real Compute Engine VMs how `P2CHTTPClient`'s `PendingRequests` tracking compares against `RoundRobinHTTPClient`'s lock-free distribution despite the `Mutex` and `TrackedResponseBody` overhead:

1. `StorageW1R3` adds `--load-balancer <p2c|round-robin|random>` (default: `random`) and `--connection-pool-size <N>` (default: SDK default).
2. In `--load-balancer random` mode, `BenchmarkRunner` lazily creates one pooled `StorageClient` set per strategy (both configured with identical `--connection-pool-size` and shared `Credentials`) and randomly selects `.p2c` or `.roundRobin` independently for each benchmark iteration in the **same process on the same VM**. Running both strategies interleaved avoids time-of-day, network-topology, or cold-VM bias.
3. Each CSV `Sample` records `lb=p2c` or `lb=round-robin` inside the existing `Details` column (e.g., `lb=p2c;chunkSize=4194304`), preserving backward compatibility with existing BigQuery schemas and ingestion scripts.
4. Tail latency (`p50`, `p95`, `p99`, `max`) and effective throughput are compared per `(operation, transfer_size, pool_size, lb)` in BigQuery.

In our experiments, the `.p2c` load balancer improves median latency for uploads, and the tail latency for both uploads and downloads, whereas the `.roundRobin` load balancer offers better median latency for downloads. Both strategies are therefore retained in `StorageLoadBalancer`, with `.roundRobin` as the default and `.p2c` selectable via `StorageClientOptions`.
