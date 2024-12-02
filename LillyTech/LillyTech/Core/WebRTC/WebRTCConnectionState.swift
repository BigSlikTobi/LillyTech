import WebRTC

enum WebRTCConnectionState {
    case new
    case connecting
    case connected
    case disconnected
    case failed
    case closed
    
    init(from rtcState: RTCPeerConnectionState) {
        switch rtcState {
        case .new: self = .new
        case .connecting: self = .connecting
        case .connected: self = .connected
        case .disconnected: self = .disconnected
        case .failed: self = .failed
        case .closed: self = .closed
        @unknown default: self = .failed
        }
    }
}

struct ConnectionQualityMetrics {
    let bitrate: Double
    let packetLoss: Double
    let roundTripTime: TimeInterval
    
    var qualityLevel: QualityLevel {
        switch (bitrate, packetLoss) {
        case _ where packetLoss > 10: return .poor
        case (let b, _) where b < 50: return .poor
        case (let b, _) where b < 150: return .medium
        default: return .good
        }
    }
    
    enum QualityLevel {
        case poor
        case medium
        case good
    }
}
