# swift-nio-udp

A high-performance UDP transport layer built on SwiftNIO with support for unicast and multicast communication.

> **Release status.** Current release: `1.1.5`.

## Features

- **SwiftNIO Integration** - Built on Apple's SwiftNIO for efficient, non-blocking I/O
- **Multicast Support** - Join/leave multicast groups with IPv4 and IPv6 support
- **Zero-Copy** - Direct ByteBuffer integration for minimal memory copies
- **Modern Swift** - Uses Swift 6 concurrency with Mutex and Sendable types
- **AsyncStream** - Incoming datagrams delivered via AsyncStream with configurable buffering
- **Comprehensive Testing** - 54 correctness tests covering functionality and error handling

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+

## Installation

Add swift-nio-udp to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-nio-udp.git", from: "1.1.5")
]
```

Then add `NIOUDPTransport` to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: ["NIOUDPTransport"]
)
```

## Usage

### Unicast Communication

```swift
import NIOUDPTransport
import NIOCore

// Create configuration for unicast
let config = UDPConfiguration.unicast(port: 5000)

// Create transport
let transport = NIOUDPTransport(configuration: config)

// Start the transport
try await transport.start()

// Send data
let address = try SocketAddress(ipAddress: "192.168.1.100", port: 5001)
try await transport.send(Data("Hello, UDP!".utf8), to: address)

// Or send ByteBuffer directly (zero-copy)
var buffer = ByteBufferAllocator().buffer(capacity: 64)
buffer.writeString("Hello, ByteBuffer!")
try await transport.send(buffer, to: address)

// Receive incoming datagrams
for await datagram in transport.incomingDatagrams {
    print("Received from \(datagram.remoteAddress): \(datagram.buffer.readableBytes) bytes")
    // Access as Data if needed
    let data = datagram.data
}

// Shut down when done
try await transport.shutdown()
```

### Multicast Communication

```swift
import NIOUDPTransport
import NIOCore

// Create configuration for multicast (mDNS example)
let config = UDPConfiguration.multicast(port: 5353)

// Create transport
let transport = NIOUDPTransport(configuration: config)

// Start the transport
try await transport.start()

// Join multicast group
try await transport.joinMulticastGroup("224.0.0.251", on: nil)

// Send to multicast group
try await transport.sendMulticast(Data("Multicast message".utf8), to: "224.0.0.251", port: 5353)

// Receive multicast messages
for await datagram in transport.incomingDatagrams {
    print("Multicast from \(datagram.remoteAddress)")
}

// Leave group and shut down.
// (shutdown() also explicitly leaves any still-joined groups before
// closing the channel, so an explicit leave is optional.)
try await transport.leaveMulticastGroup("224.0.0.251", on: nil)
try await transport.shutdown()
```

### IPv6 Multicast

```swift
import NIOUDPTransport

// IPv6 multicast configuration
let config = UDPConfiguration(
    bindAddress: .ipv6Any(port: 5353),
    reuseAddress: true,
    reusePort: true
)

let transport = NIOUDPTransport(configuration: config)
try await transport.start()
try await transport.joinMulticastGroup("ff02::fb", on: nil)  // mDNS IPv6
```

### Batch Send

```swift
import NIOUDPTransport
import NIOCore

let transport = NIOUDPTransport(configuration: .unicast(port: 5000))
try await transport.start()

let a = try SocketAddress(ipAddress: "192.168.1.10", port: 5001)
let b = try SocketAddress(ipAddress: "192.168.1.11", port: 5001)

// Send multiple datagrams with a single flush (higher throughput).
// Per-datagram failures are aggregated and reported as
// UDPError.batchSendFailed; they are never silently dropped.
try await transport.sendBatch([
    (Data("one".utf8), a),
    (Data("two".utf8), b),
])
```

## API Reference

### Core Types

