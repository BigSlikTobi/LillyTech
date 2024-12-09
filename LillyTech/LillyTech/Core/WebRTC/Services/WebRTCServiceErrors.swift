import Foundation

enum WebRTCError: Error {
    case gatheringTimeout
    case stunServerFailure(server: String)
    case turnServerFailure(server: String)
    case iceConnectionFailed
    case mediaError
    case sdpGenerationFailed
    case connectionFailed
    
    var isRecoverable: Bool {
        switch self {
        case .stunServerFailure, .gatheringTimeout, .iceConnectionFailed:
            return true
        default:
            return false
        }
    }
    
    var recoveryStrategy: RecoveryStrategy {
        switch self {
        case .stunServerFailure:
            return .useFallbackServer
        case .gatheringTimeout:
            return .restart
        case .iceConnectionFailed:
            return .reconnect
        default:
            return .none
        }
    }
}

enum RecoveryStrategy {
    case useFallbackServer
    case restart
    case reconnect
    case none
}

struct WebRTCErrorMetrics {
    var errorCount: Int = 0
    var lastErrorTimestamp: Date?
    var recoveryAttempts: Int = 0
    var successfulRecoveries: Int = 0
    
    mutating func recordError(_ error: WebRTCError) {
        errorCount += 1
        lastErrorTimestamp = Date()
    }
}
