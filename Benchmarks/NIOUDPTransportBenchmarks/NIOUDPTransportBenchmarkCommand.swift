/// NIOUDPTransport benchmark command.
///
/// Performance benchmarks for UDP transport operations.

import Foundation
import NIOCore
import NIOPosix
import Synchronization
import NIOUDPTransport

private let benchmarkSink = Mutex(0)

@main
enum NIOUDPTransportBenchmarkCommand {
    static func main() async throws {
        let benchmarks = Benchmarks()
        try benchmarks.benchmarkParseIPv4()
        try benchmarks.benchmarkParseIPv6()
        try benchmarks.benchmarkHostPortString()
        try await benchmarks.benchmarkLoopbackSend()
        try await benchmarks.benchmarkLoopbackDelivery()
        try await benchmarks.benchmarkBatchSend10()
        try await benchmarks.benchmarkBatchVsSingle()
        try benchmarks.benchmarkAddressCache()
    }
}

private struct Benchmarks {

    // MARK: - Address Parsing Benchmarks

    func benchmarkParseIPv4() throws {
        let iterations = 100_000
        let start = ContinuousClock.now
        var checksum = 0

        for _ in 0..<iterations {
            let address = try SocketAddress(hostPort: "192.168.1.100:7946")
            checksum &+= address.port ?? 0
        }
        benchmarkSink.withLock { $0 = checksum }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Parse IPv4 address: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    func benchmarkParseIPv6() throws {
        let iterations = 100_000
        let start = ContinuousClock.now
        var checksum = 0

        for _ in 0..<iterations {
            let address = try SocketAddress(hostPort: "[::1]:7946")
            checksum &+= address.port ?? 0
        }
        benchmarkSink.withLock { $0 = checksum }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("Parse IPv6 address: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    func benchmarkHostPortString() throws {
        let address = try SocketAddress(ipAddress: "192.168.1.100", port: 7946)
        let iterations = 100_000
        let start = ContinuousClock.now
        var checksum = 0

        for _ in 0..<iterations {
            guard let hostPortString = address.hostPortString else {
                throw BenchmarkError.missingHostPortString
            }
            checksum &+= hostPortString.count
        }
        benchmarkSink.withLock { $0 = checksum }

        let elapsed = ContinuousClock.now - start
        let perIteration = elapsed / iterations

        print("hostPortString: \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) ops/sec")
    }

    // MARK: - Loopback Throughput Benchmarks

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

        try await transport.shutdown()

        print("Loopback send submission (256 bytes): \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) datagrams/sec")
        print("  Data throughput: \(String(format: "%.2f", throughputMBps)) MB/sec")
    }

    func benchmarkLoopbackDelivery() async throws {
        let config1 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true
        )
        let config2 = UDPConfiguration(
            bindAddress: .specific(host: "127.0.0.1", port: 0),
            reuseAddress: true,
            streamBufferSize: 8_192
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
        try await sender.shutdown()
        try await receiver.shutdown()
        _ = await receiveTask.result

        guard received == iterations else {
            throw BenchmarkError.incompleteReceive(expected: iterations, actual: received)
        }

        let perIteration = elapsed / iterations
        let lossRate = Double(iterations - received) / Double(iterations) * 100

        print("Loopback delivery (128 bytes): \(perIteration) per iteration (\(iterations) iterations)")
        print("  Throughput: \(Double(iterations) / elapsed.totalSeconds) datagrams/sec")
        print("  Received: \(received)/\(iterations) (loss: \(String(format: "%.2f", lossRate))%)")
    }

    // MARK: - Batch Send Benchmarks

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

        try await transport.shutdown()

        print("Batch send (10x256 bytes): \(perBatch) per batch (\(iterations) batches)")
        print("  Throughput: \(Double(totalDatagrams) / elapsed.totalSeconds) datagrams/sec")
        print("  Data throughput: \(String(format: "%.2f", throughputMBps)) MB/sec")
    }

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

        try await transport.shutdown()

        let totalDatagrams = iterations * batchSize
        let singleMBps = (Double(totalDatagrams) * 256.0) / elapsedSingle.totalSeconds / 1_000_000.0
        let batchMBps = (Double(totalDatagrams) * 256.0) / elapsedBatch.totalSeconds / 1_000_000.0

        print("Single send (10x256B): \(String(format: "%.2f", singleMBps)) MB/sec")
        print("Batch send  (10x256B): \(String(format: "%.2f", batchMBps)) MB/sec")
        print("Speedup: \(String(format: "%.2f", batchMBps / singleMBps))x")
    }

    func benchmarkAddressCache() throws {
        let iterations = 100_000

        // Benchmark uncached parsing
        let startUncached = ContinuousClock.now
        var checksum = 0
        for _ in 0..<iterations {
            let address = try SocketAddress(hostPort: "192.168.1.100:7946")
            checksum &+= address.port ?? 0
        }
        let elapsedUncached = ContinuousClock.now - startUncached

        // Clear cache and prepare for cached benchmark
        SocketAddress.clearCache()

        // Pre-populate cache
        _ = try SocketAddress.cached(hostPort: "192.168.1.100:7946")

        // Benchmark cached access
        let startCached = ContinuousClock.now
        for _ in 0..<iterations {
            let address = try SocketAddress.cached(hostPort: "192.168.1.100:7946")
            checksum &+= address.port ?? 0
        }
        let elapsedCached = ContinuousClock.now - startCached
        benchmarkSink.withLock { $0 = checksum }

        let uncachedPerOp = elapsedUncached / iterations
        let cachedPerOp = elapsedCached / iterations

        print("SocketAddress uncached: \(uncachedPerOp) per operation")
        print("SocketAddress cached:   \(cachedPerOp) per operation")
        print("Speedup: \(String(format: "%.1f", elapsedUncached.totalSeconds / elapsedCached.totalSeconds))x")
    }
}

private enum BenchmarkError: Error {
    case incompleteReceive(expected: Int, actual: Int)
    case missingHostPortString
}

// MARK: - Duration Helper

extension Duration {
    var totalSeconds: Double {
        let comps = self.components
        return Double(comps.seconds) + Double(comps.attoseconds) / 1e18
    }
}
