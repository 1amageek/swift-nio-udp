# swift-nio-udp Design

## Overview

Cross-platform UDP transport library built on SwiftNIO, providing both unicast and multicast support for use by swift-mDNS and swift-SWIM.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
│              (swift-mDNS, swift-SWIM, etc.)                 │
└─────────────────────────────┬───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                    UDPTransport (protocol)                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ send(_ data: Data, to: SocketAddress) async throws      ││
│  │ send(_ buffer: ByteBuffer, to: SocketAddress) async ...  ││
│  │ incomingDatagrams: AsyncStream<IncomingDatagram>        ││
│  │ start() async throws                                     ││
│  │ shutdown() async throws                                  ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────┘
                              │ implements
┌─────────────────────────────▼───────────────────────────────┐
│                  NIOUDPTransport (class)                     │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ DatagramBootstrap                                        ││
│  │ + MulticastCapable                                       ││
│  │ + async/await wrapper                                    ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────┬───────────────────────────────┘
                              │ uses
┌─────────────────────────────▼───────────────────────────────┐
│                        SwiftNIO                              │
│           (DatagramChannel, EventLoopGroup)                  │
└─────────────────────────────────────────────────────────────┘
```

## Module Structure

```
swift-nio-udp/
├── Package.swift
├── DESIGN.md
├── Sources/
│   └── NIOUDPTransport/
│       ├── UDPTransport.swift         # Protocol definitions
│       ├── NIOUDPTransport.swift      # SwiftNIO implementation (incl. multicast)
│       ├── UDPConfiguration.swift     # Configuration
│       ├── UDPError.swift             # Error type
│       └── AddressHelpers.swift       # Address conversion utilities
│
└── Tests/
    └── NIOUDPTransportTests/
        ├── NIOUDPTransportTests.swift
        ├── MulticastTests.swift
        └── AddressHelpersTests.swift
```

## Core Types

### 1. UDPTransport Protocol

```swift
import Foundation
import NIOCore

/// Cross-platform UDP transport protocol.
///
/// Provides a simple async/await interface for UDP communication.
public protocol UDPTransport: Sendable {

    /// The local address this transport is bound to.
    var localAddress: SocketAddress? { get async }

    /// Stream of incoming datagrams.
    ///
    /// Each element carries the received bytes and the sender address.
    var incomingDatagrams: AsyncStream<IncomingDatagram> { get }

    /// Sends data to the specified address.
    ///
    /// - Parameters:
    ///   - data: The data to send
    ///   - address: The destination address
    /// - Throws: `UDPError` if the send fails
    func send(_ data: Data, to address: SocketAddress) async throws

    /// Sends a ByteBuffer to the specified address (zero-copy).
    ///
    /// - Parameters:
    ///   - buffer: The buffer to send
    ///   - address: The destination address
    /// - Throws: `UDPError` if the send fails
    func send(_ buffer: ByteBuffer, to address: SocketAddress) async throws

    /// Starts the transport.
    ///
    /// Binds to the configured address and begins receiving datagrams.
    func start() async throws

    /// Shuts the transport down.
    ///
    /// Closes the socket and stops receiving datagrams.
    func shutdown() async throws
}

/// An incoming datagram with its bytes and sender address.
public struct IncomingDatagram: Sendable {
    /// The received data as ByteBuffer (zero-copy from NIO).
    public let buffer: ByteBuffer

    /// The remote address that sent this datagram.
    public let remoteAddress: SocketAddress

    public init(buffer: ByteBuffer, remoteAddress: SocketAddress) {
        self.buffer = buffer
        self.remoteAddress = remoteAddress
    }

    /// The received data as Data (convenience, copies bytes).
    @inlinable
    public var data: Data {
        Data(buffer: buffer)
    }
}
```

### 2. MulticastCapable Protocol

```swift
/// Extension protocol for multicast support.
///
/// Used by mDNS and other multicast-based protocols.
public protocol MulticastCapable: UDPTransport {

