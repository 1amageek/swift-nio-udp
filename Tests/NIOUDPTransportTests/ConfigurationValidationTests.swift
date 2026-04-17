import Testing
import Foundation
import NIOCore
@testable import NIOUDPTransport

@Suite("Configuration Validation Tests")
struct ConfigurationValidationTests {

    // MARK: - BindAddress Variants

    @Test("IPv4Any configuration binds to 0.0.0.0")
    func ipv4AnyConfiguration() async throws {
        let config = UDPConfiguration(bindAddress: .ipv4Any(port: 0))
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let address = await transport.localAddress
        #expect(address != nil)
        try await transport.shutdown()
    }

    @Test("IPv6Any configuration binds to ::")
    func ipv6AnyConfiguration() async throws {
        let config = UDPConfiguration(bindAddress: .ipv6Any(port: 0))
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let address = await transport.localAddress
        #expect(address != nil)
        try await transport.shutdown()
    }

    @Test("Specific host configuration")
    func specificHostConfiguration() async throws {
        let config = UDPConfiguration(bindAddress: .specific(host: "127.0.0.1", port: 0))
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let address = await transport.localAddress
        #expect(address != nil)
        #expect(address?.host == "127.0.0.1")
        try await transport.shutdown()
    }

    @Test("Port 0 auto-assigns available port")
    func portZeroAutoAssigns() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let address = await transport.localAddress
        #expect(address?.port != nil)
        #expect(address!.port! > 0)
        try await transport.shutdown()
    }

    // MARK: - Buffer Sizes

    @Test("Custom receive buffer size is applied")
    func customReceiveBufferSize() async throws {
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            receiveBufferSize: 32768
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.shutdown()
    }

    @Test("Custom send buffer size is applied")
    func customSendBufferSize() async throws {
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            sendBufferSize: 32768
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.shutdown()
    }

    @Test("Custom stream buffer size is applied")
    func customStreamBufferSize() async throws {
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            streamBufferSize: 50
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.shutdown()
    }

    // MARK: - Presets

    @Test("Unicast preset has expected values")
    func unicastPreset() {
        let config = UDPConfiguration.unicast(port: 7946)

        #expect(config.bindAddress == .any(port: 7946))
        #expect(config.reuseAddress == true)
        #expect(config.reusePort == false)
        #expect(config.maxDatagramSize == 65507)
        #expect(config.streamBufferSize == 100)
    }

    @Test("Multicast preset has expected values")
    func multicastPreset() {
        let config = UDPConfiguration.multicast(port: 5353)

        #expect(config.bindAddress == .any(port: 5353))
        #expect(config.reuseAddress == true)
        #expect(config.reusePort == true)
        #expect(config.streamBufferSize == 200)
    }

    // MARK: - BindAddress Properties

    @Test("BindAddress port property returns correct value")
    func bindAddressPortProperty() {
        let addresses: [(UDPConfiguration.BindAddress, Int)] = [
            (.any(port: 1234), 1234),
            (.specific(host: "127.0.0.1", port: 5678), 5678),
            (.ipv4Any(port: 9012), 9012),
            (.ipv6Any(port: 3456), 3456),
        ]

        for (address, expectedPort) in addresses {
            #expect(address.port == expectedPort)
        }
    }
}
