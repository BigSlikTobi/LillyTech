import WebRTC
import AVFAudio
import OSLog
import Foundation

// Unified protocol hierarchy
protocol PeerConnectionDelegate: AnyObject {
    func peerConnectionDidChangeState(_ state: RTCPeerConnectionState)
    func peerConnectionDidGenerateCandidate(_ candidate: RTCIceCandidate)
    func peerConnectionDidChangeICEState(_ state: RTCIceConnectionState)
}

/// Protocol defining the basic ICE candidate handling capabilities
protocol PeerConnectionType: AnyObject {
    var connectionState: RTCPeerConnectionState { get }
    func add(_ candidate: Any, completionHandler: @escaping (Error?) -> Void)
}

protocol PeerConnectionBase: PeerConnectionType {
    var localDescription: RTCSessionDescription? { get }
    var remoteDescription: RTCSessionDescription? { get }
    
    func statistics(_ completionHandler: @escaping (RTCStatisticsReport) -> Void)
}

protocol PeerConnection: PeerConnectionBase {
    var delegate: PeerConnectionDelegate? { get set }
    
    func setLocalDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void)
    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void)
    func addICECandidate(_ candidate: RTCIceCandidate)
    func createOffer(constraints: RTCMediaConstraints, completion: @escaping (RTCSessionDescription?, Error?) -> Void)
    func createAnswer(constraints: RTCMediaConstraints, completion: @escaping (RTCSessionDescription?, Error?) -> Void)
    func close()
}

// Wrapper class for RTCPeerConnection
class PeerConnectionWrapper: NSObject, PeerConnection, RTCPeerConnectionDelegate {
    weak var delegate: PeerConnectionDelegate?
    let rtcConnection: RTCPeerConnection
    
    var connectionState: RTCPeerConnectionState {
        return rtcConnection.connectionState
    }
    
    var localDescription: RTCSessionDescription? {
        return rtcConnection.localDescription
    }
    
    var remoteDescription: RTCSessionDescription? {
        return rtcConnection.remoteDescription
    }
    
    init(rtcConnection: RTCPeerConnection) {
        self.rtcConnection = rtcConnection
        super.init()
        self.rtcConnection.delegate = self
    }
    
    func setLocalDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        rtcConnection.setLocalDescription(sdp, completionHandler: completion)
    }
    
    func setRemoteDescription(_ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        rtcConnection.setRemoteDescription(sdp, completionHandler: completion)
    }
    
    func addICECandidate(_ candidate: RTCIceCandidate) {
        rtcConnection.add(candidate) { error in
            if let error = error {
                print("Failed to add ICE candidate: \(error.localizedDescription)")
            }
        }
    }
    
    func createOffer(constraints: RTCMediaConstraints, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        rtcConnection.offer(for: constraints, completionHandler: completion)
    }
    
    func createAnswer(constraints: RTCMediaConstraints, completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
        rtcConnection.answer(for: constraints, completionHandler: completion)
    }
    
    func close() {
        rtcConnection.close()
    }
    
    func add(_ candidate: Any, completionHandler: @escaping (Error?) -> Void) {
        if let iceCandidate = candidate as? RTCIceCandidate {
            addICECandidate(iceCandidate)
            completionHandler(nil)
        }
    }
    
    func statistics(_ completionHandler: @escaping (RTCStatisticsReport) -> Void) {
        rtcConnection.statistics(completionHandler: completionHandler)
    }
    
    // RTCPeerConnectionDelegate methods
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        delegate?.peerConnectionDidChangeState(state)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.peerConnectionDidGenerateCandidate(candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        delegate?.peerConnectionDidChangeICEState(newState)
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {}
}

// Add concrete type for ICE handling
class ICEConnectionHandler: PeerConnectionType {
    private let connection: PeerConnection
    
    var connectionState: RTCPeerConnectionState { connection.connectionState }
    
    init(connection: PeerConnection) {
        self.connection = connection
    }
    
    func add(_ candidate: Any, completionHandler: @escaping (Error?) -> Void) {
        connection.add(candidate, completionHandler: completionHandler)
    }
}