    /// Joins a multicast group.
    ///
    /// - Parameters:
    ///   - group: The multicast group address (e.g., "224.0.0.251")
    ///   - interface: The network interface name (nil for default)
    func joinMulticastGroup(
        _ group: String,
        on interface: String?
    ) async throws

    /// Leaves a multicast group.
    ///
    /// - Parameters:
    ///   - group: The multicast group address
    ///   - interface: The network interface name (nil for default)
    func leaveMulticastGroup(
        _ group: String,
        on interface: String?
    ) async throws

    /// Sends data to a multicast group.
    ///
    /// - Parameters:
    ///   - data: The data to send
    ///   - group: The multicast group address
    ///   - port: The destination port
    func sendMulticast(
        _ data: Data,
        to group: String,
        port: Int
    ) async throws

    /// Sends a ByteBuffer to a multicast group (zero-copy).
    ///
    /// - Parameters:
    ///   - buffer: The buffer to send
    ///   - group: The multicast group address
    ///   - port: The destination port
    func sendMulticast(
        _ buffer: ByteBuffer,
        to group: String,
        port: Int
    ) async throws
}
```

### 3. UDPConfiguration

```swift
/// Configuration for UDP transport.
public struct UDPConfiguration: Sendable {

    /// The address to bind to.
    public let bindAddress: BindAddress

    /// Whether to enable address reuse (SO_REUSEADDR).
    public let reuseAddress: Bool

    /// Whether to enable port reuse (SO_REUSEPORT).
    public let reusePort: Bool

    /// Receive buffer size in bytes.
    public let receiveBufferSize: Int

    /// Send buffer size in bytes.
    public let sendBufferSize: Int

    /// Maximum datagram size.
    public let maxDatagramSize: Int

    /// Network interface to bind to (nil for all interfaces).
    public let networkInterface: String?

    /// Buffering capacity of the incoming-datagram AsyncStream.
    public let streamBufferSize: Int

    public enum BindAddress: Sendable {
        /// Bind to any address on the specified port.
        case any(port: Int)

        /// Bind to a specific address and port.
        case specific(host: String, port: Int)

        /// Bind to IPv4 any address.
        case ipv4Any(port: Int)

        /// Bind to IPv6 any address.
        case ipv6Any(port: Int)
    }

    /// Default configuration for unicast UDP.
    public static func unicast(port: Int) -> UDPConfiguration {
        UDPConfiguration(
            bindAddress: .any(port: port),
            reuseAddress: true,
            reusePort: false,
            receiveBufferSize: 65536,
            sendBufferSize: 65536,
            maxDatagramSize: 65507,
            networkInterface: nil,
            streamBufferSize: 100
        )
    }

    /// Default configuration for multicast UDP (e.g., mDNS).
    public static func multicast(port: Int) -> UDPConfiguration {
        UDPConfiguration(
            bindAddress: .any(port: port),
            reuseAddress: true,
            reusePort: true,  // Required for multicast
            receiveBufferSize: 65536,
            sendBufferSize: 65536,
            maxDatagramSize: 65507,
            networkInterface: nil,
            streamBufferSize: 200
        )
    }
}
```

### 4. UDPError

```swift
/// Errors that can occur during UDP operations.
///
/// Conforms to `CustomStringConvertible` for human-readable descriptions.
public enum UDPError: Error, Sendable {
    /// Transport is not started.
    case notStarted

    /// Transport is already started.
    case alreadyStarted

    /// Failed to bind to address.
    case bindFailed(underlying: Error)

    /// Failed to send datagram.
    case sendFailed(underlying: Error)

    /// A batch send partially or fully failed.
    case batchSendFailed(failedCount: Int, total: Int, firstError: Error)

    /// Invalid address format.
    case invalidAddress(String)

    /// Datagram too large.
    case datagramTooLarge(size: Int, max: Int)

    /// Multicast operation failed.
    case multicastError(String)

    /// Channel closed unexpectedly.
    case channelClosed

    /// Failed to shut the transport down.
    case shutdownFailed(underlying: Error)

    /// Operation timed out.
    case timeout

    /// The supplied configuration is invalid.
    case invalidConfiguration(String)
}

