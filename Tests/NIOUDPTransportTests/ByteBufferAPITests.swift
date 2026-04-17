import Testing
import Foundation
import NIOCore
import Synchronization
@testable import NIOUDPTransport

@Suite("ByteBuffer API Tests")
struct ByteBufferAPITests {

    @Test("Send ByteBuffer to address")
    func sendByteBuffer() async throws {
        let config = UDPConfiguration.unicast(port: 0)
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        var buffer = ByteBufferAllocator().buffer(capacity: 32)
        buffer.writeString("Hello, ByteBuffer!")

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)
        try await transport.send(buffer, to: address)

        try await transport.shutdown()
    }

    @Test("Send ByteBuffer loopback receive")
    func sendByteBufferLoopback() async throws {
        let config1 = UDPConfiguration(bindAddress: .specific(host: "127.0.0.1", port: 0))
        let config2 = UDPConfiguration(bindAddress: .specific(host: "127.0.0.1", port: 0))

        let sender = NIOUDPTransport(configuration: config1)
        let receiver = NIOUDPTransport(configuration: config2)

        try await sender.start()
        try await receiver.start()

        guard let receiverAddr = await receiver.localAddress,
              let port = receiverAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let receivedBuffer = Mutex<ByteBuffer?>(nil)

        let receiveTask = Task {
            for await datagram in receiver.incomingDatagrams {
                receivedBuffer.withLock { $0 = datagram.buffer }
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        var buffer = ByteBufferAllocator().buffer(capacity: 32)
        buffer.writeString("ByteBuffer Test")
        try await sender.send(buffer, to: targetAddr)

        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if receivedBuffer.withLock({ $0 != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        receiveTask.cancel()

        let received = receivedBuffer.withLock { $0 }
        #expect(received != nil)
        #expect(received?.getString(at: 0, length: received?.readableBytes ?? 0) == "ByteBuffer Test")

        try await sender.shutdown()
        try await receiver.shutdown()
    }

    @Test("ByteBuffer too large throws error")
    func byteBufferTooLarge() async throws {
        let maxSize = 1400
        let config = UDPConfiguration(
            bindAddress: .any(port: 0),
            maxDatagramSize: maxSize
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        var buffer = ByteBufferAllocator().buffer(capacity: maxSize + 100)
        buffer.writeBytes(Data(repeating: 0x42, count: maxSize + 1))

        let address = try SocketAddress(ipAddress: "127.0.0.1", port: 8080)

        await #expect(throws: UDPError.self) {
            try await transport.send(buffer, to: address)
        }

        try await transport.shutdown()
    }

    @Test("Received datagram buffer converts to Data correctly")
    func receivedDatagramToData() async throws {
        let config1 = UDPConfiguration(bindAddress: .specific(host: "127.0.0.1", port: 0))
        let config2 = UDPConfiguration(bindAddress: .specific(host: "127.0.0.1", port: 0))

        let sender = NIOUDPTransport(configuration: config1)
        let receiver = NIOUDPTransport(configuration: config2)

        try await sender.start()
        try await receiver.start()

        guard let receiverAddr = await receiver.localAddress,
              let port = receiverAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let receivedData = Mutex<Data?>(nil)

        let receiveTask = Task {
            for await datagram in receiver.incomingDatagrams {
                receivedData.withLock { $0 = datagram.data }
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))

        let testData = Data("Test Data".utf8)
        try await sender.send(testData, to: targetAddr)

        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if receivedData.withLock({ $0 != nil }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        receiveTask.cancel()

        let received = receivedData.withLock { $0 }
        #expect(received == testData)

        try await sender.shutdown()
        try await receiver.shutdown()
    }
}
