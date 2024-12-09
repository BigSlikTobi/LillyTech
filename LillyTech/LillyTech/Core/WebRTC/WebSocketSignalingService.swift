import Foundation
import Starscream
import Combine
import WebRTC

final class WebSocketSignalingService: NSObject, SignalingService, WebSocketDelegate {
    weak var delegate: SignalingServiceDelegate?
    var socket: WebSocket?
    private let serverURL: URL
    private let reconnectStrategy: WebSocketReconnectionStrategy
    private var isReconnecting = false
    private var currentRoom: String?
    private var userId: String
    private let logger = AppLogger.shared
    private var isSocketConnected = false
    private var isIntentionalDisconnect = false // Add this flag
    
    private enum Constants {
        static let reconnectDelay: TimeInterval = 2.0
        static let maxReconnectAttempts = 5
        static let heartbeatTimeout: TimeInterval = 25.0 // Slightly more than server's 20s
    }
    
    private var heartbeatTimer: Timer?
    private var lastHeartbeat: Date?
    
    var isConnected: Bool {
        return isSocketConnected
    }
    
    init(url: URL, userId: String = UUID().uuidString) {
        self.serverURL = url
        self.userId = userId
        self.reconnectStrategy = WebSocketReconnectionStrategy(
            maxAttempts: Constants.maxReconnectAttempts,
            delay: Constants.reconnectDelay
        )
        super.init()
        setupWebSocket()
    }
    
    private func setupWebSocket() {
        var request = URLRequest(url: serverURL)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        socket?.delegate = self
    }
    
