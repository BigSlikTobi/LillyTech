import XCTest
import WebRTC
@testable import LillyTech
@testable import Starscream

class MockWebSocket: WebSocket {
    var connectCallCount = 0
    var disconnectCallCount = 0
    var writeCallCount = 0
    var lastWrittenMessage: String?
    var isConnected = false
    
    override func connect() {
        connectCallCount += 1
    }
    
    override func disconnect(closeCode: UInt16 = 1000) {
        disconnectCallCount += 1
    }
    
    override func write(string: String, completion: (() -> ())?) {
        writeCallCount += 1
        lastWrittenMessage = string
        completion?()
    }
    
    func simulateConnection() {
        isConnected = true
        delegate?.didReceive(event: .connected([String: String]()), client: self)
    }
    
    func simulateDisconnection(reason: String = "", code: UInt16 = 0) {
        isConnected = false
        delegate?.didReceive(event: .disconnected(reason, code), client: self)
    }
    
    func simulateError(_ error: Error) {
        delegate?.didReceive(event: .error(error), client: self)
    }
}

class SignalingServiceTests: XCTestCase {
    var signalingService: WebSocketSignalingService!
    var mockWebSocket: MockWebSocket!
    var mockDelegate: MockSignalingDelegate!
    
    override func setUp() {
        super.setUp()
        let url = URL(string: "wss://example.com")!
        signalingService = WebSocketSignalingService(url: url)
        mockWebSocket = MockWebSocket(request: URLRequest(url: url))
        signalingService.socket = mockWebSocket
        mockWebSocket.delegate = signalingService 
        mockDelegate = MockSignalingDelegate()
        signalingService.delegate = mockDelegate
    }
    
    override func tearDown() {
        signalingService = nil
        super.tearDown()
    }
    
