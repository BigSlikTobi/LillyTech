import WebRTC

/* Temporarily commented out until impact of removal is assessed
protocol RTCPeerConnectionProtocol: AnyObject {
    var connectionState: RTCPeerConnectionState { get }
    var localDescription: RTCSessionDescription? { get }
    var remoteDescription: RTCSessionDescription? { get }
    
    func add(_ candidate: RTCIceCandidate, completionHandler: @escaping ((Error?) -> Void))
    func close()
}

extension RTCPeerConnection: RTCPeerConnectionProtocol {}
*/
