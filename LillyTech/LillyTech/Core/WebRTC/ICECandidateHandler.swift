import OSLog

class ICECandidateHandler<Connection: PeerConnectionType, Candidate> {
    private let logger = Logger(subsystem: "com.app.webrtc", category: "ICEHandler")
    private let peerConnection: Connection
    var queuedCandidates: [Candidate] = []
    var isReady: Bool = false
    
    var onCandidateGenerated: ((Candidate) -> Void)?
    
    init(peerConnection: Connection) {
        self.peerConnection = peerConnection
    }
    
    func setReady(_ ready: Bool) {
        isReady = ready
        if ready {
            processQueuedCandidates()
        }
    }
    
    func addCandidate(_ candidate: Candidate) {
        guard isReady else {
            self.queuedCandidates.append(candidate)
            logger.debug("Queued ICE candidate, total queued: \(self.queuedCandidates.count)")
            return
        }
        
        peerConnection.add(candidate) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to add ICE candidate: \(error.localizedDescription)")
                return
            }
            self?.logger.debug("Added ICE candidate successfully")
        }
    }
    
    func handleGeneratedCandidate(_ candidate: Candidate) {
        logger.debug("Generated ICE candidate")
        onCandidateGenerated?(candidate)
    }
    
    private func processQueuedCandidates() {
        guard !self.queuedCandidates.isEmpty else { return }
        
        logger.debug("Processing \(self.queuedCandidates.count) queued candidates")
        self.queuedCandidates.forEach { addCandidate($0) }
        self.queuedCandidates.removeAll()
    }
    
    func reset() {
        queuedCandidates.removeAll()
        isReady = false
    }
}