    private func setupHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Constants.heartbeatTimeout, repeats: true) { [weak self] _ in
            self?.handleMissedHeartbeat()
        }
    }
    
    private func handleMissedHeartbeat() {
        guard let last = lastHeartbeat else { return }
        if Date().timeIntervalSince(last) > Constants.heartbeatTimeout {
            logger.webrtc.warning("Missed heartbeat, reconnecting...", category: AppLogger.shared.signaling)
            disconnect()
            connect()
        }
    }
    
    // MARK: - SignalingService Protocol
    func connect() {
        isIntentionalDisconnect = false // Reset flag on connect
        logger.webrtc.debug("Connecting to signaling server...", category: AppLogger.shared.signaling)
        socket?.connect()
    }
    
    func disconnect() {
        isIntentionalDisconnect = true // Set flag to indicate intentional disconnect
        logger.webrtc.debug("Disconnecting from signaling server...", category: AppLogger.shared.signaling)
        socket?.disconnect()
        currentRoom = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        reconnectStrategy.reset()
    }
    
    func join(roomId: String) {
        currentRoom = roomId
        let roomInfo = RoomInfo(roomId: roomId, userId: userId, timestamp: Date())
        send(event: .join(roomInfo))
    }
    
    func leave(roomId: String) {
        let roomInfo = RoomInfo(roomId: roomId, userId: userId, timestamp: Date())
        send(event: .leave(roomInfo))
        currentRoom = nil
    }
    
    func send(event: SignalingEvent) {
        do {
            let message = try encodeMessage(event)
            socket?.write(string: message)
        } catch {
            delegate?.signalingService(self, didEncounterError: .invalidMessage)
        }
    }
    
    // MARK: - Private Methods
    private func handleDisconnection() {
        // Only attempt reconnection if disconnect was unintentional
        if !isIntentionalDisconnect && reconnectStrategy.shouldAttemptReconnection() {
            isReconnecting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.reconnectDelay) { [weak self] in
                self?.connect()
            }
        } else {
            isReconnecting = false
            reconnectStrategy.reset()
            delegate?.signalingService(self, didEncounterError: .disconnected)
        }
    }
    
    private func handleReceivedMessage(_ message: String) {
        do {
            let event = try decodeMessage(message)
            switch event {
            case .heartbeat:
                lastHeartbeat = Date()
            default:
                delegate?.signalingService(self, didReceiveEvent: event)
            }
        } catch {
            delegate?.signalingService(self, didEncounterError: .invalidMessage)
        }
    }
    
    func encodeMessage(_ event: SignalingEvent) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        let data: Data
        
        switch event {
        case .offer(let desc):
            let payload = SDPPayload(sdp: desc.sdp, target: "")
            let message = ServerMessage(type: "offer", payload: payload)
            data = try encoder.encode(message)
            
        case .answer(let desc):
            let payload = SDPPayload(sdp: desc.sdp, target: "")
            let message = ServerMessage(type: "answer", payload: payload)
            data = try encoder.encode(message)
            
        case .candidate(let ice):
            let payload = IceCandidatePayload(candidate: ice, target: "")
            let message = ServerMessage(type: "ice-candidate", payload: payload)
            data = try encoder.encode(message)
            
        case .join(let info):
            let payload = JoinRoomPayload(roomId: info.roomId)
            let message = ServerMessage(type: "join-room", payload: payload)
            data = try encoder.encode(message)
            
        case .leave(let info):
            let payload = JoinRoomPayload(roomId: info.roomId)
            let message = ServerMessage(type: "leave-room", payload: payload)
            data = try encoder.encode(message)
            
        case .error(let error):
            let payload = ErrorPayload(type: "error", message: error.localizedDescription)
            let message = ServerMessage(type: "error", payload: payload)
            data = try encoder.encode(message)
            
        case .peerJoined(let peerId):
            let payload = PeerPayload(peerId: peerId)
            let message = ServerMessage(type: "peer-joined", payload: payload)
            data = try encoder.encode(message)
            
        case .peerLeft(let peerId):
            let payload = PeerPayload(peerId: peerId)
            let message = ServerMessage(type: "peer-left", payload: payload)
            data = try encoder.encode(message)
            
        case .heartbeat:
            let payload = HeartbeatPayload(timestamp: Date())
            let message = ServerMessage(type: "heartbeat", payload: payload)
            data = try encoder.encode(message)
        }
        
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func decodeMessage(_ message: String) throws -> SignalingEvent {
        guard let data = message.data(using: .utf8) else {
            throw WebRTCSignalingError.invalidMessage
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let serverMessage = try decoder.decode(ServerMessage<AnyCodable>.self, from: data)
        
        switch serverMessage.type {
        case "offer":
            let serverMessage = try decoder.decode(ServerMessage<SDPPayload>.self, from: data)
            let rtcSessionDescription = RTCSessionDescription(type: .offer, sdp: serverMessage.payload.sdp)
            return .offer(SessionDescription(from: rtcSessionDescription))
            
        case "answer":
            let serverMessage = try decoder.decode(ServerMessage<SDPPayload>.self, from: data)
            let rtcSessionDescription = RTCSessionDescription(type: .answer, sdp: serverMessage.payload.sdp)
            return .answer(SessionDescription(from: rtcSessionDescription))
            
        case "ice-candidate":
            let serverMessage = try decoder.decode(ServerMessage<IceCandidatePayload>.self, from: data)
            let rtcCandidate = RTCIceCandidate(
                sdp: serverMessage.payload.candidate.candidate,
                sdpMLineIndex: serverMessage.payload.candidate.sdpMLineIndex,
                sdpMid: serverMessage.payload.candidate.sdpMid
            )
            return .candidate(IceCandidate(from: rtcCandidate))
        case "peer-joined":
            let serverMessage = try decoder.decode(ServerMessage<PeerPayload>.self, from: data)
            return .peerJoined(peerId: serverMessage.payload.peerId)
        case "peer-left":
            let serverMessage = try decoder.decode(ServerMessage<PeerPayload>.self, from: data)
            return .peerLeft(peerId: serverMessage.payload.peerId)
        case "heartbeat":
            return .heartbeat
        case "error":
            let serverMessage = try decoder.decode(ServerMessage<ErrorPayload>.self, from: data)
            return .error(WebRTCSignalingError.serverError(serverMessage.payload.message))
        default:
            throw WebRTCSignalingError.invalidMessage
        }
    }
    
    // MARK: - WebSocketDelegate Implementation
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .connected(_):
            isSocketConnected = true
            isReconnecting = false
            reconnectStrategy.reset()
            setupHeartbeat()
            lastHeartbeat = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.signalingServiceDidConnect(self)
            }
            
        case .disconnected(let reason, let code):
            isSocketConnected = false
            heartbeatTimer?.invalidate()
            heartbeatTimer = nil
            logger.webrtc.warning("WebSocket disconnected: \(reason) (code: \(code))", category: AppLogger.shared.signaling)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.signalingServiceDidDisconnect(self)
            }
            handleDisconnection()
            
        case .text(let string):
            if (string == "heartbeat") {
                lastHeartbeat = Date()
                return
            }
            handleReceivedMessage(string)
            
        case .error(let error):
            logger.webrtc.error("WebSocket error: \(error?.localizedDescription ?? "unknown")", category: AppLogger.shared.signaling)
            delegate?.signalingService(self, didEncounterError: .connectionFailed)
            
        case .cancelled:
            isSocketConnected = false
            handleDisconnection()
            
        default:
            break
        }
    }
}

// MARK: - Reconnection Strategy
private class WebSocketReconnectionStrategy {
    private let maxAttempts: Int
    private let delay: TimeInterval
    private var attempts = 0
    
    init(maxAttempts: Int, delay: TimeInterval) {
        self.maxAttempts = maxAttempts
        self.delay = delay
    }
    
    func shouldAttemptReconnection() -> Bool {
        attempts += 1
        return attempts <= maxAttempts
    }
    
    func reset() {
        attempts = 0
    }
}

private struct AnyCodable: Codable {
    private let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case is ():
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode value"))
        }
    }
}
