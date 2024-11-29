import WebRTC
import OSLog

enum WebRTCServiceError: Error {
    case connectionFailed
    case invalidState
    case mediaError
    case sdpGenerationFailed
}

// The WebRTCServiceDelegate protocol defines methods that notify the delegate about changes in the connection state, 
// receipt of new ICE candidates, errors encountered, and generation of SDP offers.
// The WebRTCService protocol defines the properties and methods that a WebRTC service must implement, 
// including managing the delegate, connection state, and handling remote session descriptions and ICE candidates.
protocol WebRTCServiceDelegate: AnyObject {
    func webRTCService(_ service: WebRTCService, didChangeConnectionState state: RTCPeerConnectionState)
    func webRTCService(_ service: WebRTCService, didReceiveCandidate candidate: RTCIceCandidate)
    func webRTCService(_ service: WebRTCService, didEncounterError error: WebRTCServiceError)
    func webRTCService(_ service: WebRTCService, didGenerateOffer sdp: RTCSessionDescription)
}

/// A protocol that defines the core functionalities for a WebRTC service.
/// Classes conforming to this protocol should implement methods and properties
/// required to manage WebRTC connections and communication.
///
/// This protocol is intended to be used within the WebRTC module of the LillyTech project.
protocol WebRTCService: AnyObject {
    var delegate: WebRTCServiceDelegate? { get set }
    var connectionState: RTCPeerConnectionState { get }
    
    func connect()
    func disconnect()
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription) 
    func handleRemoteCandidate(_ candidate: RTCIceCandidate)
}

/// The `WebRTCServiceImplementation` class is an implementation of the `WebRTCService` protocol.
/// It provides the necessary functionality to manage WebRTC connections and interactions.
/// This class inherits from `NSObject` to leverage Objective-C runtime features.
class WebRTCServiceImplementation: NSObject, WebRTCService {
    weak var delegate: WebRTCServiceDelegate?
    private let logger = Logger(subsystem: "com.app.webrtc", category: "WebRTCService")
    
    var connectionState: RTCPeerConnectionState {
        return _peerConnection.connectionState
    }
    
    private var _peerConnection: RTCPeerConnection
    private let factory: RTCPeerConnectionFactory
    
    init(configuration: RTCConfiguration) {
        factory = RTCPeerConnectionFactory()
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
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
        
        _peerConnection.delegate = self
        logger.debug("WebRTC service initialized")
    }
    
    func connect() {
        // Implement connection logic
        createOffer()
    }
    
    func disconnect() {
        _peerConnection.close()
    }
    
    /// Handles the remote session description received from the WebRTC connection.
    /// - Parameter sdp: The session description protocol (SDP) object containing the remote session description.
    /// This function processes the remote SDP to establish the WebRTC connection.
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription) {
        // Validate SDP first
        if sdp.sdp.isEmpty {
            delegate?.webRTCService(self, didEncounterError: .sdpGenerationFailed)
            return
        }

        _peerConnection.setRemoteDescription(sdp) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to set remote description: \(error.localizedDescription)")
                self?.delegate?.webRTCService(self!, didEncounterError: .connectionFailed)
                return
            }
            
            if sdp.type == .offer {
                self?.createAnswer()
            }
        }
    }
    
    /// Handles the remote ICE candidate received from the signaling server.
    /// This function processes the given `RTCIceCandidate` and adds it to the
    /// appropriate peer connection to establish a connection with the remote peer.
    /// - Parameter candidate: The `RTCIceCandidate` object representing the remote
    ///   candidate to be added to the peer connection.
    func handleRemoteCandidate(_ candidate: RTCIceCandidate) {
        _peerConnection.add(candidate) { _ in
            // Success case - no action needed
        }
    }
    
    /// Creates an SDP offer to initiate the WebRTC connection.
    private func createOffer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        
        _peerConnection.offer(for: constraints) { [weak self] sdp, _ in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self._peerConnection.setLocalDescription(sdp) { _ in
                self.delegate?.webRTCService(self, didGenerateOffer: sdp)
            }
        }
    }
    
    /// Creates an SDP answer in response to the received offer.
    private func createAnswer() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true"],
            optionalConstraints: nil
        )
        
        _peerConnection.answer(for: constraints) { [weak self] sdp, _ in
            guard let self = self, let sdp = sdp else {
                self?.delegate?.webRTCService(self!, didEncounterError: .sdpGenerationFailed)
                return
            }
            
            self._peerConnection.setLocalDescription(sdp) { _ in
                // Success case - answer set
            }
        }
    }
}

/// Extension to conform to the `RTCPeerConnectionDelegate` protocol.
extension WebRTCServiceImplementation: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCPeerConnectionState) {
        delegate?.webRTCService(self, didChangeConnectionState: state)
        logger.debug("Connection state changed: \(String(describing: state))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        delegate?.webRTCService(self, didReceiveCandidate: candidate)
        logger.debug("ICE candidate generated")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        logger.debug("Signaling state changed: \(String(describing: state))")
    }
       
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        logger.debug("Stream added: \(stream.streamId)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.debug("Stream removed: \(stream.streamId)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.debug("ICE connection state changed: \(String(describing: newState))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.debug("ICE gathering state changed: \(String(describing: newState))")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.debug("ICE candidates removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.debug("Negotiation needed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.debug("Data channel opened")
    }
}