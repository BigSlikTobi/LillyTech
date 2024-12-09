import WebRTC
import Foundation

// MARK: - Room Management
struct Room: Codable, Identifiable {
    let id: String
    let name: String
    let participantCount: Int
    let createdAt: Date
    
    var isActive: Bool {
        participantCount > 0
    }
}

// MARK: - Signaling Events
enum SignalingEvent: Codable {
    case offer(SessionDescription)
    case answer(SessionDescription)
    case candidate(IceCandidate)
    case join(RoomInfo)
    case leave(RoomInfo)
    case error(WebRTCSignalingError)
    case peerJoined(peerId: String)
    case peerLeft(peerId: String)
    case heartbeat
    
    private enum CodingKeys: String, CodingKey {
        case type, payload
    }
    
    private enum EventType: String, Codable {
        case offer, answer, candidate, join, leave, error, peerJoined, peerLeft, heartbeat
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .offer(let desc):
            try container.encode(EventType.offer, forKey: .type)
            try container.encode(desc, forKey: .payload)
        case .answer(let desc):
            try container.encode(EventType.answer, forKey: .type)
            try container.encode(desc, forKey: .payload)
        case .candidate(let candidate):
            try container.encode(EventType.candidate, forKey: .type)
            try container.encode(candidate, forKey: .payload)
        case .join(let info):
            try container.encode(EventType.join, forKey: .type)
            try container.encode(info, forKey: .payload)
        case .leave(let info):
            try container.encode(EventType.leave, forKey: .type)
            try container.encode(info, forKey: .payload)
        case .error(let error):
            try container.encode(EventType.error, forKey: .type)
            try container.encode(error, forKey: .payload)
        case .peerJoined(let peerId):
            try container.encode(EventType.peerJoined, forKey: .type)
            try container.encode(peerId, forKey: .payload)
        case .peerLeft(let peerId):
            try container.encode(EventType.peerLeft, forKey: .type)
            try container.encode(peerId, forKey: .payload)
        case .heartbeat:
            try container.encode(EventType.heartbeat, forKey: .type)
            try container.encode(HeartbeatPayload(timestamp: Date()), forKey: .payload)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(EventType.self, forKey: .type)
        
        switch type {
        case .offer:
            let desc = try container.decode(SessionDescription.self, forKey: .payload)
            self = .offer(desc)
        case .answer:
            let desc = try container.decode(SessionDescription.self, forKey: .payload)
            self = .answer(desc)
        case .candidate:
            let candidate = try container.decode(IceCandidate.self, forKey: .payload)
            self = .candidate(candidate)
        case .join:
            let info = try container.decode(RoomInfo.self, forKey: .payload)
            self = .join(info)
        case .leave:
            let info = try container.decode(RoomInfo.self, forKey: .payload)
            self = .leave(info)
        case .error:
            let error = try container.decode(WebRTCSignalingError.self, forKey: .payload)
            self = .error(error)
        case .peerJoined:
            let peerId = try container.decode(String.self, forKey: .payload)
            self = .peerJoined(peerId: peerId)
        case .peerLeft:
            let peerId = try container.decode(String.self, forKey: .payload)
            self = .peerLeft(peerId: peerId)
        case .heartbeat:
            self = .heartbeat
        }
    }
}

// MARK: - Data Models
struct SessionDescription: Codable {
    let sdp: String
    let type: SDPType
    
    enum SDPType: String, Codable {
        case offer
        case answer
        case pranswer
        case rollback
    }
    
    init(from rtcDescription: RTCSessionDescription) {
        self.sdp = rtcDescription.sdp
        self.type = SDPType(from: rtcDescription.type)
    }
    
    var rtcSessionDescription: RTCSessionDescription {
        RTCSessionDescription(type: type.rtcType, sdp: sdp)
    }
}

struct IceCandidate: Codable {
    let candidate: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
    
    init(from rtcCandidate: RTCIceCandidate) {
        self.candidate = rtcCandidate.sdp
        self.sdpMLineIndex = rtcCandidate.sdpMLineIndex
        self.sdpMid = rtcCandidate.sdpMid
    }
    
    var rtcIceCandidate: RTCIceCandidate {
        RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
    }
}

struct RoomInfo: Codable {
    let roomId: String
    let userId: String
    let timestamp: Date
}

// Consolidated error type with new name
enum WebRTCSignalingError: LocalizedError, Codable, Equatable {
    case connectionFailed
    case invalidMessage
    case invalidState
    case disconnected
    case timeoutError
    case roomNotFound
    case serverError(String)
    
    static func == (lhs: WebRTCSignalingError, rhs: WebRTCSignalingError) -> Bool {
        switch (lhs, rhs) {
        case (.connectionFailed, .connectionFailed),
             (.invalidMessage, .invalidMessage),
             (.invalidState, .invalidState),
             (.disconnected, .disconnected),
             (.timeoutError, .timeoutError),
             (.roomNotFound, .roomNotFound):
            return true
        case (.serverError(let lhsMsg), .serverError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to establish signaling connection"
        case .invalidMessage:
            return "Received invalid signaling message"
        case .invalidState:
            return "Invalid signaling state"
        case .disconnected:
            return "Signaling connection disconnected"
        case .timeoutError:
            return "Signaling operation timed out"
        case .roomNotFound:
            return "Room not found"
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}

// MARK: - Server Error
struct ServerError: Codable {
    let type: String
    let message: String
}

// MARK: - Helper Extensions
private extension SessionDescription.SDPType {
    init(from rtcType: RTCSdpType) {
        switch rtcType {
        case .offer: self = .offer
        case .answer: self = .answer
        case .prAnswer: self = .pranswer
        case .rollback: self = .rollback
        @unknown default: self = .rollback
        }
    }
    
    var rtcType: RTCSdpType {
        switch self {
        case .offer: return .offer
        case .answer: return .answer
        case .pranswer: return .prAnswer
        case .rollback: return .rollback
        }
    }
}

// MARK: - Signaling Protocols
protocol SignalingServiceDelegate: AnyObject {
    func signalingService(_ service: SignalingService, didReceiveEvent event: SignalingEvent)
    func signalingService(_ service: SignalingService, didEncounterError error: WebRTCSignalingError)
    func signalingServiceDidConnect(_ service: SignalingService)
    func signalingServiceDidDisconnect(_ service: SignalingService)
}

protocol SignalingService: AnyObject {
    var delegate: SignalingServiceDelegate? { get set }
    var isConnected: Bool { get }
    
    func connect()
    func disconnect()
    func join(roomId: String)
    func leave(roomId: String)
    func send(event: SignalingEvent)
}