extension UDPError: CustomStringConvertible {
    public var description: String { /* human-readable per case */ }
}
```

### 5. NIOUDPTransport Implementation

```swift
import NIOCore
import NIOPosix
import Synchronization

/// SwiftNIO-based UDP transport implementation.
public final class NIOUDPTransport: UDPTransport, MulticastCapable, @unchecked Sendable {

    private let configuration: UDPConfiguration
    private let eventLoopGroup: EventLoopGroup
    private let ownsEventLoopGroup: Bool

    private let state: Mutex<State>
    private let incomingContinuation: AsyncStream<IncomingDatagram>.Continuation

    public let incomingDatagrams: AsyncStream<IncomingDatagram>

    private struct State {
        var channel: (any Channel)?
        var status: Status = .initial
        var generation: UInt64 = 0
        var joinedGroups: Set<String> = []
        var deviceCache: [String: NIONetworkDevice] = [:]

        enum Status {
            case initial
            case starting
            case started
            case stopping
            case stopped
        }
    }

    // MARK: - Initialization

    /// Creates a new UDP transport with the given configuration.
    ///
    /// - Parameters:
    ///   - configuration: UDP configuration
    ///   - eventLoopGroup: Optional event loop group (creates one if nil)
    public init(
        configuration: UDPConfiguration,
        eventLoopGroup: EventLoopGroup? = nil
    ) {
        self.configuration = configuration

        if let group = eventLoopGroup {
            self.eventLoopGroup = group
            self.ownsEventLoopGroup = false
        } else {
            self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.ownsEventLoopGroup = true
        }

        self.state = Mutex(State())

        var continuation: AsyncStream<IncomingDatagram>.Continuation!
        self.incomingDatagrams = AsyncStream(
            bufferingPolicy: .bufferingNewest(configuration.streamBufferSize)
        ) { cont in
            continuation = cont
        }
        self.incomingContinuation = continuation
    }

    deinit {
        if ownsEventLoopGroup {
            try? eventLoopGroup.syncShutdownGracefully()
        }
    }

    // MARK: - UDPTransport

    public var localAddress: SocketAddress? {
        get async {
            state.withLock { $0.channel?.localAddress }
        }
    }

    public func start() async throws {
        let alreadyStarted = state.withLock { state in
            if state.status == .started || state.status == .starting { return true }
            state.status = .starting
            state.generation &+= 1
            return false
        }

        guard !alreadyStarted else {
            throw UDPError.alreadyStarted
        }

        do {
            let channel = try await createChannel()
            state.withLock {
                $0.channel = channel
                $0.status = .started
            }
        } catch {
            state.withLock { $0.status = .stopped }
            throw UDPError.bindFailed(underlying: error)
        }
    }

    public func shutdown() async throws {
        let channel = state.withLock { state in
            state.status = .stopping
            let ch = state.channel
            state.channel = nil
            state.joinedGroups.removeAll()
            state.deviceCache.removeAll()
            return ch
        }

        if let channel {
            try await channel.close()
        }

        incomingContinuation.finish()

        state.withLock { $0.status = .stopped }

        if ownsEventLoopGroup {
            try await eventLoopGroup.shutdownGracefully()
        }
    }

    public func send(_ data: Data, to address: SocketAddress) async throws {
        let buffer = ByteBuffer.from(data, allocator: ByteBufferAllocator())
        try await send(buffer, to: address)
    }

    public func send(_ buffer: ByteBuffer, to address: SocketAddress) async throws {
        guard let channel = state.withLock({ $0.channel }) else {
            throw UDPError.notStarted
        }

        guard buffer.readableBytes <= configuration.maxDatagramSize else {
            throw UDPError.datagramTooLarge(
                size: buffer.readableBytes,
                max: configuration.maxDatagramSize
            )
        }

        let envelope = AddressedEnvelope(remoteAddress: address, data: buffer)
        try await channel.writeAndFlush(envelope)
    }

