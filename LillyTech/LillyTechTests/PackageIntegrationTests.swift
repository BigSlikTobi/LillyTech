import XCTest
import WebRTC
import AVFAudio
@testable import LillyTech

final class PackageIntegrationTests: XCTestCase {
    
    /// Tests the availability of the WebRTC package by creating an instance of RTCPeerConnectionFactory.
    func testWebRTCPackageAvailability() {
        let rtcPeerConnectionFactory = RTCPeerConnectionFactory()
        XCTAssertNotNil(rtcPeerConnectionFactory, "RTCPeerConnectionFactory should be available")
    }
    
    /// Tests the WebRTC configuration by setting up ICE servers and verifying the configuration.
    func testWebRTCConfiguration() {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        
        XCTAssertEqual(config.iceServers.count, 1, "Should have one ICE server configured")
        XCTAssertEqual(config.iceServers.first?.urlStrings.first, "stun:stun.l.google.com:19302")
        
        AppLogger.info("WebRTC configuration test completed", category: AppLogger.network)
    }
    
    /// Tests the initialization and configuration of the audio device for WebRTC.
    func testAudioDeviceInitialization() {
        let audioSession = RTCAudioSession.sharedInstance()
        XCTAssertNotNil(audioSession, "Audio session should be available")
        
        do {
            try audioSession.configureWebRTCSession()
            AppLogger.debug("Audio session configured successfully", category: AppLogger.network)
        } catch {
            AppLogger.error("Audio session configuration failed: \(error.localizedDescription)", 
                          category: AppLogger.network)
            XCTFail("Audio session configuration failed: \(error)")
        }
    }
}

// MARK: - Helper Extensions
private extension RTCAudioSession {
    func configureWebRTCSession() throws {
        self.lockForConfiguration()
        defer { self.unlockForConfiguration() }
        
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
    }
}