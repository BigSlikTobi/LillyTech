import XCTest
import WebRTC
@testable import LillyTech

final class TestPeerConnection: PeerConnectionType {
    var connectionState: RTCPeerConnectionState = .new
    var localDescription: RTCSessionDescription?
    var remoteDescription: RTCSessionDescription?
    var addedCandidates: [TestIceCandidate] = []
    
    func add(_ candidate: Any, completionHandler: @escaping (Error?) -> Void) {
        if let iceCandidate = candidate as? TestIceCandidate {
            addedCandidates.append(iceCandidate)
            completionHandler(nil)
        }
    }
    
    func close() {
        // No-op for test implementation
    }
}

final class TestIceCandidate {
    let sdp: String
    let sdpMLineIndex: Int32
    let sdpMid: String?
    
    init(sdp: String = "test:sdp", sdpMLineIndex: Int32 = 0, sdpMid: String? = "data") {
        self.sdp = sdp
        self.sdpMLineIndex = sdpMLineIndex
        self.sdpMid = sdpMid
    }
}

final class ICECandidateHandlerTests: XCTestCase {
    var sut: ICECandidateHandler<TestPeerConnection, TestIceCandidate>!
    var peerConnection: TestPeerConnection!
    
    override func setUp() {
        super.setUp()
        peerConnection = TestPeerConnection()
        sut = ICECandidateHandler(peerConnection: peerConnection)
    }
    
    override func tearDown() {
        sut = nil
        peerConnection = nil
        super.tearDown()
    }
    
    func testCandidateGathering() {
        // Given
        let expectation = XCTestExpectation(description: "Candidate generated")
        let mockCandidate = TestIceCandidate()
        
        sut.onCandidateGenerated = { candidate in
            XCTAssertEqual(candidate.sdp, mockCandidate.sdp)
            expectation.fulfill()
        }
        
        // When
        sut.handleGeneratedCandidate(mockCandidate)
        
        // Then
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testCandidateProcessing() {
        // Given
        let mockCandidate = TestIceCandidate()
        
        // When - not ready
        sut.addCandidate(mockCandidate)
        
        // Then
        XCTAssertEqual(sut.queuedCandidates.count, 1)
        XCTAssertTrue(peerConnection.addedCandidates.isEmpty)
        
        // When - ready
        sut.setReady(true)
        
        // Then
        XCTAssertEqual(peerConnection.addedCandidates.count, 1)
        XCTAssertTrue(sut.queuedCandidates.isEmpty)
    }
    
    func testConnectionEstablishment() {
        // Given
        let mockCandidate = TestIceCandidate()
        sut.setReady(true)
        
        // When
        sut.addCandidate(mockCandidate)
        
        // Then
        XCTAssertEqual(peerConnection.addedCandidates.count, 1)
        XCTAssertEqual(peerConnection.addedCandidates.first?.sdp, mockCandidate.sdp)
    }
    
    func testReset() {
        // Given
        let mockCandidate = TestIceCandidate()
        sut.addCandidate(mockCandidate)
        
        // When
        sut.reset()
        
        // Then
        XCTAssertTrue(sut.queuedCandidates.isEmpty)
        XCTAssertFalse(sut.isReady)
    }
}