    /// Sends a batch of buffered datagrams, reporting partial failures.
    public func sendBatch(
        _ datagrams: [(ByteBuffer, SocketAddress)]
    ) async throws { /* ... aggregates failures into UDPError.batchSendFailed ... */ }

    /// Sends a batch of Data datagrams (convenience overload).
    public func sendBatch(
        _ datagrams: [(Data, SocketAddress)]
    ) async throws { /* ... */ }

    // MARK: - MulticastCapable

    public func joinMulticastGroup(
        _ group: String,
        on interface: String?
    ) async throws {
        guard let channel = state.withLock({ $0.channel }) else {
            throw UDPError.notStarted
        }

        guard let datagramChannel = channel as? any MulticastChannel else {
            throw UDPError.multicastError("Channel does not support multicast")
        }

        do {
            let groupAddress = try SocketAddress(ipAddress: group, port: 0)

            if let interfaceName = interface ?? configuration.networkInterface {
                // Find the interface
                let device = try System.enumerateDevices().first {
                    $0.name == interfaceName
                }
                if let device {
                    try await datagramChannel.joinGroup(groupAddress, device: device).get()
                } else {
                    throw UDPError.multicastError("Interface not found: \(interfaceName)")
                }
            } else {
                try await datagramChannel.joinGroup(groupAddress).get()
            }

            state.withLock { $0.joinedGroups.insert(group) }
        } catch let error as UDPError {
            throw error
        } catch {
            throw UDPError.multicastError("Failed to join group: \(error)")
        }
    }

    public func leaveMulticastGroup(
        _ group: String,
        on interface: String?
    ) async throws {
        guard let channel = state.withLock({ $0.channel }) else {
            throw UDPError.notStarted
        }

        guard let datagramChannel = channel as? any MulticastChannel else {
            throw UDPError.multicastError("Channel does not support multicast")
        }

        do {
            let groupAddress = try SocketAddress(ipAddress: group, port: 0)

            if let interfaceName = interface ?? configuration.networkInterface {
                let device = try System.enumerateDevices().first {
                    $0.name == interfaceName
                }
                if let device {
                    try await datagramChannel.leaveGroup(groupAddress, device: device).get()
                }
            } else {
                try await datagramChannel.leaveGroup(groupAddress).get()
            }

            state.withLock { $0.joinedGroups.remove(group) }
        } catch {
            throw UDPError.multicastError("Failed to leave group: \(error)")
        }
    }

    public func sendMulticast(
        _ data: Data,
        to group: String,
        port: Int
    ) async throws {
        let address = try SocketAddress(ipAddress: group, port: port)
        try await send(data, to: address)
    }

    public func sendMulticast(
        _ buffer: ByteBuffer,
        to group: String,
        port: Int
    ) async throws {
        let address = try SocketAddress(ipAddress: group, port: port)
        try await send(buffer, to: address)
    }

    // MARK: - Private

    private func createChannel() async throws -> Channel {
        let bootstrap = DatagramBootstrap(group: eventLoopGroup)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: configuration.reuseAddress ? 1 : 0)
            .channelOption(ChannelOptions.recvAllocator, value: FixedSizeRecvByteBufferAllocator(capacity: configuration.receiveBufferSize))
            .channelInitializer { [weak self] channel in
                channel.pipeline.addHandler(DatagramHandler(transport: self))
            }

        // Apply SO_REUSEPORT if needed (for multicast)
        let bootstrap2 = configuration.reusePort
            ? bootstrap.channelOption(ChannelOptions.socketOption(.so_reuseport), value: 1)
            : bootstrap

        // Bind to address
        let bindAddress: SocketAddress
        switch configuration.bindAddress {
        case .any(let port):
            bindAddress = try SocketAddress(ipAddress: "0.0.0.0", port: port)
        case .specific(let host, let port):
            bindAddress = try SocketAddress(ipAddress: host, port: port)
        case .ipv4Any(let port):
            bindAddress = try SocketAddress(ipAddress: "0.0.0.0", port: port)
        case .ipv6Any(let port):
            bindAddress = try SocketAddress(ipAddress: "::", port: port)
        }

