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

final class MockWebRTCConfigurable: WebRTCConfigurable {
    var configuration: RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])]
        return config
    }
    
    var defaultConstraints: RTCMediaConstraints {
        return RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
    }
}

extension WebRTCServiceImpl {
    func simulateConnectionStateChange(to state: RTCPeerConnectionState) {
        // Directly call the delegate method
        self.peerConnectionDidChangeState(state)
    }
}

final class WebRTCServiceTests: XCTestCase {
    var sut: WebRTCServiceImpl!
    var delegate: MockWebRTCServiceDelegate!
    var config: MockWebRTCConfigurable!
    
    override func setUp() {
        super.setUp()
        config = MockWebRTCConfigurable()
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
        XCTAssertEqual(sut.peerConnection.connectionState, .new)
    }
    
    func testConnect() {
        // Create an expectation for the async operation
        let expectation = XCTestExpectation(description: "Connection offer generated")
        
        // Connect and wait for the offer to be generated
        sut.connect()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            XCTAssertNotNil(self.delegate.generatedOffer)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
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
    
    func testDisconnect() {
        sut.connect()
        sut.disconnect()
        XCTAssertEqual(sut.peerConnection.connectionState, .closed)
    }
    
    func testDelegateConnectionStateCallback() {
        let expectation = XCTestExpectation(description: "Connection state changed")
        
        // Force connection state change by connecting
        sut.connect()
        
        // Simulate connection state change
        sut.simulateConnectionStateChange(to: .connected)
        
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
