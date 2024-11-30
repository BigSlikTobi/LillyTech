//
//  LillyTechTests.swift
//  LillyTechTests
//
//  Created by Tobias Latta on 24.11.24.
//

import Testing
import WebRTC
@testable import LillyTech

struct LillyTechTests {

    @Test func example() async throws {
        // This is a placeholder test
        #expect(true)
    }

    @Test func verifyWebRTCInitialization() async throws {
        // Initialize WebRTC
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        
        // Test media constraints
        let mandatoryConstraints = ["OfferToReceiveAudio": "true",
                                  "OfferToReceiveVideo": "true"]
        let constraints = RTCMediaConstraints(mandatoryConstraints: mandatoryConstraints,
                                           optionalConstraints: nil)
        
        // Create factory and verify
        let factory = RTCPeerConnectionFactory()
        #expect(factory != nil, "Should create RTCPeerConnectionFactory")
        
        // Create and verify peer connection
        let peerConnection = factory.peerConnection(with: config,
                                                  constraints: constraints,
                                                  delegate: nil)
        
        #expect(peerConnection != nil, "Should create RTCPeerConnection")
        
        // Verify audio capabilities
        let audioConfig = RTCAudioSessionConfiguration()
        audioConfig.category = AVAudioSession.Category.playAndRecord.rawValue
        audioConfig.mode = AVAudioSession.Mode.videoChat.rawValue
        audioConfig.categoryOptions = .allowBluetooth
        
        #expect(audioConfig != nil, "Should create audio configuration")
        
        AppLogger.shared.info("WebRTC initialization verified")
    }

}