    private func normalizeJSON(_ jsonString: String) throws -> [String: Any] {
        guard let data = jsonString.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebRTCSignalingError.invalidMessage
        }
        return json
    }

    private func assertEqualJSON(_ message: String, _ expected: String, file: StaticString = #file, line: UInt = #line) throws {
        let normalizedMessage = try normalizeJSON(message)
        let normalizedExpected = try normalizeJSON(expected)
        XCTAssertEqual(NSDictionary(dictionary: normalizedMessage), NSDictionary(dictionary: normalizedExpected), file: file, line: line)
    }

    private func normalizeSDP(_ sdp: String) -> String {
        return sdp.replacingOccurrences(of: "\\r\\n", with: "\r\n")
    }

    func testEncodingSDPOfferMessage() throws {
        // Use a simplified SDP string without newlines for testing
        let sdpString = "v=0\\r\\no=- 4611732939996472648 2 IN IP4 127.0.0.1\\r\\ns=-\\r\\n"
        let rtcSessionDescription = RTCSessionDescription(type: .offer, sdp: sdpString)
        let sessionDescription = SessionDescription(from: rtcSessionDescription)
        let event = SignalingEvent.offer(sessionDescription)
        
        let message = try signalingService.encodeMessage(event)
        
        // Decode and verify the structure
        let decoded = try normalizeJSON(message)
        XCTAssertEqual(decoded["type"] as? String, "offer")
        let payload = decoded["payload"] as? [String: Any]
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?["sdp"] as? String, sdpString)
        XCTAssertEqual(payload?["target"] as? String, "")
    }

    func testDecodingSDPAnswerMessage() throws {
        let sdpString = "v=0\\r\\no=- 4611732939996472650 2 IN IP4 127.0.0.1\\r\\ns=-\\r\\n"
        let jsonString = """
        {"type":"answer","payload":{"sdp":"\(sdpString)","target":""}}
        """
        
        let event = try signalingService.decodeMessage(jsonString)
        
        guard case let .answer(sessionDescription) = event else {
            XCTFail("Expected .answer event")
            return
        }
        
        XCTAssertEqual(normalizeSDP(sessionDescription.sdp), normalizeSDP(sdpString))
        XCTAssertEqual(sessionDescription.type, .answer)
    }

    func testEncodingICECandidateMessage() throws {
        let candidate = "candidate:1 1 UDP 2122252543 192.168.1.2 54400 typ host"
        let rtcCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: 0, sdpMid: "audio")
        let iceCandidate = IceCandidate(from: rtcCandidate)
        let event = SignalingEvent.candidate(iceCandidate)
        
        let message = try signalingService.encodeMessage(event)
        let expectedJSON = """
        {"type":"ice-candidate","payload":{"candidate":{"candidate":"\(candidate)","sdpMLineIndex":0,"sdpMid":"audio"},"target":""}}
        """
        
        try assertEqualJSON(message, expectedJSON)
    }

    func testDecodingRoomManagementMessages() throws {
        // Mock peer joined message
        let peerJoinedJSON = """
        {"type":"peer-joined","payload":{"peerId":"user123"}}
        """
        
        let joinEvent = try signalingService.decodeMessage(peerJoinedJSON)
        if case let .peerJoined(peerId) = joinEvent {
            XCTAssertEqual(peerId, "user123")
        } else {
            XCTFail("Expected .peerJoined event")
        }
        
        // Mock peer left message
        let peerLeftJSON = """
        {"type":"peer-left","payload":{"peerId":"user123"}}
        """
        
        let leaveEvent = try signalingService.decodeMessage(peerLeftJSON)
        if case let .peerLeft(peerId) = leaveEvent {
            XCTAssertEqual(peerId, "user123")
        } else {
            XCTFail("Expected .peerLeft event")
        }
    }
    
    func testInvalidMessageDecoding() {
        // Invalid message
        let invalidJSON = """
        {"type":"unknown","payload":{}}
        """
        
        XCTAssertThrowsError(try signalingService.decodeMessage(invalidJSON)) { error in
            if case WebRTCSignalingError.invalidMessage = error {
                // Test passes
            } else {
                XCTFail("Expected WebRTCSignalingError.invalidMessage but got \(error)")
            }
        }
    }
    
    func testConnectionLifecycle() {
        // Test connect
        let connectExpectation = expectation(description: "Delegate should be notified of connection")
        let disconnectExpectation = expectation(description: "Delegate should be notified of disconnection")
        
        mockDelegate.connectCallback = {
            connectExpectation.fulfill()
        }
        mockDelegate.disconnectCallback = {
            disconnectExpectation.fulfill()
        }
        
        // Test connect
        signalingService.connect()
        XCTAssertEqual(mockWebSocket.connectCallCount, 1)
        
        // Simulate successful connection
        mockWebSocket.simulateConnection()
        wait(for: [connectExpectation], timeout: 1.0)
        
        XCTAssertTrue(signalingService.isConnected)
        XCTAssertEqual(mockDelegate.connectCount, 1)
        
        // Test disconnect
        signalingService.disconnect()
        XCTAssertEqual(mockWebSocket.disconnectCallCount, 1)
        
        // Simulate disconnection
        mockWebSocket.simulateDisconnection()
        wait(for: [disconnectExpectation], timeout: 1.0)
        
        XCTAssertFalse(signalingService.isConnected)
        XCTAssertEqual(mockDelegate.disconnectCount, 1)
    }
    
    func testReconnectionAttempts() {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        // Simulate disconnection and verify reconnection attempts
        mockWebSocket.simulateDisconnection()
        
        // Wait for reconnection attempt
        let expectation = XCTestExpectation(description: "Reconnection attempt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        XCTAssertGreaterThan(mockWebSocket.connectCallCount, 1)
    }
    
    func testErrorHandling() {
        signalingService.connect()
        
        // Simulate WebSocket error
        let error = NSError(domain: "WebSocket", code: -1, userInfo: nil)
        mockWebSocket.simulateError(error)
        
        XCTAssertEqual(mockDelegate.lastError, .connectionFailed)
    }
}

