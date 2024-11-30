import WebRTC

/// Extension for RTCMediaConstraints to handle audio configuration
public extension RTCMediaConstraints {
    
    /// Standard audio constraint keys
    private enum AudioConstraintKey {
        static let echoCancellation = "echoCancellation"
        static let noiseSuppression = "noiseSuppression"
        static let autoGainControl = "autoGainControl"
        static let highPassFilter = "highPassFilter"
        static let typingNoiseDetection = "typingNoiseDetection"
        static let audioLevel = "audioLevel"
    }
    
    /// Creates constraints for voice chat optimization
    /// - Returns: RTCMediaConstraints configured for voice
    static func voiceChatConstraints() -> RTCMediaConstraints {
        let mandatoryConstraints = [
            AudioConstraintKey.echoCancellation: "true",
            AudioConstraintKey.noiseSuppression: "true",
            AudioConstraintKey.autoGainControl: "true"
        ]
        
        let optionalConstraints = [
            AudioConstraintKey.typingNoiseDetection: "true",
            AudioConstraintKey.highPassFilter: "true"
        ]
        
        return RTCMediaConstraints(
            mandatoryConstraints: mandatoryConstraints,
            optionalConstraints: optionalConstraints
        )
    }
    
    /// Creates constraints for music streaming
    /// - Returns: RTCMediaConstraints configured for music
    static func musicStreamingConstraints() -> RTCMediaConstraints {
        let mandatoryConstraints = [
            AudioConstraintKey.echoCancellation: "false",
            AudioConstraintKey.noiseSuppression: "false",
            AudioConstraintKey.autoGainControl: "false"
        ]
        
        return RTCMediaConstraints(
            mandatoryConstraints: mandatoryConstraints,
            optionalConstraints: nil
        )
    }
    
    /// Creates custom audio constraints
    /// - Parameters:
    ///   - echoCancellation: Enable echo cancellation
    ///   - noiseSuppression: Enable noise suppression
    ///   - autoGainControl: Enable automatic gain control
    ///   - additional: Additional optional constraints
    /// - Returns: RTCMediaConstraints with custom settings
    static func customAudioConstraints(
        echoCancellation: Bool = true,
        noiseSuppression: Bool = true,
        autoGainControl: Bool = true,
        additional: [String: String] = [:]
    ) -> RTCMediaConstraints {
        let mandatoryConstraints = [
            AudioConstraintKey.echoCancellation: echoCancellation.description,
            AudioConstraintKey.noiseSuppression: noiseSuppression.description,
            AudioConstraintKey.autoGainControl: autoGainControl.description
        ]
        
        return RTCMediaConstraints(
            mandatoryConstraints: mandatoryConstraints,
            optionalConstraints: additional
        )
    }
    
    /// Access to mandatory constraints
    var mandatoryConstraints: [String: String] {
        return self.value(forKey: "mandatory") as? [String: String] ?? [:]
    }
    
    /// Access to optional constraints
    var optionalConstraints: [String: String]? {
        return self.value(forKey: "optional") as? [String: String]
    }
}

// MARK: - Codec Configuration
public extension RTCMediaConstraints {
    /// Creates OPUS codec configuration
    /// - Parameters:
    ///   - bitrate: Target bitrate in bits per second
    ///   - stereo: Enable stereo audio
    /// - Returns: RTCMediaConstraints for OPUS codec
    static func opusConfiguration(
        bitrate: Int = 32_000,
        stereo: Bool = false
    ) -> RTCMediaConstraints {
        let mandatoryConstraints = [
            "opusBitrate": String(bitrate),
            "opusStereo": stereo.description,
            "opusFec": "true",
            "opusDtx": "true"
        ]
        
        return RTCMediaConstraints(
            mandatoryConstraints: mandatoryConstraints,
            optionalConstraints: nil
        )
    }
}

// MARK: - Helper Methods
public extension RTCMediaConstraints {
    /// Merges current constraints with new ones
    /// - Parameter other: Additional constraints to merge
    /// - Returns: New RTCMediaConstraints instance
    func merging(with other: RTCMediaConstraints) -> RTCMediaConstraints {
        var mandatory = self.mandatoryConstraints
        for (key, value) in other.mandatoryConstraints {
            mandatory[key] = value
        }
        
        var optional = self.optionalConstraints ?? [:]
        if let otherOptional = other.optionalConstraints {
            for (key, value) in otherOptional {
                optional[key] = value
            }
        }
        
        return RTCMediaConstraints(
            mandatoryConstraints: mandatory,
            optionalConstraints: optional
        )
    }
}
