import Testing
import Foundation
import NIOCore
import Synchronization
@testable import NIOUDPTransport

@Suite("NIOUDPTransport Tests")
struct NIOUDPTransportTests {

    // MARK: - Configuration Tests

    @Test("Unicast configuration has correct defaults")
    func unicastConfiguration() {
        let config = UDPConfiguration.unicast(port: 7946)

        #expect(config.bindAddress == .any(port: 7946))
        #expect(config.reuseAddress == true)
        #expect(config.reusePort == false)
        #expect(config.maxDatagramSize == 65507)
    }

    @Test("Multicast configuration has correct defaults")
    func multicastConfiguration() {
        let config = UDPConfiguration.multicast(port: 5353)

        #expect(config.bindAddress == .any(port: 5353))
        #expect(config.reuseAddress == true)
        #expect(config.reusePort == true)  // Required for multicast
    }

    // MARK: - Address Helper Tests

    @Test("Parse IPv4 host:port")
    func parseIPv4Address() throws {
        let address = try SocketAddress(hostPort: "192.168.1.10:8080")

        #expect(address.host == "192.168.1.10")
        #expect(address.port == 8080)
    }

    @Test("Parse IPv6 with brackets")
    func parseIPv6WithBrackets() throws {
        let address = try SocketAddress(hostPort: "[::1]:8080")

        #expect(address.host == "::1")
        #expect(address.port == 8080)
    }

    @Test("Parse localhost")
    func parseLocalhost() throws {
        let address = try SocketAddress(hostPort: "127.0.0.1:9000")

        #expect(address.host == "127.0.0.1")
        #expect(address.port == 9000)
    }

    @Test("Invalid address throws error")
    func invalidAddressThrows() {
        #expect(throws: UDPError.self) {
            _ = try SocketAddress(hostPort: "invalid")
        }

        #expect(throws: UDPError.self) {
            _ = try SocketAddress(hostPort: "no-port")
        }
    }

    @Test("Host port string round trip")
    func hostPortStringRoundTrip() throws {
        let original = "192.168.1.10:7946"
        let address = try SocketAddress(hostPort: original)
        let result = address.hostPortString

        #expect(result == original)
    }

    // MARK: - Transport Lifecycle Tests

    @Test("Transport starts and stops")
    func transportLifecycle() async throws {
        let config = UDPConfiguration.unicast(port: 0)  // Use port 0 for auto-assign
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        let localAddr = await transport.localAddress
        #expect(localAddr != nil)
        #expect(localAddr?.port != nil)
        #expect(localAddr!.port! > 0)

        try await transport.shutdown()
    }

    @Test("Double start throws error")
    func doubleStartThrows() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        await #expect(throws: UDPError.self) {
            try await transport.start()
        }

        try await transport.shutdown()
    }

    @Test("Send before start throws error")
    func sendBeforeStartThrows() async {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        let address = try! SocketAddress(ipAddress: "127.0.0.1", port: 8080)

        await #expect(throws: UDPError.self) {
            try await transport.send(Data("test".utf8), to: address)
        }
    }

    // MARK: - Send/Receive Tests

    @Test("Loopback send and receive")
    func loopbackSendReceive() async throws {
        // Create two transports bound to localhost
        let config1 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let config2 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )

        let transport1 = NIOUDPTransport(configuration: config1)
        let transport2 = NIOUDPTransport(configuration: config2)

        try await transport1.start()
        try await transport2.start()

        // Get the actual bound address with port
        guard let localAddr2 = await transport2.localAddress,
              let port2 = localAddr2.port else {
            throw UDPError.notStarted
        }

        // Create target address explicitly on 127.0.0.1
        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port2)

        // Setup receiver
        let receivedData = Mutex<Data?>(nil)

        let receiveTask = Task {
            for await datagram in transport2.incomingDatagrams {
                receivedData.withLock { $0 = datagram.data }
                break
            }
        }

        // Give the receive task time to start
        try await Task.sleep(for: .milliseconds(50))

        // Send from transport1 to transport2
        let testData = Data("Hello, UDP!".utf8)
        try await transport1.send(testData, to: targetAddr)

        // Wait for receive with timeout
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if receivedData.withLock({ $0 != nil }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        receiveTask.cancel()

        let received = receivedData.withLock { $0 }
        #expect(received == testData)

        try await transport1.shutdown()
        try await transport2.shutdown()
    }

    @Test("Large datagram is rejected")
    func largeDatagram() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        let largeData = Data(repeating: 0, count: 70000)  // > 65507
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)

        await #expect(throws: UDPError.self) {
            try await transport.send(largeData, to: address)
        }

        try await transport.shutdown()
    }

    // MARK: - Error Tests

    @Test("UDPError descriptions are meaningful")
    func errorDescriptions() {
        let errors: [UDPError] = [
            .notStarted,
            .alreadyStarted,
            .invalidAddress("bad"),
            .datagramTooLarge(size: 70000, max: 65507),
            .multicastError("test"),
            .channelClosed,
            .timeout
        ]

        for error in errors {
            let description = error.description
            #expect(!description.isEmpty)
        }
    }
}