        return try await bootstrap2.bind(to: bindAddress).get()
    }

    /// Called by DatagramHandler when a datagram is received.
    fileprivate func handleIncomingDatagram(_ datagram: IncomingDatagram) {
        incomingContinuation.yield(datagram)
    }
}

// MARK: - Channel Handler

private final class DatagramHandler: ChannelInboundHandler {
    typealias InboundIn = AddressedEnvelope<ByteBuffer>

    private weak var transport: NIOUDPTransport?

    init(transport: NIOUDPTransport?) {
        self.transport = transport
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let envelope = unwrapInboundIn(data)

        // Keep the NIO ByteBuffer (zero-copy); `data` is exposed as a
        // convenience computed property on IncomingDatagram.
        let datagram = IncomingDatagram(
            buffer: envelope.data,
            remoteAddress: envelope.remoteAddress
        )

        transport?.handleIncomingDatagram(datagram)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        // Log error but keep channel open
        print("UDP channel error: \(error)")
    }
}
```

### 6. Address Helpers

```swift
import NIOCore

extension SocketAddress {
    /// Creates a SocketAddress from a "host:port" string.
    public init(hostPort: String) throws {
        let parts = hostPort.split(separator: ":")
        guard parts.count == 2,
              let port = Int(parts[1]) else {
            throw UDPError.invalidAddress(hostPort)
        }
        try self.init(ipAddress: String(parts[0]), port: port)
    }

    /// Returns a cached SocketAddress for a "host:port" string, parsing and
    /// caching on first use (bounded cache).
    public static func cached(hostPort: String) throws -> SocketAddress

    /// Clears the address cache used by `cached(hostPort:)`.
    public static func clearCache()

    /// The IP address portion of this socket address, if any.
    public var host: String? { self.ipAddress }

    /// Returns the address as "host:port" string.
    public var hostPortString: String? {
        switch self {
        case .v4(let addr):
            return "\(addr.host):\(port ?? 0)"
        case .v6(let addr):
            return "[\(addr.host)]:\(port ?? 0)"
        case .unixDomainSocket:
            return nil
        @unknown default:
            return nil
        }
    }
}

