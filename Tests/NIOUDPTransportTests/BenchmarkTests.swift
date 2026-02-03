/// NIOUDPTransport Benchmark Tests
///
/// Performance benchmarks for UDP transport operations.

import Testing
import Foundation
import NIOCore
import NIOPosix
import Synchronization
@testable import NIOUDPTransport

@Suite("Benchmark Tests")
struct BenchmarkTests {

    // MARK: - Address Parsing Benchmarks

    @Test("Benchmark: Parse IPv4 address")
    func benchmarkParseIPv4() throws {
        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            _ = try SocketAddress(hostPort: "192.168.1.100:7946")
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Parse IPv4 address: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: Parse IPv6 address")
    func benchmarkParseIPv6() throws {
        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            _ = try SocketAddress(hostPort: "[::1]:7946")
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Parse IPv6 address: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: hostPortString generation")
    func benchmarkHostPortString() throws {
        let address = try SocketAddress(ipAddress: "192.168.1.100", port: 7946)

        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            _ = address.hostPortString
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("hostPortString: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    // MARK: - ByteBuffer Benchmarks

    @Test("Benchmark: ByteBuffer write bytes")
    func benchmarkByteBufferWrite() {
        let allocator = ByteBufferAllocator()
        let testData = Data(repeating: 0x42, count: 512)

        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            var buffer = allocator.buffer(capacity: 512)
            buffer.writeBytes(testData)
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("ByteBuffer write 512 bytes: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: ByteBuffer to Data conversion")
    func benchmarkByteBufferToData() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 512)
        buffer.writeBytes(Data(repeating: 0x42, count: 512))

        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            _ = Data(buffer: buffer)
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("ByteBuffer to Data (512 bytes): \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: ByteBuffer withUnsafeReadableBytes")
    func benchmarkByteBufferUnsafeRead() {
        let allocator = ByteBufferAllocator()
        var buffer = allocator.buffer(capacity: 512)
        buffer.writeBytes(Data(repeating: 0x42, count: 512))

        let iterations = 100_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            buffer.withUnsafeReadableBytes { ptr in
                _ = ptr.count
            }
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("ByteBuffer withUnsafeReadableBytes: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    // MARK: - Atomic vs Mutex Benchmarks

    @Test("Benchmark: Atomic Bool load")
    func benchmarkAtomicBoolLoad() {
        let atomic = Atomic<Bool>(false)

        let iterations = 1_000_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            _ = atomic.load(ordering: .acquiring)
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Atomic Bool load: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: Mutex withLock")
    func benchmarkMutexWithLock() {
        let mutex = Mutex<Bool>(false)

        let iterations = 1_000_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            mutex.withLock { _ = $0 }
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Mutex withLock: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    @Test("Benchmark: Atomic vs Mutex comparison")
    func benchmarkAtomicVsMutex() {
        let atomic = Atomic<Bool>(false)
        let mutex = Mutex<Bool>(false)

        let iterations = 500_000

        // Benchmark Atomic
        let startAtomic = ContinuousClock.now
        for _ in 0..<iterations {
            if !atomic.load(ordering: .acquiring) {
                // simulate work
            }
        }
        let elapsedAtomic = ContinuousClock.now - startAtomic

        // Benchmark Mutex
        let startMutex = ContinuousClock.now
        for _ in 0..<iterations {
            mutex.withLock { val in
                if !val {
                    // simulate work
                }
            }
        }
        let elapsedMutex = ContinuousClock.now - startMutex

        print("Atomic check: \(elapsedAtomic / iterations) per iteration")
        print("Mutex check: \(elapsedMutex / iterations) per iteration")
        print("Speedup: \(elapsedMutex.totalSeconds / elapsedAtomic.totalSeconds)x")
    }

    // MARK: - AsyncStream Benchmarks

    @Test("Benchmark: AsyncStream yield")
    func benchmarkAsyncStreamYield() async {
        var continuation: AsyncStream<Int>.Continuation!
        let stream = AsyncStream<Int>(bufferingPolicy: .bufferingNewest(100)) { cont in
            continuation = cont
        }

        let iterations = 100_000
        let start = ContinuousClock.now

        for i in 0..<iterations {
            _ = continuation.yield(i)
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        continuation.finish()
        _ = stream  // Keep stream alive

        print("AsyncStream yield: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    // MARK: - Loopback Throughput Benchmarks

    @Test("Benchmark: Loopback send throughput")
    func benchmarkLoopbackSend() async throws {
        let config = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        guard let localAddr = await transport.localAddress,
              let port = localAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let testData = Data(repeating: 0x42, count: 256)

        // Warm up
        for _ in 0..<100 {
            try await transport.send(testData, to: targetAddr)
        }

        let iterations = 10_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            try await transport.send(testData, to: targetAddr)
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations
        let throughputMBps = (Double(iterations) * 256.0) / elapsed.totalSeconds / 1_000_000.0

        await transport.stop()

        print("Loopback send (256 bytes): \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) datagrams/sec")
        print("  Data throughput: \(String(format: "%.2f", throughputMBps)) MB/sec")
    }

    @Test("Benchmark: Loopback send/receive round-trip")
    func benchmarkLoopbackRoundTrip() async throws {
        let config1 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let config2 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )

        let sender = NIOUDPTransport(configuration: config1)
        let receiver = NIOUDPTransport(configuration: config2)

        try await sender.start()
        try await receiver.start()

        guard let receiverAddr = await receiver.localAddress,
              let receiverPort = receiverAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: receiverPort)
        let testData = Data(repeating: 0x42, count: 128)

        let receivedCount = Mutex<Int>(0)

        // Start receiver task
        let receiveTask = Task {
            for await _ in receiver.incomingDatagrams {
                receivedCount.withLock { $0 += 1 }
            }
        }

        // Warm up
        try await Task.sleep(for: .milliseconds(50))

        let iterations = 5_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            try await sender.send(testData, to: targetAddr)
        }

        // Wait for messages to be received
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if receivedCount.withLock({ $0 >= iterations }) {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        let elapsed = ContinuousClock.now - start
        let received = receivedCount.withLock { $0 }

        receiveTask.cancel()
        await sender.stop()
        await receiver.stop()

        let perIteration = elapsed / iterations
        let lossRate = Double(iterations - received) / Double(iterations) * 100

        print("Loopback round-trip (128 bytes): \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) datagrams/sec")
        print("  Received: \(received)/\(iterations) (loss: \(String(format: "%.2f", lossRate))%)")
    }

    // MARK: - Configuration Benchmarks

    @Test("Benchmark: UDPConfiguration creation")
    func benchmarkConfigCreation() {
        let iterations = 100_000
        let start = ContinuousClock.now

        for i in 0..<iterations {
            _ = UDPConfiguration(
                bindAddress: .specific(host: "127.0.0.1", port: 8000 + (i % 1000)),
                reuseAddress: true,
                reusePort: false
            )
        }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("UDPConfiguration creation: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    // MARK: - Batch Send Benchmarks

    @Test("Benchmark: Batch send throughput (10 packets)")
    func benchmarkBatchSend10() async throws {
        let config = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        guard let localAddr = await transport.localAddress,
              let port = localAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let testData = Data(repeating: 0x42, count: 256)

        // Prepare batch of 10 datagrams
        let batchSize = 10
        var datagrams: [(Data, SocketAddress)] = []
        datagrams.reserveCapacity(batchSize)
        for _ in 0..<batchSize {
            datagrams.append((testData, targetAddr))
        }

        // Warm up
        for _ in 0..<10 {
            try await transport.sendBatch(datagrams)
        }

        let iterations = 1_000
        let start = ContinuousClock.now

        for _ in 0..<iterations {
            try await transport.sendBatch(datagrams)
        }

        let elapsed = ContinuousClock.now - start
        let totalDatagrams = iterations * batchSize
        let perBatch = elapsed / iterations
        let throughputMBps = (Double(totalDatagrams) * 256.0) / elapsed.totalSeconds / 1_000_000.0

        await transport.stop()

        print("Batch send (10x256 bytes): \(perBatch) per batch (\(iterations) batches)")
        print("  Throughput: \(Double(totalDatagrams) / elapsed.totalSeconds) datagrams/sec")
        print("  Data throughput: \(String(format: "%.2f", throughputMBps)) MB/sec")
    }

    @Test("Benchmark: Batch send vs single send (comparison)")
    func benchmarkBatchVsSingle() async throws {
        let config = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let transport = NIOUDPTransport(configuration: config)

        try await transport.start()

        guard let localAddr = await transport.localAddress,
              let port = localAddr.port else {
            throw UDPError.notStarted
        }

        let targetAddr = try SocketAddress(ipAddress: "127.0.0.1", port: port)
        let testData = Data(repeating: 0x42, count: 256)

        let batchSize = 10
        let iterations = 500

        // Benchmark single send
        let startSingle = ContinuousClock.now
        for _ in 0..<iterations {
            for _ in 0..<batchSize {
                try await transport.send(testData, to: targetAddr)
            }
        }
        let elapsedSingle = ContinuousClock.now - startSingle

        // Benchmark batch send
        var datagrams: [(Data, SocketAddress)] = []
        datagrams.reserveCapacity(batchSize)
        for _ in 0..<batchSize {
            datagrams.append((testData, targetAddr))
        }

        let startBatch = ContinuousClock.now
        for _ in 0..<iterations {
            try await transport.sendBatch(datagrams)
        }
        let elapsedBatch = ContinuousClock.now - startBatch

        await transport.stop()

        let totalDatagrams = iterations * batchSize
        let singleMBps = (Double(totalDatagrams) * 256.0) / elapsedSingle.totalSeconds / 1_000_000.0
        let batchMBps = (Double(totalDatagrams) * 256.0) / elapsedBatch.totalSeconds / 1_000_000.0

        print("Single send (10x256B): \(String(format: "%.2f", singleMBps)) MB/sec")
        print("Batch send  (10x256B): \(String(format: "%.2f", batchMBps)) MB/sec")
        print("Speedup: \(String(format: "%.2f", batchMBps / singleMBps))x")
    }

    @Test("Benchmark: SocketAddress.cached() performance")
    func benchmarkAddressCache() throws {
        let iterations = 100_000

        // Benchmark uncached parsing
        let startUncached = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try SocketAddress(hostPort: "192.168.1.100:7946")
        }
        let elapsedUncached = ContinuousClock.now - startUncached

        // Clear cache and prepare for cached benchmark
        SocketAddress.clearCache()

        // Pre-populate cache
        _ = try SocketAddress.cached(hostPort: "192.168.1.100:7946")

        // Benchmark cached access
        let startCached = ContinuousClock.now
        for _ in 0..<iterations {
            _ = try SocketAddress.cached(hostPort: "192.168.1.100:7946")
        }
        let elapsedCached = ContinuousClock.now - startCached

        let uncachedPerOp = elapsedUncached / iterations
        let cachedPerOp = elapsedCached / iterations

        print("SocketAddress uncached: \(uncachedPerOp) per operation")
        print("SocketAddress cached:   \(cachedPerOp) per operation")
        print("Speedup: \(String(format: "%.1f", elapsedUncached.totalSeconds / elapsedCached.totalSeconds))x")
    }
}

// MARK: - Duration Helper

extension Duration {
    var totalSeconds: Double {
        let comps = self.components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
