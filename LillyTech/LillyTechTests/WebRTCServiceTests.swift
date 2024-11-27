import XCTest
import WebRTC
@testable import LillyTech

final class MockWebRTCServiceDelegate: WebRTCServiceDelegate {
    var connectionStateChanged: RTCPeerConnectionState?
    var receivedCandidate: RTCIceCandidate?
    var encounteredError: WebRTCServiceError?
    var generatedOffer: RTCSessionDescription?
    
    func webRTCService(_ service: WebRTCService, didChangeConnectionState state: RTCPeerConnectionState) {
        connectionStateChanged = state
    }
    
    func webRTCService(_ service: WebRTCService, didReceiveCandidate candidate: RTCIceCandidate) {
        receivedCandidate = candidate
    }
    
    func webRTCService(_ service: WebRTCService, didEncounterError error: WebRTCServiceError) {
        encounteredError = error
    }
    
    func webRTCService(_ service: WebRTCService, didGenerateOffer sdp: RTCSessionDescription) {
        generatedOffer = sdp
    }
}

final class WebRTCServiceTests: XCTestCase {
    var sut: WebRTCServiceImpl!
    var delegate: MockWebRTCServiceDelegate!
    var config: RTCConfiguration!
    
    override func setUp() {
        super.setUp()
        config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        config.sdpSemantics = .unifiedPlan
        sut = WebRTCServiceImpl(configuration: config)
        delegate = MockWebRTCServiceDelegate()
        sut.delegate = delegate
    }
    
    override func tearDown() {
        sut.disconnect()
        sut = nil
        delegate = nil
        config = nil
        super.tearDown()
    }
    
    func testInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertEqual(sut.connectionState, .new)
    }
    
    func testConnect() {
        sut.connect()
        // Wait for async operations
        let expectation = XCTestExpectation(description: "Connection offer generated")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertNotNil(self.delegate.generatedOffer)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testHandleRemoteSessionDescription() {
        // Create a local offer to generate a valid SDP
        let expectation = XCTestExpectation(description: "Remote description handled")
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        sut.peerConnection.offer(for: constraints) { [weak self] sdp, error in
            guard let self = self, let sdp = sdp else {
                XCTFail("Failed to create local offer")
                return
            }
            
            // Now, test handling this SDP as remote SDP
            self.sut.handleRemoteSessionDescription(sdp)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                XCTAssertNil(self.delegate.encounteredError, "Valid SDP should not cause error")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testHandleInvalidRemoteSessionDescription() {
        let invalidSdp = RTCSessionDescription(type: .offer, sdp: "")
        let expectation = XCTestExpectation(description: "Invalid SDP handled")
    
        sut.handleRemoteSessionDescription(invalidSdp)
    
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(
                self.delegate.encounteredError,
                .sdpGenerationFailed,
                "Empty SDP should trigger generation failed error"
            )
            expectation.fulfill()
        }
    
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testHandleRemoteCandidate() {
        let candidate = RTCIceCandidate(
            sdp: "candidate:1 1 UDP 2122260223 192.168.1.1 30000 typ host",
            sdpMLineIndex: 0,
            sdpMid: "data"
        )
        sut.handleRemoteCandidate(candidate)
        // Should not crash or throw
    }
    
    func testDisconnect() {
        sut.connect()
        sut.disconnect()
        XCTAssertEqual(sut.connectionState, .closed)
    }
    
    func testDelegateConnectionStateCallback() {
        let expectation = XCTestExpectation(description: "Connection state changed")
        
        // Force connection state change by connecting
        sut.connect()
        
        // Directly trigger connection state change through delegate method
        sut.peerConnection(sut.peerConnection, didChange: RTCPeerConnectionState.connected)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertNotNil(self.delegate.connectionStateChanged, "Connection state should be updated")
            XCTAssertEqual(self.delegate.connectionStateChanged, RTCPeerConnectionState.connected, "Connection state should be connected")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testErrorHandling() {
        let expectation = XCTestExpectation(description: "Error handled")
        
        // Simulate invalid SDP
        let invalidSdp = RTCSessionDescription(type: .offer, sdp: "")
        sut.handleRemoteSessionDescription(invalidSdp)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            XCTAssertEqual(
                self.delegate.encounteredError, 
                .sdpGenerationFailed, // Changed from .connectionFailed
                "Empty SDP should trigger generation failed error"
            )
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}