extension ByteBuffer {
    /// Builds a ByteBuffer from Data using the given allocator.
    @inlinable
    public static func from(_ data: Data, allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

extension Data {
    /// Creates Data from a ByteBuffer.
    init(buffer: ByteBuffer) {
        var buffer = buffer
        self = buffer.readData(length: buffer.readableBytes) ?? Data()
    }
}
```

---

## Usage Examples

### Basic Unicast (SWIM)

```swift
import NIOUDPTransport

// Create transport
let config = UDPConfiguration.unicast(port: 7946)
let transport = NIOUDPTransport(configuration: config)

// Start
try await transport.start()

// Receive in background
Task {
    for await datagram in transport.incomingDatagrams {
        print("Received \(datagram.data.count) bytes from \(datagram.remoteAddress)")
        // Process datagram...
    }
}

// Send
let address = try SocketAddress(ipAddress: "192.168.1.10", port: 7946)
try await transport.send(Data("Hello".utf8), to: address)

// Shut down
try await transport.shutdown()
```

### Multicast (mDNS)

```swift
import NIOUDPTransport

// Create transport for mDNS
let config = UDPConfiguration.multicast(port: 5353)
let transport = NIOUDPTransport(configuration: config)

// Start
try await transport.start()

// Join mDNS multicast groups
try await transport.joinMulticastGroup("224.0.0.251", on: nil)  // IPv4
try await transport.joinMulticastGroup("ff02::fb", on: nil)     // IPv6

// Receive
Task {
    for await datagram in transport.incomingDatagrams {
        // Process mDNS message...
    }
}

// Send multicast
try await transport.sendMulticast(dnsQuery, to: "224.0.0.251", port: 5353)

// Cleanup
try await transport.leaveMulticastGroup("224.0.0.251", on: nil)
try await transport.shutdown()
```

### Shared EventLoopGroup

```swift
import NIOPosix
import NIOUDPTransport

// Share event loop group across transports
let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

let swimTransport = NIOUDPTransport(
    configuration: .unicast(port: 7946),
    eventLoopGroup: eventLoopGroup
)

let mdnsTransport = NIOUDPTransport(
    configuration: .multicast(port: 5353),
    eventLoopGroup: eventLoopGroup
)

// Don't forget to shutdown when done
defer {
    try? eventLoopGroup.syncShutdownGracefully()
}
```

---

## Integration with swift-SWIM

```swift
// In swift-SWIM, create adapter
import SWIM
import NIOUDPTransport

/// Adapts NIOUDPTransport to SWIMTransport protocol.
public final class SWIMUDPTransport: SWIMTransport, Sendable {
    private let udp: NIOUDPTransport

    public var localAddress: String {
        // ... get from udp.localAddress
    }

    public var incomingMessages: AsyncStream<(SWIMMessage, MemberID)> {
        // Transform udp.incomingDatagrams
        AsyncStream { continuation in
            Task {
                for await datagram in udp.incomingDatagrams {
                    if let message = try? SWIMMessageCodec.decode(datagram.data),
                       let address = datagram.remoteAddress.hostPortString {
                        let memberID = MemberID(id: address, address: address)
                        continuation.yield((message, memberID))
                    }
                }
                continuation.finish()
            }
        }
    }

    public func send(_ message: SWIMMessage, to member: MemberID) async throws {
        let data = SWIMMessageCodec.encode(message)
        let address = try SocketAddress(hostPort: member.address)
        try await udp.send(data, to: address)
    }
}
```

---

## Integration with swift-mDNS

```swift
// In swift-mDNS, replace MDNSSocket with NIOUDPTransport
import mDNS
import NIOUDPTransport

/// NIO-based mDNS transport.
public final class MDNSTransportNIO: MDNSTransport, Sendable {
    private let udp: NIOUDPTransport

    public init(configuration: MDNSConfiguration) throws {
        let udpConfig = UDPConfiguration.multicast(port: 5353)
        self.udp = NIOUDPTransport(configuration: udpConfig)
    }

    public func start() async throws {
        try await udp.start()

        if configuration.useIPv4 {
            try await udp.joinMulticastGroup("224.0.0.251", on: configuration.interface)
        }
        if configuration.useIPv6 {
            try await udp.joinMulticastGroup("ff02::fb", on: configuration.interface)
        }
    }

    public func send(_ message: DNSMessage) async throws {
        let data = message.encode()

        if configuration.useIPv4 {
            try await udp.sendMulticast(data, to: "224.0.0.251", port: 5353)
        }
        if configuration.useIPv6 {
            try await udp.sendMulticast(data, to: "ff02::fb", port: 5353)
        }
    }

    // ... rest of implementation
}
```

---

## Package.swift

```swift
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "swift-nio-udp",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(
            name: "NIOUDPTransport",
            targets: ["NIOUDPTransport"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.92.0"),
    ],
    targets: [
        .target(
            name: "NIOUDPTransport",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "NIOUDPTransportTests",
            dependencies: ["NIOUDPTransport"]
        ),
    ]
)
```

---

## Testing Strategy

### Unit Tests

1. **ConfigurationTests** - Configuration creation, defaults
2. **AddressHelpersTests** - Address parsing, conversion
3. **NIOUDPTransportTests** - Start/stop, send/receive

### Integration Tests

1. **LoopbackTests** - Send to self on loopback
2. **MulticastTests** - Join/leave groups, multicast send
3. **ConcurrencyTests** - Multiple concurrent sends

### Performance Tests

1. **ThroughputTests** - Datagrams per second
2. **LatencyTests** - Round-trip time

---

## Verification Checklist

- [ ] Unicast send/receive works
- [ ] Multicast join/leave works
- [ ] Multicast send/receive works
- [ ] AsyncStream properly delivers datagrams
- [ ] Error handling is comprehensive
- [ ] Works on macOS
- [ ] Works on Linux
- [ ] Integration with swift-SWIM verified
- [ ] Integration with swift-mDNS verified
