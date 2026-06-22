/// UDP Transport Errors
///
/// Errors that can occur during UDP transport operations.

import Foundation

/// Errors that can occur during UDP operations.
public enum UDPError: Error, Sendable {
    /// Transport is not started.
    case notStarted

    /// Transport is already started.
    case alreadyStarted

    /// Failed to bind to address.
    case bindFailed(underlying: Error)

    /// Failed to send datagram.
    case sendFailed(underlying: Error)

    /// One or more datagrams in a batch send failed.
    ///
    /// `failedCount` is the number of datagrams that failed out of `total`, and
    /// `firstError` is the first underlying failure encountered.
    case batchSendFailed(failedCount: Int, total: Int, firstError: Error)

    /// Invalid address format.
    case invalidAddress(String)

    /// Datagram too large.
    case datagramTooLarge(size: Int, max: Int)

    /// Multicast operation failed.
    case multicastError(String)

    /// Channel closed unexpectedly.
    case channelClosed

    /// Failed to shut down transport resources.
    case shutdownFailed(underlying: Error)

    /// Operation timed out.
    case timeout

    /// Invalid configuration value.
    case invalidConfiguration(String)
}

extension UDPError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notStarted:
            return "UDP transport not started"
        case .alreadyStarted:
            return "UDP transport already started"
        case .bindFailed(let error):
            return "Failed to bind: \(error)"
        case .sendFailed(let error):
            return "Failed to send: \(error)"
        case .batchSendFailed(let failedCount, let total, let firstError):
            return "Batch send failed for \(failedCount) of \(total) datagram(s); first error: \(firstError)"
        case .invalidAddress(let address):
            return "Invalid address: \(address)"
        case .datagramTooLarge(let size, let max):
            return "Datagram too large: \(size) bytes (max: \(max))"
        case .multicastError(let message):
            return "Multicast error: \(message)"
        case .channelClosed:
            return "Channel closed unexpectedly"
        case .shutdownFailed(let error):
            return "Failed to shut down transport: \(error)"
        case .timeout:
            return "Operation timed out"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}
