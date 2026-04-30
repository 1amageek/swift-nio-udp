import Testing
import Foundation
import NIOCore
@testable import NIOUDPTransport

@Suite("Multicast Tests")
struct MulticastTests {

    // MARK: - Basic Multicast Operations

    @Test("Join IPv4 multicast group")
    func joinIPv4MulticastGroup() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.joinMulticastGroup("224.0.0.251", on: nil)
        try await transport.shutdown()
    }

    @Test("Join IPv6 multicast group")
    func joinIPv6MulticastGroup() async throws {
        let config = UDPConfiguration(
            bindAddress: .ipv6Any(port: 0),
            reuseAddress: true,
            reusePort: true
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        do {
            try await transport.joinMulticastGroup("ff02::fb", on: nil)
        } catch UDPError.multicastError(let message) where message.contains("No such device") {
            try await transport.shutdown()
            return
        } catch {
            try await transport.shutdown()
            throw error
        }
        try await transport.shutdown()
    }

    @Test("Leave multicast group")
    func leaveMulticastGroup() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.joinMulticastGroup("224.0.0.251", on: nil)
        try await transport.leaveMulticastGroup("224.0.0.251", on: nil)
        try await transport.shutdown()
    }

    @Test("Send to multicast group")
    func sendToMulticastGroup() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let testData = Data("Hello, Multicast!".utf8)
        try await transport.sendMulticast(testData, to: "224.0.0.251", port: 5353)
        try await transport.shutdown()
    }

    @Test("Send ByteBuffer to multicast group")
    func sendByteBufferToMulticastGroup() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        var buffer = ByteBufferAllocator().buffer(capacity: 16)
        buffer.writeString("Hello")
        try await transport.sendMulticast(buffer, to: "224.0.0.251", port: 5353)
        try await transport.shutdown()
    }

    // MARK: - Error Cases

    @Test("Join multicast before start throws error")
    func joinMulticastBeforeStart() async {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        await #expect(throws: UDPError.self) {
            try await transport.joinMulticastGroup("224.0.0.251", on: nil)
        }
    }

    @Test("Leave multicast before start throws error")
    func leaveMulticastBeforeStart() async {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        await #expect(throws: UDPError.self) {
            try await transport.leaveMulticastGroup("224.0.0.251", on: nil)
        }
    }

    @Test("Join with invalid group address throws error")
    func joinInvalidGroupAddress() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        await #expect(throws: UDPError.self) {
            // 192.168.1.1 is not a multicast address
            try await transport.joinMulticastGroup("192.168.1.1", on: nil)
        }

        try await transport.shutdown()
    }

    @Test("Join with non-existent interface throws error")
    func joinNonExistentInterface() async throws {
        let config = UDPConfiguration.multicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        await #expect(throws: UDPError.self) {
            try await transport.joinMulticastGroup("224.0.0.251", on: "nonexistent0")
        }

        try await transport.shutdown()
    }
}
