import Foundation

// Base message structure for all server communications
struct ServerMessage<T: Codable>: Codable {
    let type: String
    let payload: T
}

// Payload types for different messages
struct JoinRoomPayload: Codable {
    let roomId: String
}

struct SDPPayload: Codable {
    let sdp: String
    let target: String
}

struct IceCandidatePayload: Codable {
    let candidate: IceCandidate
    let target: String
}

struct PeerPayload: Codable {
    let peerId: String
}

struct ErrorPayload: Codable {
    let type: String
    let message: String
}

struct HeartbeatPayload: Codable {
    let timestamp: Date
}
