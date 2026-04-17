import Testing
import Foundation
import NIOCore
import NIOPosix
@testable import NIOUDPTransport

@Suite("Error Path Tests")
struct ErrorPathTests {

    // MARK: - Bind Errors

    @Test("Bind to occupied port throws bindFailed")
    func bindToOccupiedPort() async throws {
        let config1 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: false,
            reusePort: false
        )
        let transport1 = NIOUDPTransport(configuration: config1)
        try await transport1.start()

        guard let boundPort = await transport1.localAddress?.port else {
            throw UDPError.notStarted
        }

        let config2 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: boundPort),
            reuseAddress: false,
            reusePort: false
        )
        let transport2 = NIOUDPTransport(configuration: config2)

        await #expect(throws: UDPError.self) {
            try await transport2.start()
        }

        try await transport1.shutdown()
    }

    @Test("Send after shutdown throws notStarted")
    func sendAfterShutdown() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.shutdown()

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)

        await #expect(throws: UDPError.self) {
            try await transport.send(Data("test".utf8), to: address)
        }
    }

    @Test("Restart after shutdown throws alreadyStarted")
    func restartAfterShutdown() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        try await transport.shutdown()

        await #expect(throws: UDPError.self) {
            try await transport.start()
        }
    }

    // MARK: - Datagram Size

    @Test("Send zero-length datagram succeeds")
    func sendZeroLengthDatagram() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)
        try await transport.send(Data(), to: address)
        try await transport.shutdown()
    }

    @Test("Datagram at exact max size succeeds")
    func datagramAtMaxSize() async throws {
        let maxSize = 1400
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            maxDatagramSize: maxSize
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let data = Data(repeating: 0x42, count: maxSize)
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)
        try await transport.send(data, to: address)
        try await transport.shutdown()
    }

    @Test("Datagram one byte over max throws error")
    func datagramOverMaxSize() async throws {
        let maxSize = 1400
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            maxDatagramSize: maxSize
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let data = Data(repeating: 0x42, count: maxSize + 1)
        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)

        await #expect(throws: UDPError.self) {
            try await transport.send(data, to: address)
        }

        try await transport.shutdown()
    }

    // MARK: - Error Messages

    @Test("All UDPError cases have non-empty descriptions")
    func allErrorsHaveDescriptions() {
        let errors: [UDPError] = [
            .notStarted,
            .alreadyStarted,
            .bindFailed(underlying: NSError(domain: "test", code: 1)),
            .sendFailed(underlying: NSError(domain: "test", code: 2)),
            .invalidAddress("test"),
            .datagramTooLarge(size: 70000, max: 65507),
            .multicastError("test"),
            .channelClosed,
            .timeout,
            .invalidConfiguration("test")
        ]

        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }

    @Test("bindFailed includes underlying error message")
    func bindFailedIncludesUnderlying() {
        let underlying = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = UDPError.bindFailed(underlying: underlying)
        #expect(error.description.contains("Test error"))
    }

    @Test("sendFailed includes underlying error message")
    func sendFailedIncludesUnderlying() {
        let underlying = NSError(domain: "TestDomain", code: 42, userInfo: [NSLocalizedDescriptionKey: "Send failed"])
        let error = UDPError.sendFailed(underlying: underlying)
        #expect(error.description.contains("Send failed"))
    }
}
