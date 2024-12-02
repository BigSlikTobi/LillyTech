import XCTest
import WebRTC
@testable import LillyTech

protocol WebRTCServiceRequirements {
    var connectionState: RTCPeerConnectionState { get }
    var peerConnection: RTCPeerConnection { get }
    func connect()
    func disconnect()
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription)
    func handleRemoteCandidate(_ candidate: RTCIceCandidate)
}

protocol TestPeerConnectionProtocol {
    var connectionState: RTCPeerConnectionState { get }
    var localDescription: RTCSessionDescription? { get }
    var remoteDescription: RTCSessionDescription? { get set }
    func add(_ candidate: RTCIceCandidate, completionHandler: ((Error?) -> Void)?)
    func close()
}

class MockPeerConnection: TestPeerConnectionProtocol {
    var mockRemoteDescription: RTCSessionDescription?
    var connectionState: RTCPeerConnectionState = .new
    
    // Add required properties
    var localDescription: RTCSessionDescription?
    var remoteDescription: RTCSessionDescription? {
        get { return mockRemoteDescription }
        set { 
            mockRemoteDescription = newValue
            // Notify any completion handlers if needed
        }
    }
    
    func add(_ candidate: RTCIceCandidate, completionHandler: ((Error?) -> Void)?) {
        completionHandler?(nil)
    }
    
    func close() {}
}

// Update MockWebRTCService to conform to WebRTCService directly
class MockWebRTCService: WebRTCService {
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()
    
    var delegate: WebRTCServiceDelegate?
    var connectCalled = false
    var disconnectCalled = false
    var handleRemoteSDPCalled = false
    var handleRemoteCandidateCalled = false
    
    let mockPeerConnection = MockPeerConnection()
    private let rtcPeerConnection: RTCPeerConnection
    
    var restoredSDP: RTCSessionDescription?
    private var storedRemoteDescription: RTCSessionDescription?
    
    init() {
        let config = RTCConfiguration()
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        self.rtcPeerConnection = Self.factory.peerConnection(with: config, constraints: constraints, delegate: nil)!
    }
    
    var connectionState: RTCPeerConnectionState {
        return mockPeerConnection.connectionState
    }
    
    var peerConnection: RTCPeerConnection {
        // Return mock peer connection instead of real one to control testing
        return rtcPeerConnection
    }
    
    // Add any missing protocol requirements here
    var isConnected: Bool = false
    
    func connect() {
        connectCalled = true
        // Restore the saved remote description during reconnection
        if let savedSDP = storedRemoteDescription {
            handleRemoteSessionDescription(savedSDP)
        }
    }
    
    func disconnect() {
        disconnectCalled = true
        // Store the current remote description before disconnecting
        storedRemoteDescription = mockPeerConnection.remoteDescription
    }
    
    func handleRemoteSessionDescription(_ sdp: RTCSessionDescription) {
        handleRemoteSDPCalled = true
        restoredSDP = sdp
        mockPeerConnection.remoteDescription = sdp
    }
    
    func handleRemoteCandidate(_ candidate: RTCIceCandidate) {
        handleRemoteCandidateCalled = true
    }
}

// Update test class to use TestWebRTCServiceType
class ReconnectionManagerTests: XCTestCase {
    var reconnectionManager: WebRTCReconnectionManager<MockWebRTCService>!
    var mockService: MockWebRTCService!
    
    override func setUp() {
        super.setUp()
        reconnectionManager = WebRTCReconnectionManager<MockWebRTCService>()
        mockService = MockWebRTCService()
        reconnectionManager.setWebRTCService(mockService)
    }
    
    override func tearDown() {
        reconnectionManager = nil
        mockService = nil
        super.tearDown()
    }
    
    func testConnectionRecovery() {
        // Test initial disconnection
        reconnectionManager.handleConnectionStateChange(.disconnected)
        
        // Wait for reconnection attempt
        let expectation = XCTestExpectation(description: "Reconnection attempt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        XCTAssertTrue(mockService.disconnectCalled, "Disconnect should be called during recovery")
        XCTAssertTrue(mockService.connectCalled, "Connect should be called during recovery")
    }
    
    func testSessionPersistence() {
        // Set up mock remote description
        let mockSDP = RTCSessionDescription(type: .answer, sdp: "mock_sdp")
        mockService.handleRemoteSessionDescription(mockSDP) // Use the service method instead of direct assignment
        
        // Trigger disconnection to store state
        reconnectionManager.handleConnectionStateChange(.disconnected)
        
        // Wait for reconnection attempt
        let expectation = XCTestExpectation(description: "Session restoration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        XCTAssertEqual(mockService.restoredSDP?.sdp, mockSDP.sdp, "SDP string should match")
        XCTAssertEqual(mockService.restoredSDP?.type, mockSDP.type, "SDP type should match")
        XCTAssertTrue(mockService.handleRemoteSDPCalled, "Remote SDP should be restored")
    }
    
    func testStreamRestoration() {
        // Add mock ICE candidate
        let mockCandidate = RTCIceCandidate(sdp: "mock_candidate", sdpMLineIndex: 0, sdpMid: "0")
        reconnectionManager.addICECandidate(mockCandidate)
        
        // Trigger disconnection
        reconnectionManager.handleConnectionStateChange(.disconnected)
        
        // Wait for reconnection attempt
        let expectation = XCTestExpectation(description: "Stream restoration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
        
        XCTAssertTrue(mockService.handleRemoteCandidateCalled, "ICE candidates should be restored")
    }
}