class MockSignalingDelegate: SignalingServiceDelegate {
    var connectCount = 0
    var disconnectCount = 0
    var lastError: WebRTCSignalingError?
    var receivedEvents: [SignalingEvent] = []
    
    var connectCallback: (() -> Void)?
    var disconnectCallback: (() -> Void)?
    
    func signalingServiceDidConnect(_ service: SignalingService) {
        connectCount += 1
        connectCallback?()
    }
    
    func signalingServiceDidDisconnect(_ service: SignalingService) {
        disconnectCount += 1
        disconnectCallback?()
    }
    
    func signalingService(_ service: SignalingService, didEncounterError error: WebRTCSignalingError) {
        lastError = error
    }
    
    func signalingService(_ service: SignalingService, didReceiveEvent event: SignalingEvent) {
        receivedEvents.append(event)
    }
}

class MockTimer {
    var isValid = true
    var fireDate: Date
    var interval: TimeInterval
    var repeats: Bool
    var block: () -> Void
    
    init(fireDate: Date, interval: TimeInterval, repeats: Bool, block: @escaping () -> Void) {
        self.fireDate = fireDate
        self.interval = interval
        self.repeats = repeats
        self.block = block
    }
    
    func fire() {
        if isValid {
            block()
        }
    }
    
    func invalidate() {
        isValid = false
    }
}

