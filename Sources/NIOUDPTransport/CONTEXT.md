# NIOUDPTransport — CONTEXT
Scope/role: the SwiftNIO-backed `UDPTransport` / `MulticastCapable` implementation and its lifecycle/concurrency invariants. Depended on by swift-mDNS, swift-SWIM, and the P2P stack's `P2PTransportNIO` adapter.
Last reviewed: 2026-06-25

`NIOUDPTransport` is a reference type that owns mutable NIO state behind a
single `Mutex<State>`. Read this before touching `start()`, `shutdown()`, the
`Status`/`generation` fields, or the incoming-datagram continuation: the
lifecycle is single-shot and the concurrency is hand-checked, so small edits
can reintroduce a use-after-shutdown, a double-finish, or a leaked channel.

## Contracts (the load-bearing rules)
- All mutable state lives in `State` and is reached ONLY through `state.withLock`.
  `State` holds non-Sendable NIO values (`any Channel`, `NIONetworkDevice`),
  so the type is `@unchecked Sendable`; correctness depends on never exposing
  those values outside the lock and never adding unsynchronized shared state.
- The transport is single-shot: `start()` succeeds only from `.initial`, and
  once `shutdown()` runs (`.stopping`/`.stopped`) it cannot be restarted —
  callers create a new instance instead.
- `incomingDatagrams` is the one buffered (`.bufferingNewest`) stream; the hot
  receive path yields through `incomingContinuation` without taking the lock,
  guarded only by the `continuationFinished` atomic.
- The event-loop group is shut down in `shutdown()` only when this instance
  created it (`ownsEventLoopGroup`); an injected group is left for its owner.

## Invariants (must hold; tests guard them)
- `generation` increments on every `start()`/`shutdown()` transition and is the
  arbiter for the start-vs-shutdown race: if `shutdown()` runs while
  `createChannel()` is in flight, `start()` sees the changed generation/status
  and closes the freshly bound channel rather than installing it (no leaked or
  orphaned channel).
- Shutdown finishes the stream exactly once: `continuationFinished` is stored
  `true` (release) BEFORE `incomingContinuation.finish()`, so no datagram is
  yielded after finish and the stream never double-finishes.
- Multicast leave on shutdown is best-effort and never promoted to a thrown
  error: closing the channel releases kernel membership unconditionally, so a
  rejected leave is logged, not surfaced. `shutdownFailed` is reserved for
  failures that actually leak resources (channel close / event-loop shutdown).
- Send fails closed: `send`/`sendBatch` throw `UDPError.notStarted` when there
  is no started channel and `datagramTooLarge` past `maxDatagramSize`; batch
  failures aggregate into `batchSendFailed` and are never silently dropped.

## Dependencies & seams
- SwiftNIO only (`NIOCore` + `NIOPosix`). The inbound `DatagramHandler` holds a
  `weak` back-reference to the transport and forwards envelopes via the
  continuation; it is also `@unchecked Sendable` for the same reason as the
  transport.

## Build
```bash
# Host build + tests (default toolchain)
swift build
swift test
```
This module is host-only (SwiftNIO is not Embedded); there is no Embedded build.
