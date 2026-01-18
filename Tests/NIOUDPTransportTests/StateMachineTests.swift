import Testing
import Foundation
import NIOCore
import NIOPosix
import Synchronization
@testable import NIOUDPTransport

@Suite("State Machine Tests")
struct StateMachineTests {

    // MARK: - State Transitions

    @Test("Stop on non-started transport is no-op")
    func stopOnNonStarted() async {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        await transport.stop()
        // Should complete without error
    }

    @Test("Double stop is idempotent")
    func doubleStop() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        await transport.stop()
        await transport.stop()
    }

    // MARK: - Lifecycle

    @Test("AsyncStream completes on stop")
    func asyncStreamCompletesOnStop() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        let streamCompleted = Mutex(false)

        let task = Task {
            for await _ in transport.incomingDatagrams {
                // Consume datagrams
            }
            streamCompleted.withLock { $0 = true }
        }

        try await Task.sleep(for: .milliseconds(50))
        await transport.stop()
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        let completed = streamCompleted.withLock { $0 }
        #expect(completed)
    }

    @Test("LocalAddress is nil before start")
    func localAddressBeforeStart() async {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        let address = await transport.localAddress
        #expect(address == nil)
    }

    @Test("LocalAddress is nil after stop")
    func localAddressAfterStop() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()
        let addressBefore = await transport.localAddress
        #expect(addressBefore != nil)

        await transport.stop()

        let addressAfter = await transport.localAddress
        #expect(addressAfter == nil)
    }

    // MARK: - Concurrency

    @Test("Concurrent sends do not corrupt state")
    func concurrentSends() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 9999)
        let sendCount = 100

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<sendCount {
                group.addTask {
                    let data = Data("Message \(i)".utf8)
                    try? await transport.send(data, to: address)
                }
            }
        }

        await transport.stop()
    }

    @Test("Rapid start-stop cycles complete cleanly", .timeLimit(.minutes(1)))
    func rapidStartStopCycles() async throws {
        for _ in 0..<5 {
            let config = UDPConfiguration.unicast(port: 0)
            let transport = NIOUDPTransport(configuration: config)

            try await transport.start()
            await transport.stop()
        }
    }

    @Test("Multiple transports can run simultaneously")
    func multipleTransports() async throws {
        let transports = (0..<3).map { _ in
            NIOUDPTransport(configuration: .unicast(port: 0))
        }

        for transport in transports {
            try await transport.start()
        }

        for transport in transports {
            let addr = await transport.localAddress
            #expect(addr != nil)
        }

        for transport in transports {
            await transport.stop()
        }
    }

    @Test("External EventLoopGroup is not shutdown on stop")
    func externalEventLoopGroupNotShutdown() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config, eventLoopGroup: group)

        try await transport.start()
        await transport.stop()

        // Group should still be usable
        let transport2 = NIOUDPTransport(configuration: config, eventLoopGroup: group)
        try await transport2.start()
        await transport2.stop()

        try await group.shutdownGracefully()
    }
}