| Type | Description |
|------|-------------|
| `UDPTransport` | Protocol defining UDP transport operations |
| `MulticastCapable` | Protocol for multicast group management |
| `NIOUDPTransport` | SwiftNIO-based implementation |
| `UDPConfiguration` | Transport configuration options |
| `IncomingDatagram` | Received datagram with buffer and sender address |
| `UDPError` | Error types for UDP operations |

### UDPTransport Protocol

```swift
public protocol UDPTransport: Sendable {
    /// Local address the transport is bound to
    var localAddress: SocketAddress? { get async }

    /// Stream of incoming datagrams
    var incomingDatagrams: AsyncStream<IncomingDatagram> { get }

    /// Start the transport
    func start() async throws

    /// Shut down the transport
    func shutdown() async throws

    /// Send data to a remote address
    func send(_ data: Data, to address: SocketAddress) async throws

    /// Send ByteBuffer to a remote address (zero-copy)
    func send(_ buffer: ByteBuffer, to address: SocketAddress) async throws
}
```

### MulticastCapable Protocol

```swift
public protocol MulticastCapable: UDPTransport {
    /// Join a multicast group
    func joinMulticastGroup(_ group: String, on interface: String?) async throws

    /// Leave a multicast group
    func leaveMulticastGroup(_ group: String, on interface: String?) async throws

    /// Send data to a multicast group
    func sendMulticast(_ data: Data, to group: String, port: Int) async throws

    /// Send ByteBuffer to a multicast group (zero-copy)
    func sendMulticast(_ buffer: ByteBuffer, to group: String, port: Int) async throws
}
```

### IncomingDatagram

```swift
public struct IncomingDatagram: Sendable {
    /// The received data as ByteBuffer (zero-copy from NIO)
    public let buffer: ByteBuffer

    /// The sender's address
    public let remoteAddress: SocketAddress

    /// The received data as Data (convenience, copies bytes)
    public var data: Data { get }
}
```

## Configuration

### UDPConfiguration

```swift
// Unicast configuration (SWIM, custom protocols)
let unicastConfig = UDPConfiguration.unicast(port: 7946)

// Multicast configuration (mDNS, service discovery)
let multicastConfig = UDPConfiguration.multicast(port: 5353)

// Custom configuration
let customConfig = UDPConfiguration(
    bindAddress: .specific(host: "127.0.0.1", port: 8000),
    reuseAddress: true,
    reusePort: false,
    receiveBufferSize: 65536,
    sendBufferSize: 65536,
    maxDatagramSize: 65507,
    networkInterface: nil,
    streamBufferSize: 100
)
```

### Bind Address Options

| Option | Description |
|--------|-------------|
| `.any(port:)` | Bind to 0.0.0.0 (all interfaces) |
| `.ipv4Any(port:)` | Bind to 0.0.0.0 (IPv4 only) |
| `.ipv6Any(port:)` | Bind to :: (IPv6 only) |
| `.specific(host:port:)` | Bind to specific IP address |

## Error Handling

```swift
public enum UDPError: Error, Sendable {
    case notStarted                           // Transport not started
    case alreadyStarted                       // Transport already started
    case bindFailed(underlying: Error)        // Failed to bind to address
    case sendFailed(underlying: Error)        // Failed to send datagram
    case batchSendFailed(failedCount: Int, total: Int, firstError: Error) // One or more datagrams in a batch failed
    case invalidAddress(String)               // Invalid address format
    case datagramTooLarge(size: Int, max: Int) // Datagram exceeds max size
    case multicastError(String)               // Multicast operation failed
    case channelClosed                        // Channel closed unexpectedly
    case shutdownFailed(underlying: Error)    // Failed to shut down transport resources
    case timeout                              // Operation timed out
    case invalidConfiguration(String)         // Invalid configuration value
}
```

Failures while configuring the outbound multicast interface (`IP_MULTICAST_IF` /
`IPV6_MULTICAST_IF`) are surfaced as `UDPError.multicastError`: `start()` closes
the channel and throws rather than silently returning a transport that cannot
deliver multicast traffic.

## Performance