// Update WebRTCServiceImpl to use our custom protocols
final class WebRTCServiceImpl: NSObject, WebRTCService, PeerConnectionDelegate {
    weak var delegate: WebRTCServiceDelegate?
    private let wrappedConnection: PeerConnection  // Renamed from peerConnection
    private let factory: RTCPeerConnectionFactory
    private let audioSession = RTCAudioSession.sharedInstance()
    private let logger = Logger(subsystem: "com.app.webrtc", category: "WebRTCService")
    private lazy var localAudioTrack: RTCAudioTrack = {
        let audioSource = factory.audioSource(with: nil)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }()
    private let monitoringService: WebRTCMonitoringService
    private let iceHandler: ICECandidateHandler<ICEConnectionHandler, RTCIceCandidate>
    private let reconnectionManager: WebRTCReconnectionManager<WebRTCServiceImpl>
    
    init(configuration: WebRTCConfigurable) {
        self.factory = RTCPeerConnectionFactory()
        
        guard let rtcConnection = factory.peerConnection(
            with: configuration.configuration,
            constraints: configuration.defaultConstraints,
            delegate: nil
        ) else {
            fatalError("Failed to create peer connection")
        }
        
        let wrapper = PeerConnectionWrapper(rtcConnection: rtcConnection)
        self.wrappedConnection = wrapper  // Updated to use new name
        let iceConnection = ICEConnectionHandler(connection: wrapper)
        self.iceHandler = ICECandidateHandler<ICEConnectionHandler, RTCIceCandidate>(peerConnection: iceConnection)
        self.monitoringService = WebRTCMonitoringService(peerConnection: wrapper)
        self.reconnectionManager = WebRTCReconnectionManager<WebRTCServiceImpl>()
        
        super.init()
        
        // Set up dependencies after super.init
        reconnectionManager.setWebRTCService(self)
        wrapper.delegate = self
        rtcConnection.add(localAudioTrack, streamIds: ["stream0"])
        iceHandler.onCandidateGenerated = { [weak self] candidate in
            self?.delegate?.webRTCService(self!, didReceiveCandidate: candidate)
        }
        logger.debug("WebRTC service initialized")
    }
    
    /// Connects to the WebRTC service by configuring the audio session and creating an offer.
    func connect() {
        configureAudioSession()
        createOffer()
        monitoringService.startMonitoring()
    }
    
    /// Disconnects from the WebRTC service by closing the peer connection and resetting the audio session.
    func disconnect() {
        monitoringService.stopMonitoring()
        wrappedConnection.close()
        resetAudioSession()
        logger.debug("WebRTC connection closed")
    }
    
    /// Handles the remote session description by setting it on the peer connection and creating an answer if the type is offer.
    /// - Parameter sdp: The remote session description.
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription) {
        // Validate SDP first
        if (sdp.sdp.isEmpty) {
            delegate?.webRTCService(self, didEncounterError: .sdpGenerationFailed)
            return
        }

        wrappedConnection.setRemoteDescription(sdp) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to set remote description: \(error.localizedDescription)")
                // Added print statement for debugging
                print("setRemoteDescription error: \(error.localizedDescription)")
                self?.delegate?.webRTCService(self!, didEncounterError: .connectionFailed)
                return
            }
            
            self?.iceHandler.setReady(true)
            if (sdp.type == .offer) {
                self?.createAnswer()
            }
        }
    }
    
    /// Handles the remote ICE candidate by adding it to the peer connection.
    /// - Parameter candidate: The remote ICE candidate.
    func handleRemoteCandidate(_ candidate: RTCIceCandidate) {
        iceHandler.addCandidate(candidate)
        reconnectionManager.addICECandidate(candidate)
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
        
        wrappedConnection.createOffer(constraints: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self.wrappedConnection.setLocalDescription(sdp) { error in
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
        
        wrappedConnection.createAnswer(constraints: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self.wrappedConnection.setLocalDescription(sdp) { error in
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

    // Implement PeerConnectionDelegate methods
    func peerConnectionDidChangeState(_ state: RTCPeerConnectionState) {
        delegate?.webRTCService(self, didChangeConnectionState: state)
    }
    
    func peerConnectionDidGenerateCandidate(_ candidate: RTCIceCandidate) {
        delegate?.webRTCService(self, didReceiveCandidate: candidate)
    }
    
    func peerConnectionDidChangeICEState(_ state: RTCIceConnectionState) {
        if state == .disconnected || state == .failed {
            iceHandler.reset()
        }
    }
    
    var connectionState: RTCPeerConnectionState {
        return wrappedConnection.connectionState
    }
    
    var peerConnection: RTCPeerConnection {
        guard let wrapper = wrappedConnection as? PeerConnectionWrapper else {
            fatalError("Invalid peer connection state")
        }
        return wrapper.rtcConnection
    }
}
