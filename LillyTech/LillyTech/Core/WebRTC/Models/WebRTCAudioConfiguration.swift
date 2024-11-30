import WebRTC
import Foundation

/// Represents audio codec information
public struct RTCCodecInfo {
    public let name: String
    public let payloadType: Int32
    
    public init(name: String, payloadType: Int32) {
        self.name = name
        self.payloadType = payloadType
    }
}

/// Configuration model for WebRTC audio settings
public struct WebRTCAudioConfiguration {
    
    /// Audio processing constraints
    public struct MediaConstraints {
        let echoCancellation: Bool
        let noiseSupression: Bool
        let autoGainControl: Bool
        
        public init(
            echoCancellation: Bool = true,
            noiseSupression: Bool = true, 
            autoGainControl: Bool = true
        ) {
            self.echoCancellation = echoCancellation
            self.noiseSupression = noiseSupression
            self.autoGainControl = autoGainControl
        }
        
        var rtcConstraints: [String: String] {
            [
                "echoCancellation": echoCancellation.description,
                "noiseSuppression": noiseSupression.description,
                "autoGainControl": autoGainControl.description
            ]
        }
    }
    
    /// Audio sample rate and channel configuration
    public enum AudioProfile: Equatable {
        case standard     // 48kHz stereo
        case highQuality  // 96kHz stereo
        case voiceChat   // 16kHz mono
        case custom(sampleRate: Int, channels: Int)
        
        public static func == (lhs: AudioProfile, rhs: AudioProfile) -> Bool {
            switch (lhs, rhs) {
            case (.standard, .standard),
                 (.highQuality, .highQuality),
                 (.voiceChat, .voiceChat):
                return true
            case let (.custom(lhsRate, lhsChannels), .custom(rhsRate, rhsChannels)):
                return lhsRate == rhsRate && lhsChannels == rhsChannels
            default:
                return false
            }
        }
        
        var sampleRate: Int {
            switch self {
            case .standard: return 48_000
            case .highQuality: return 96_000
            case .voiceChat: return 16_000
            case .custom(let rate, _): return rate
            }
        }
        
        var channels: Int {
            switch self {
            case .standard, .highQuality: return 2
            case .voiceChat: return 1
            case .custom(_, let channels): return channels
            }
        }
    }
    
    /// Preferred audio codecs in priority order
    public let preferredCodecs: [RTCCodecInfo]
    
    /// Audio processing constraints
    public let constraints: MediaConstraints
    
    /// Sample rate and channel configuration 
    public let profile: AudioProfile
    
    /// Maximum allowed bitrate in bits per second
    public let maxBitrate: Int
    
    public init(
        preferredCodecs: [RTCCodecInfo] = [],
        constraints: MediaConstraints = MediaConstraints(),
        profile: AudioProfile = .standard,
        maxBitrate: Int = 32_000
    ) {
        self.preferredCodecs = preferredCodecs
        self.constraints = constraints
        self.profile = profile
        self.maxBitrate = maxBitrate
    }
    
    /// Validates the configuration settings
    /// - Returns: Result indicating if configuration is valid
    /// - Throws: ConfigurationError with description of invalid settings
    public func validate() throws {
        // Check sample rate range
        guard (8_000...192_000).contains(profile.sampleRate) else {
            throw ConfigurationError.invalidSampleRate
        }
        
        // Check channel count
        guard (1...2).contains(profile.channels) else {
            throw ConfigurationError.invalidChannelCount
        }
        
        // Check bitrate range (8_000 to 500_000 bits per second)
        guard (8_000...500_000).contains(maxBitrate) else {
            throw ConfigurationError.invalidBitrate
        }
    }
}

/// Errors that can occur during configuration validation
public enum ConfigurationError: Error, Equatable {
    case invalidSampleRate
    case invalidChannelCount
    case invalidBitrate
    
    var localizedDescription: String {
        switch self {
        case .invalidSampleRate:
            return "Sample rate must be between 8kHz and 192kHz"
        case .invalidChannelCount:
            return "Channel count must be 1 (mono) or 2 (stereo)"
        case .invalidBitrate:
            return "Bitrate must be between 8kbps and 510kbps"
        }
    }
}

// Helper extension for codec configuration
extension WebRTCAudioConfiguration {
    /// Creates default OPUS codec configuration
    public static func opusConfig() -> WebRTCAudioConfiguration {
        let opus = RTCCodecInfo(name: "opus", payloadType: 111)
        return WebRTCAudioConfiguration(
            preferredCodecs: [opus],
            constraints: MediaConstraints(),
            profile: .voiceChat,
            maxBitrate: 32_000
        )
    }
}