Benchmarks are an opt-in executable, separate from ordinary correctness tests.
The loopback lanes measure real UDP send submission and one-way delivery; they
do not label one-way traffic as a round trip.

```bash
SWIFT_NIO_UDP_ENABLE_BENCHMARKS=1 \
  TOOLCHAINS=org.swift.64202607231a \
  swift run -c release -debug-info-format none NIOUDPTransportBenchmarks
```

Release snapshot measured on 2026-08-14 with an Apple M4 Max, macOS 27.0,
and Swift `swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-07-23-a`. Values are the
median of three runs:

| Benchmark | Result |
|---|---:|
| Loopback send submission, 256 bytes | 27,184 datagrams/s; 6.96 MB/s |
| Loopback one-way delivery, 128 bytes | 26,802 datagrams/s; 0/5,000 lost |
| Batch send, 10 x 256 bytes | 37,445 datagrams/s; 9.59 MB/s |
| Batch vs. individual submission | 1.31x |
| Cached address lookup vs. parsing | 18.8x |

## Architecture

`NIOUDPTransport` implements the `UDPTransport` (+ `MulticastCapable`)
protocol over SwiftNIO's `DatagramBootstrap`, exposing a plain async/await
surface. It is used directly by host-side adapters in swift-SWIM and the P2P
stack. Protocol-neutral datagram contracts remain in `swift-networking`;
this package owns only the SwiftNIO-backed UDP implementation.

```
┌─────────────────────────────────────────────────────────────┐
│                     NIOUDPTransport                         │
│                   (final class, Sendable)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ State Machine   │    │ AsyncStream<IncomingDatagram>   │ │
│  │ (Mutex<State>)  │    │ with buffering policy           │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                   DatagramBootstrap                         │
│                     (SwiftNIO)                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ Channel Handler │    │ Multicast Group Management      │ │
│  │ (inbound msgs)  │    │ (join/leave)                    │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### State Machine

```
┌─────────┐     start()     ┌──────────┐
│ initial │ ───────────────► │ starting │
└─────────┘                  └────┬─────┘
                                  │ bound
                                  ▼
┌─────────┐   shutdown()    ┌──────────┐
│ stopped │ ◄─────────────── │ started  │
└─────────┘                  └────┬─────┘
     ▲                            │ shutdown()
     │                            ▼
     │                       ┌──────────┐
     └─────────────────────── │ stopping │
                              └──────────┘
```

### Thread Safety

| Component | Mechanism | Reason |
|-----------|-----------|--------|
| `NIOUDPTransport` | `final class` + `Mutex`, `@unchecked Sendable` | High-frequency state access |
| Internal state | `Mutex<State>` | Synchronized mutable state |
| Continuation flag | `Atomic<Bool>` | Lock-free termination check |

`@unchecked Sendable` is required because `State` stores non-Sendable
SwiftNIO values (`any Channel`, `NIONetworkDevice`); they are never exposed
directly and every access funnels through `Mutex<State>`. See
[`Sources/NIOUDPTransport/CONTEXT.md`](Sources/NIOUDPTransport/CONTEXT.md) for
the start/shutdown lifecycle and the load-bearing concurrency invariants.

## Testing

Performance benchmarks are not counted as tests and do not run during ordinary
test invocations.

The release gate runs 54 correctness tests across six suites:

| Suite | Tests | Coverage |
|-------|-------|----------|
| Configuration Validation | 10 | Bind addresses, buffer sizes, presets |
| Error Path | 9 | All error conditions |
| State Machine | 9 | Lifecycle, concurrency, transitions |
| Multicast | 9 | Join/leave/send for IPv4 and IPv6 |
| ByteBuffer API | 4 | Zero-copy send/receive |
| NIOUDPTransport | 13 | Core functionality |

Run tests:
```bash
TOOLCHAINS=org.swift.64202607231a \
  xcodebuild test \
  -scheme swift-nio-udp \
  -destination 'platform=macOS'
```

## Dependencies

- [swift-nio](https://github.com/apple/swift-nio) - Event-driven network framework

## License

MIT License
