import Foundation
import Network
import Security

/// WORKER ACTOR
actor MITMBoundConnection: Identifiable {
    nonisolated let id = UUID()
    let clientConnection: NWConnection
    let clashPort: UInt16

    var serverConnection: NWConnection?
    var loopbackListener: NWListener?
    var loopbackConnection: NWConnection?      // Track loopback connection
    var decryptedConnection: NWConnection?     // Track decrypted TLS connection
    var upstreamConnection: NWConnection?      // Track upstream TLS connection
    var buffer = Data()
    var targetHost: String = ""
    var targetPort: NWEndpoint.Port = 80
    var isStopped = false  // CRITICAL: Prevent recursive stop calls
    var isPiping = false   // CRITICAL: Prevent conflicting reads during pipe handover

    // MARK: - Connection Lifecycle Tracking
    let createdAt = Date()
    var lastActivity = Date()
    var handshakeComplete = false  // Track if we've successfully established the pipe

    // Cached whitelist - read once at init to avoid thread issues
    let cachedWhitelist: [String]

    // Resilience Mode
    let resilienceEnabled: Bool

    // Request Cache for Retry
    var cachedRequest: Data?
    var isRetrying = false
    var retryCount = 0
    static let maxRetries = 3

    // Pipe State (Maintained on actor to allow refactoring closures)
    var firstRequestReported = false
    var currentRequestId: String?
    var firstResponseReported = false
    var requestStartTime = Date()
    var responseAccumulator = Data()
    var dataToSendOnRetry: Data?

    func isStale(handshakeTimeout: TimeInterval, dataIdleTimeout: TimeInterval) -> Bool {
        // Already stopped - definitely stale
        if isStopped { return true }

        let age = Date().timeIntervalSince(createdAt)
        let idleTime = Date().timeIntervalSince(lastActivity)

        // Check handshake timeout (stricter for stuck TLS connections)
        if !handshakeComplete {
            if age > handshakeTimeout { return true }
        }

        // Check data idle timeout (more lenient for slow responses)
        if handshakeComplete {
            if idleTime > dataIdleTimeout { return true }
        }

        return false
    }

    func updateActivity() {
        lastActivity = Date()
    }

    func markHandshakeComplete() {
        handshakeComplete = true
        updateActivity()
    }

    func shouldBypassMITM(_ host: String) -> Bool {
        // First check blacklist (always bypass these domains)
        if MITMDomainMatcher.host(host, matches: MITMDomainMatcher.mitmBypassDomains) {
            return true
        }

        // If whitelist is empty, intercept all (default behavior)
        if cachedWhitelist.isEmpty {
            return false
        }

        // Host not in whitelist, bypass MITM
        return !MITMDomainMatcher.host(host, matches: cachedWhitelist)
    }

    init(id: UUID, clientConnection: NWConnection, clashPort: UInt16, cachedWhitelist: [String], resilienceEnabled: Bool) {
        self.clashPort = clashPort
        self.clientConnection = clientConnection
        self.cachedWhitelist = cachedWhitelist
        self.resilienceEnabled = resilienceEnabled
    }

    func start() {
        // Debug Log
        // Starting new connection

        clientConnection.stateUpdateHandler = { [weak self] state in
             guard let self = self else { return }
             // Debug Log
             // Client state update
             Task { await self.handleClientState(state) }
        }
        clientConnection.start(queue: .global())
        readClient()
    }

    func stop() {
        // CRITICAL: Prevent multiple stop calls
        guard !isStopped else { return }
        isStopped = true

        // Debug Log
        // Stopping connection

        // Remove state handlers to prevent further callbacks
        clientConnection.stateUpdateHandler = nil
        serverConnection?.stateUpdateHandler = nil
        loopbackListener?.stateUpdateHandler = nil
        loopbackConnection?.stateUpdateHandler = nil
        decryptedConnection?.stateUpdateHandler = nil
        upstreamConnection?.stateUpdateHandler = nil

        // Cancel ALL connections to prevent resource leaks
        clientConnection.cancel()
        serverConnection?.cancel()
        loopbackListener?.cancel()
        loopbackConnection?.cancel()
        decryptedConnection?.cancel()
        upstreamConnection?.cancel()

        // Set all to nil to release memory and resources immediately
        serverConnection = nil
        loopbackListener = nil
        loopbackConnection = nil
        decryptedConnection = nil
        upstreamConnection = nil
        buffer.removeAll()

        // Remove from parent actor
        Task {
            await MITMBackend.shared.removeConnection(id: self.id)
        }
    }

    func handleClientState(_ state: NWConnection.State) {
        // CRITICAL: Check if already stopped
        guard !isStopped else { return }

        switch state {
        case .failed, .cancelled:
            stop()
        default:
            break
        }
    }
}