extension SignalingServiceTests {
    func testHeartbeatMechanism() {
        let expectation = XCTestExpectation(description: "Reconnection after missed heartbeat")
        
        // Setup and initial connection
        signalingService.connect()
        mockWebSocket.simulateConnection()
        XCTAssertTrue(signalingService.isConnected)
        
        // Verify initial state
        XCTAssertEqual(mockWebSocket.connectCallCount, 1)
        
        // Simulate a working heartbeat first
        let heartbeatJSON = """
        {"type":"heartbeat","payload":{"timestamp":"\(ISO8601DateFormatter().string(from: Date()))"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(heartbeatJSON), client: mockWebSocket)
        
        // Simulate heartbeat timeout by triggering disconnection
        mockWebSocket.simulateDisconnection(reason: "Heartbeat timeout", code: 1001)
        
        // Wait for reconnection attempt
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { // Wait for reconnect delay
            XCTAssertGreaterThan(self.mockWebSocket.connectCallCount, 1)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testHeartbeatCleanup() {
        // Initial connection
        signalingService.connect()
        mockWebSocket.simulateConnection()
        XCTAssertTrue(signalingService.isConnected)
        
        // Record initial connect count
        let initialConnectCount = mockWebSocket.connectCallCount
        
        // Verify heartbeat is working
        let heartbeatJSON = """
        {"type":"heartbeat","payload":{"timestamp":"\(ISO8601DateFormatter().string(from: Date()))"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(heartbeatJSON), client: mockWebSocket)
        
        // Explicitly disconnect (should cleanup heartbeat)
        signalingService.disconnect()
        
        // Simulate disconnection
        mockWebSocket.simulateDisconnection(reason: "Normal closure", code: 1000)
        
        // Wait to ensure no automatic reconnection happens after intentional disconnect
        let expectation = XCTestExpectation(description: "No reconnection after intentional disconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // Connect count should not increase after intentional disconnect
            XCTAssertEqual(self.mockWebSocket.connectCallCount, initialConnectCount)
            XCTAssertFalse(self.signalingService.isConnected)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 4.0)
    }
    
    func testMultipleHeartbeatCycles() {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        // Simulate multiple valid heartbeats
        for _ in 1...3 {
            let heartbeatJSON = """
            {"type":"heartbeat","payload":{"timestamp":"\(ISO8601DateFormatter().string(from: Date()))"}}
            """
            mockWebSocket.delegate?.didReceive(event: .text(heartbeatJSON), client: mockWebSocket)
        }
        
        // Should maintain single connection
        XCTAssertEqual(mockWebSocket.connectCallCount, 1)
        XCTAssertTrue(signalingService.isConnected)
    }
    
    func testRoomJoining() throws {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        let roomId = "test-room-123"
        signalingService.join(roomId: roomId)
        
        XCTAssertEqual(mockWebSocket.writeCallCount, 1)
        let expectedJSON = """
        {"type":"join-room","payload":{"roomId":"test-room-123"}}
        """
        try assertEqualJSON(mockWebSocket.lastWrittenMessage!, expectedJSON)
    }
    
    func testRoomLeaving() throws {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        let roomId = "test-room-123"
        signalingService.join(roomId: roomId)
        signalingService.leave(roomId: roomId)
        
        XCTAssertEqual(mockWebSocket.writeCallCount, 2)
        let expectedJSON = """
        {"type":"leave-room","payload":{"roomId":"test-room-123"}}
        """
        try assertEqualJSON(mockWebSocket.lastWrittenMessage!, expectedJSON)
    }
    
    func testMultipleParticipantsHandling() throws {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        // Simulate first peer joining
        let peerJoinedJSON = """
        {"type":"peer-joined","payload":{"peerId":"user123"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(peerJoinedJSON), client: mockWebSocket)
        
        XCTAssertEqual(mockDelegate.receivedEvents.count, 1)
        if case let .peerJoined(peerId) = mockDelegate.receivedEvents[0] {
            XCTAssertEqual(peerId, "user123")
        } else {
            XCTFail("Expected peer-joined event")
        }
        
        // Simulate second peer joining
        let secondPeerJSON = """
        {"type":"peer-joined","payload":{"peerId":"user456"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(secondPeerJSON), client: mockWebSocket)
        
        XCTAssertEqual(mockDelegate.receivedEvents.count, 2)
        if case let .peerJoined(peerId) = mockDelegate.receivedEvents[1] {
            XCTAssertEqual(peerId, "user456")
        } else {
            XCTFail("Expected peer-joined event")
        }
        
        // Simulate peer leaving
        let peerLeftJSON = """
        {"type":"peer-left","payload":{"peerId":"user123"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(peerLeftJSON), client: mockWebSocket)
        
        XCTAssertEqual(mockDelegate.receivedEvents.count, 3)
        if case let .peerLeft(peerId) = mockDelegate.receivedEvents[2] {
            XCTAssertEqual(peerId, "user123")
        } else {
            XCTFail("Expected peer-left event")
        }
    }
    
    func testRoomCleanupOnDisconnect() throws {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        let roomId = "test-room-123"
        signalingService.join(roomId: roomId)
        XCTAssertEqual(mockWebSocket.writeCallCount, 1)
        
        // Simulate disconnection
        mockWebSocket.simulateDisconnection()
        
        // Verify that reconnecting doesn't automatically rejoin room
        mockWebSocket.simulateConnection()
        XCTAssertEqual(mockWebSocket.writeCallCount, 1) // Should not have sent another join message
        
        // Verify we can join a new room after reconnection
        let newRoomId = "new-room-456"
        signalingService.join(roomId: newRoomId)
        XCTAssertEqual(mockWebSocket.writeCallCount, 2)
        
        let expectedJSON = """
        {"type":"join-room","payload":{"roomId":"new-room-456"}}
        """
        try assertEqualJSON(mockWebSocket.lastWrittenMessage!, expectedJSON)
    }
    
    func testInvalidRoomMessages() {
        signalingService.connect()
        mockWebSocket.simulateConnection()
        
        // Test invalid room message format
        let invalidRoomJSON = """
        {"type":"peer-joined","payload":{"invalid_field":"user123"}}
        """
        mockWebSocket.delegate?.didReceive(event: .text(invalidRoomJSON), client: mockWebSocket)
        
        XCTAssertEqual(mockDelegate.lastError, .invalidMessage)
    }
}

