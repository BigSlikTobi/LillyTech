import XCTest
import WebRTC
@testable import LillyTech

final class WebRTCAudioConfigurationTests: XCTestCase {
    
    func testValidConfiguration() throws {
        // Test standard configuration
        let standardConfig = WebRTCAudioConfiguration(
            preferredCodecs: [RTCCodecInfo(name: "opus", payloadType: 111)],
            constraints: WebRTCAudioConfiguration.MediaConstraints(),
            profile: .standard,
            maxBitrate: 32_000
        )
        
        XCTAssertNoThrow(try standardConfig.validate())
        
        // Test custom configuration within valid ranges
        let customConfig = WebRTCAudioConfiguration(
            constraints: WebRTCAudioConfiguration.MediaConstraints(
                echoCancellation: true,
                noiseSupression: true,
                autoGainControl: true
            ),
            profile: .custom(sampleRate: 48000, channels: 2),
            maxBitrate: 128_000
        )
        
        XCTAssertNoThrow(try customConfig.validate())
    }
    
    func testInvalidSampleRate() {
        let invalidLowConfig = WebRTCAudioConfiguration(
            profile: .custom(sampleRate: 4000, channels: 1),
            maxBitrate: 32_000
        )
        
        XCTAssertThrowsError(try invalidLowConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidSampleRate)
        }
        
        let invalidHighConfig = WebRTCAudioConfiguration(
            profile: .custom(sampleRate: 200_000, channels: 1),
            maxBitrate: 32_000
        )
        
        XCTAssertThrowsError(try invalidHighConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidSampleRate)
        }
    }
    
    func testInvalidChannelCount() {
        let invalidChannelConfig = WebRTCAudioConfiguration(
            profile: .custom(sampleRate: 48000, channels: 3),
            maxBitrate: 32_000
        )
        
        XCTAssertThrowsError(try invalidChannelConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidChannelCount)
        }
        
        let zeroChannelConfig = WebRTCAudioConfiguration(
            profile: .custom(sampleRate: 48000, channels: 0),
            maxBitrate: 32_000
        )
        
        XCTAssertThrowsError(try zeroChannelConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidChannelCount)
        }
    }
    
    func testCodecConfiguration() {
        // Test OPUS codec configuration
        let opusConfig = WebRTCAudioConfiguration.opusConfig()
        
        XCTAssertEqual(opusConfig.preferredCodecs.count, 1)
        XCTAssertEqual(opusConfig.preferredCodecs.first?.name, "opus")
        XCTAssertEqual(opusConfig.preferredCodecs.first?.payloadType, 111)
        XCTAssertEqual(opusConfig.profile, .voiceChat)
        XCTAssertEqual(opusConfig.maxBitrate, 32_000)
        XCTAssertNoThrow(try opusConfig.validate())
    }
    
    func testMaxBitrateValidation() {
        let invalidLowBitrateConfig = WebRTCAudioConfiguration(
            profile: .standard,
            maxBitrate: 7_999  // Just below minimum of 8_000
        )
        
        XCTAssertThrowsError(try invalidLowBitrateConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidBitrate)
        }
        
        let invalidHighBitrateConfig = WebRTCAudioConfiguration(
            profile: .standard,
            maxBitrate: 500_001  // Just above maximum of 500_000
        )
        
        XCTAssertThrowsError(try invalidHighBitrateConfig.validate()) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidBitrate)
        }
    }
    
    func testMediaConstraintsInitialization() {
        let constraints = WebRTCAudioConfiguration.MediaConstraints(
            echoCancellation: true,
            noiseSupression: false,
            autoGainControl: true
        )
        
        XCTAssertTrue(constraints.echoCancellation)
        XCTAssertFalse(constraints.noiseSupression)
        XCTAssertTrue(constraints.autoGainControl)
        
        // Test default initialization
        let defaultConstraints = WebRTCAudioConfiguration.MediaConstraints()
        XCTAssertTrue(defaultConstraints.echoCancellation)
        XCTAssertTrue(defaultConstraints.noiseSupression)
        XCTAssertTrue(defaultConstraints.autoGainControl)
    }
    
    func testCustomProfileCreation() {
        let customProfile = WebRTCAudioConfiguration.AudioProfile.custom(sampleRate: 48000, channels: 2)
        
        let config = WebRTCAudioConfiguration(
            constraints: WebRTCAudioConfiguration.MediaConstraints(),
            profile: customProfile,
            maxBitrate: 64_000
        )
        
        XCTAssertNoThrow(try config.validate())
        
        if case let .custom(sampleRate, channels) = config.profile {
            XCTAssertEqual(sampleRate, 48000)
            XCTAssertEqual(channels, 2)
        } else {
            XCTFail("Expected custom profile")
        }
    }
}