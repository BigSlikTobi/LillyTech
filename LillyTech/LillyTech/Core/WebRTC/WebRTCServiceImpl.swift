import WebRTC
import AVFAudio
import OSLog

final class WebRTCServiceImpl: NSObject, WebRTCService {
    weak var delegate: WebRTCServiceDelegate?
    
    var connectionState: RTCPeerConnectionState {
        return peerConnection.connectionState
    }
    
    internal var peerConnection: RTCPeerConnection {
        return _peerConnection
    }
    private let _peerConnection: RTCPeerConnection
    
    private let factory: RTCPeerConnectionFactory
    private let audioSession = RTCAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.app.webrtc", category: "WebRTCService")
    private lazy var localAudioTrack: RTCAudioTrack = {
        return createLocalAudioTrack()
    }()
    
    init(configuration: RTCConfiguration) {
        self.factory = RTCPeerConnectionFactory()
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        guard let connection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: nil
        ) else {
            fatalError("Failed to create peer connection")
        }
        
        self._peerConnection = connection
        
        super.init()
        
        peerConnection.delegate = self
        peerConnection.add(localAudioTrack, streamIds: ["stream0"])
        logger.debug("WebRTC service initialized")
    }
    
    /// Connects to the WebRTC service by configuring the audio session and creating an offer.
    func connect() {
        configureAudioSession()
        createOffer()
    }
    
    /// Disconnects from the WebRTC service by closing the peer connection and resetting the audio session.
    func disconnect() {
        peerConnection.close()
        resetAudioSession()
        logger.debug("WebRTC connection closed")
    }
    
    /// Handles the remote session description by setting it on the peer connection and creating an answer if the type is offer.
    /// - Parameter sdp: The remote session description.
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription) {
        // Validate SDP first
        if sdp.sdp.isEmpty {
            delegate?.webRTCService(self, didEncounterError: .sdpGenerationFailed)
            return
        }

        peerConnection.setRemoteDescription(sdp) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to set remote description: \(error.localizedDescription)")
                // Added print statement for debugging
                print("setRemoteDescription error: \(error.localizedDescription)")
                self?.delegate?.webRTCService(self!, didEncounterError: .connectionFailed)
                return
            }
            
            if (sdp.type == .offer) {
                self?.createAnswer()
            }
        }
    }
    
    /// Handles the remote ICE candidate by adding it to the peer connection.
    /// - Parameter candidate: The remote ICE candidate.
    func handleRemoteCandidate(_ candidate: RTCIceCandidate) {
        peerConnection.add(candidate) { error in
            if let error = error {
                self.logger.error("Failed to add ICE candidate: \(error.localizedDescription)")
                self.delegate?.webRTCService(self, didEncounterError: .connectionFailed)
            }
        }
    }
    
    /// Configures the audio session for WebRTC by setting the category and activating it.
    private func configureAudioSession() {
        audioSession.lockForConfiguration()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Audio session configuration failed: \(error.localizedDescription)")
            delegate?.webRTCService(self, didEncounterError: .mediaError)
        }
        audioSession.unlockForConfiguration()
    }
    
    /// Resets the audio session by deactivating it.
    private func resetAudioSession() {
        audioSession.lockForConfiguration()
        try? AVAudioSession.sharedInstance().setActive(false)
        audioSession.unlockForConfiguration()
    }
    
    /// Creates an offer for the WebRTC connection and sets the local description.
    private func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        
        peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self.peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    self.logger.error("Local description failed: \(error.localizedDescription)")
                    return
                }
                self.delegate?.webRTCService(self, didGenerateOffer: sdp)
            }
        }
    }
    
    /// Creates an answer for the WebRTC connection and sets the local description.
    private func createAnswer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        
        peerConnection.answer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self.peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    self.logger.error("Local description failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Creates a local audio track for the peer connection.
    private func createLocalAudioTrack() -> RTCAudioTrack {
        let audioSource = factory.audioSource(with: nil)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }
}

extension WebRTCServiceImpl: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        logger.debug("Connection state changed: \(String(describing: state))")
        delegate?.webRTCService(self, didChangeConnectionState: state)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCService(self, didReceiveCandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.debug("ICE candidates removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.debug("Negotiation needed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.debug("ICE connection state changed: \(String(describing: newState))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.debug("ICE gathering state changed: \(String(describing: newState))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.debug("Stream removed: \(stream.streamId)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        logger.debug("Stream added: \(stream.streamId)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.debug("Data channel opened")
    }
    
    // Required protocol method
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        logger.debug("Signaling state changed: \(String(describing: state))")
    }
}