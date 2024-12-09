import WebRTC
import OSLog

enum ConnectionRecoveryState {
    case idle
    case attempting
    case backingOff
    case rotating
    case failed
}

class WebRTCReconnectionManager<Service: WebRTCService> {
    private let logger = Logger(subsystem: "com.app.webrtc", category: "Reconnection")
    private weak var service: Service?
    private var retryCount = 0
    private let maxRetries = 3
    private var isReconnecting = false
    private var reconnectionTimer: Timer?
    private var candidates: [RTCIceCandidate] = []
    
    // Store last known good state
    private var lastSessionDescription: RTCSessionDescription?
    private var lastICECandidates: [RTCIceCandidate] = []
    
    // Change initializer to not require WebRTCServiceImpl
    init() {
        // Empty init, service will be set later
    }
    
    private let initialBackoffDelay = 1.0
    private let maxBackoffDelay = 32.0
    private let jitterFactor = 0.1
    private let serverRotationThreshold = 2
    
    private var currentState: ConnectionRecoveryState = .idle
    private var consecutiveFailures = 0
    private var totalRetryAttempts = 0
    private var successfulReconnections = 0
    private var currentServerIndex = 0
    private var lastAttemptTimestamp: Date?
    
    private var servers: [String] = [] // ICE server URLs
    
    func handleConnectionStateChange(_ state: RTCPeerConnectionState) {
        switch state {
        case .failed, .disconnected:
            initiateReconnection()
        case .connected:
            resetReconnectionState()
        default:
            break
        }
    }
    
    private func initiateReconnection() {
        guard !isReconnecting && retryCount < maxRetries else {
            currentState = .failed
            logger.error("Max reconnection attempts reached or already reconnecting")
            return
        }
        
        isReconnecting = true
        retryCount += 1
        totalRetryAttempts += 1
        currentState = .attempting
        lastAttemptTimestamp = Date()
        
        logger.info("Initiating reconnection attempt \(self.retryCount)/\(self.maxRetries)")
        
        // Store current session state
        storeCurrentState()
        
        let backoffDelay = calculateBackoffDelay()
        if retryCount >= serverRotationThreshold {
            rotateServer()
        }
        
        // Schedule reconnection with exponential backoff
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: backoffDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.executeReconnection()
        }
    }
    
    private func calculateBackoffDelay() -> TimeInterval {
        let baseDelay = min(maxBackoffDelay, initialBackoffDelay * pow(2.0, Double(retryCount - 1)))
        let jitter = baseDelay * jitterFactor * Double.random(in: -1...1)
        return baseDelay + jitter
    }
    
    private func rotateServer() {
        currentState = .rotating
        currentServerIndex = (currentServerIndex + 1) % max(1, servers.count)
        logger.info("Rotating to server index: \(self.currentServerIndex)")
    }
    
    private func executeReconnection() {
        guard let weakService = service else {
            logger.error("Service not available for reconnection")
            return
        }
        
        logger.info("Executing reconnection...")
        
        // Clean up existing connection
        weakService.disconnect()
        
        // Restore connection
        weakService.connect()
        
        // Restore session state if available
        if let sdp = lastSessionDescription {
            weakService.handleRemoteSessionDescription(sdp)
        }
        
        // Restore ICE candidates
        lastICECandidates.forEach { candidate in
            weakService.handleRemoteCandidate(candidate)
        }
        
        updateConnectionMetrics()
        if !self.servers.isEmpty {
            self.currentServerIndex = (self.currentServerIndex + 1) % self.servers.count
        }
    }
    
    private func storeCurrentState() {
        guard let service = service else { return }
        
        // Store current session description
        lastSessionDescription = service.peerConnection.remoteDescription
        
        logger.debug("Stored session state for recovery")
    }
    
    private func resetReconnectionState() {
        isReconnecting = false
        retryCount = 0
        reconnectionTimer?.invalidate()
        reconnectionTimer = nil
        lastICECandidates.removeAll()
        lastSessionDescription = nil
        
        logger.info("Reset reconnection state")
    }
    
    private func updateConnectionMetrics() {
        if currentState == .attempting {
            successfulReconnections += 1
            consecutiveFailures = 0
        } else {
            consecutiveFailures += 1
        }
    }
    
    func getReconnectionStats() -> (attempts: Int, successes: Int, failureRate: Double) {
        let failureRate = totalRetryAttempts > 0 
            ? Double(totalRetryAttempts - successfulReconnections) / Double(totalRetryAttempts) 
            : 0.0
        return (totalRetryAttempts, successfulReconnections, failureRate)
    }
    
    func addICECandidate(_ candidate: RTCIceCandidate) {
        lastICECandidates.append(candidate)
    }
    
    func setWebRTCService(_ service: Service) {
        self.service = service
    }
    
    func setICEServers(_ serverURLs: [String]) {
        self.servers = serverURLs
    }
}
