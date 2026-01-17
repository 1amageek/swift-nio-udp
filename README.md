# swift-nio-udp

A high-performance UDP transport layer built on SwiftNIO with support for unicast and multicast communication.

## Features

- **SwiftNIO Integration** - Built on Apple's SwiftNIO for efficient, non-blocking I/O
- **Multicast Support** - Join/leave multicast groups with IPv4 and IPv6 support
- **Zero-Copy** - Direct ByteBuffer integration for minimal memory copies
- **Modern Swift** - Uses Swift 6 concurrency with actors, Mutex, and Sendable types
- **AsyncStream** - Incoming datagrams delivered via AsyncStream with configurable buffering

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+

## Installation

Add swift-nio-udp to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-nio-udp.git", from: "1.0.0")
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

// Create configuration for unicast
let config = UDPConfiguration.unicast(port: 5000)

// Create transport
let transport = try await NIOUDPTransport(configuration: config)

// Start the transport
try await transport.start()

// Send data
let data = ByteBuffer(string: "Hello, UDP!")
try await transport.send(data, to: SocketAddress(ipAddress: "192.168.1.100", port: 5001))

// Receive incoming datagrams
for await datagram in transport.incomingDatagrams {
    print("Received from \(datagram.remoteAddress): \(datagram.data.readableBytes) bytes")
}

// Stop when done
await transport.stop()
```

### Multicast Communication

```swift
import NIOUDPTransport

// Create configuration for multicast (mDNS example)
let config = UDPConfiguration.multicast(
    group: "224.0.0.251",
    port: 5353
)

// Create transport
let transport = try await NIOUDPTransport(configuration: config)

// Start the transport
try await transport.start()

// Join multicast group
try await transport.joinGroup("224.0.0.251")

// Send to multicast group
let message = ByteBuffer(string: "Multicast message")
try await transport.send(message, to: SocketAddress(ipAddress: "224.0.0.251", port: 5353))

// Receive multicast messages
for await datagram in transport.incomingDatagrams {
    print("Multicast from \(datagram.remoteAddress)")
}

// Leave group and stop
try await transport.leaveGroup("224.0.0.251")
await transport.stop()
```

### IPv6 Multicast

```swift
import NIOUDPTransport

// IPv6 multicast configuration
let config = UDPConfiguration.multicast(
    group: "ff02::fb",  // mDNS IPv6 multicast address
    port: 5353
)

let transport = try await NIOUDPTransport(configuration: config)
try await transport.start()
try await transport.joinGroup("ff02::fb")
```

## API Reference

### Core Types

| Type | Description |
|------|-------------|
| `UDPTransport` | Protocol defining UDP transport operations |
| `MulticastCapable` | Protocol for multicast group management |
| `NIOUDPTransport` | SwiftNIO-based implementation |
| `UDPConfiguration` | Transport configuration options |
| `IncomingDatagram` | Received datagram with data and sender address |
| `UDPError` | Error types for UDP operations |

### UDPTransport Protocol

```swift
public protocol UDPTransport: Sendable {
    /// Local address the transport is bound to
    var localAddress: SocketAddress? { get async }

    /// Stream of incoming datagrams
    var incomingDatagrams: AsyncStream<IncomingDatagram> { get async }

    /// Start the transport
    func start() async throws

    /// Stop the transport
    func stop() async

    /// Send data to a remote address
    func send(_ data: ByteBuffer, to remoteAddress: SocketAddress) async throws
}
```

### MulticastCapable Protocol

```swift
public protocol MulticastCapable: Sendable {
    /// Join a multicast group
    func joinGroup(_ group: String) async throws

    /// Leave a multicast group
    func leaveGroup(_ group: String) async throws
}
```

### IncomingDatagram

```swift
public struct IncomingDatagram: Sendable {
    /// The received data
    public let data: ByteBuffer

    /// The sender's address
    public let remoteAddress: SocketAddress
}
```

## Configuration

### UDPConfiguration

```swift
// Unicast configuration
let unicastConfig = UDPConfiguration.unicast(
    host: "0.0.0.0",  // Bind address (default: "0.0.0.0")
    port: 5000        // Bind port
)

// Multicast configuration
let multicastConfig = UDPConfiguration.multicast(
    group: "224.0.0.251",  // Multicast group address
    port: 5353             // Port number
)
```

### Bind Address Options

| Option | Description |
|--------|-------------|
| `.anyIPv4` | Bind to 0.0.0.0 (all IPv4 interfaces) |
| `.anyIPv6` | Bind to :: (all IPv6 interfaces) |
| `.localhost` | Bind to 127.0.0.1 |
| `.localhostIPv6` | Bind to ::1 |
| `.specific(String)` | Bind to specific IP address |

## Error Handling

```swift
public enum UDPError: Error {
    case notStarted
    case alreadyStarted
    case bindFailed(underlying: Error)
    case sendFailed(underlying: Error)
    case invalidAddress(String)
    case multicastJoinFailed(group: String, underlying: Error)
    case multicastLeaveFailed(group: String, underlying: Error)
    case channelClosed
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     NIOUDPTransport                         │
│                        (actor)                              │
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
┌─────────┐     stop()      ┌──────────┐
│ stopped │ ◄─────────────── │ started  │
└─────────┘                  └────┬─────┘
     ▲                            │ stop()
     │                            ▼
     │                       ┌──────────┐
     └─────────────────────── │ stopping │
                              └──────────┘
```

## Thread Safety

| Component | Mechanism | Reason |
|-----------|-----------|--------|
| `NIOUDPTransport` | `actor` | User-facing API with async operations |
| Internal state | `Mutex<State>` | High-frequency state access |
| Continuation flag | `Atomic<Bool>` | Lock-free termination check |

## Dependencies

- [swift-nio](https://github.com/apple/swift-nio) - Event-driven network framework

## License

MIT License
