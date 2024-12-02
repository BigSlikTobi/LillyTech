import WebRTC
import OSLog

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
            logger.error("Max reconnection attempts reached or already reconnecting")
            return
        }
        
        isReconnecting = true
        retryCount += 1
        
        logger.info("Initiating reconnection attempt \(self.retryCount)/\(self.maxRetries)")
        
        // Store current session state
        storeCurrentState()
        
        // Schedule reconnection with exponential backoff
        let delay = pow(2.0, Double(retryCount - 1))
        reconnectionTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.executeReconnection()
        }
    }
    
    private func executeReconnection() {
        guard let service = service else { return }
        
        logger.info("Executing reconnection...")
        
        // Clean up existing connection
        service.disconnect()
        
        // Restore connection
        service.connect()
        
        // Restore session state if available
        if let sdp = lastSessionDescription {
            service.handleRemoteSessionDescription(sdp)
        }
        
        // Restore ICE candidates
        lastICECandidates.forEach { candidate in
            service.handleRemoteCandidate(candidate)
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
    
    func addICECandidate(_ candidate: RTCIceCandidate) {
        lastICECandidates.append(candidate)
    }
    
    func setWebRTCService(_ service: Service) {
        self.service = service
    }
}
