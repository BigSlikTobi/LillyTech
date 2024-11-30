import WebRTC
import Foundation

/// Errors that can occur during audio operations
public enum WebRTCAudioError: Error {
    case initializationFailed
    case captureStartFailed
    case deviceNotFound
    case invalidState
    case configurationError
    
    var localizedDescription: String {
        switch self {
        case .initializationFailed: return "Failed to initialize audio subsystem"
        case .captureStartFailed: return "Failed to start audio capture"
        case .deviceNotFound: return "Audio capture device not found"
        case .invalidState: return "Invalid audio manager state"
        case .configurationError: return "Invalid audio configuration"
        }
    }
}

/// Represents the current state of the audio manager
public enum WebRTCAudioState: Equatable {
    case uninitialized
    case initialized
    case capturing
    case stopped
    case error(WebRTCAudioError)
    
    public static func == (lhs: WebRTCAudioState, rhs: WebRTCAudioState) -> Bool {
        switch (lhs, rhs) {
        case (.uninitialized, .uninitialized),
             (.initialized, .initialized),
             (.capturing, .capturing),
             (.stopped, .stopped):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// Represents audio buffer data - prefix with Custom to avoid ambiguity
public struct CustomRTCAudioBuffer {
    public let data: UnsafeMutablePointer<Float>
    public let samples: UInt32
    public let channels: Int32
    
    public init(data: UnsafeMutablePointer<Float>, samples: UInt32, channels: Int32) {
        self.data = data
        self.samples = samples
        self.channels = channels
    }
}

/// Protocol defining WebRTC audio management capabilities
public protocol WebRTCAudioManaging: AnyObject {
    /// Current state of the audio manager
    var state: WebRTCAudioState { get }
    
    /// Current audio configuration
    var configuration: WebRTCAudioConfiguration { get }
    
    /// Audio track initialization
    /// - Parameter config: Audio configuration to use
    /// - Returns: Result containing RTCAudioTrack on success
    func initializeAudioTrack(
        with config: WebRTCAudioConfiguration
    ) -> Result<RTCAudioTrack, WebRTCAudioError>
    
    /// Start audio capture
    /// - Returns: Result indicating success or failure
    func startCapture() -> Result<Void, WebRTCAudioError>
    
    /// Stop audio capture
    /// - Returns: Result indicating success or failure
    func stopCapture() -> Result<Void, WebRTCAudioError>
    
    /// Enable/disable local audio output
    /// - Parameter enabled: Whether local audio should be enabled
    /// - Returns: Result indicating success or failure
    func setLocalAudio(enabled: Bool) -> Result<Void, WebRTCAudioError>
    
    /// Set audio device
    /// - Parameter deviceId: ID of audio device to use
    /// - Returns: Result indicating success or failure
    func selectAudioDevice(
        deviceId: String
    ) -> Result<Void, WebRTCAudioError>
    
    /// Reset audio subsystem
    /// - Returns: Result indicating success or failure
    func reset() -> Result<Void, WebRTCAudioError>
    
    /// Add state change observer
    /// - Parameter observer: Closure to call on state changes
    /// - Returns: UUID used to identify the observer for removal
    func addStateObserver(
        _ observer: @escaping (WebRTCAudioState) -> Void
    ) -> UUID
    
    /// Remove state observer
    /// - Parameter id: UUID of the observer to remove
    func removeStateObserver(id: UUID)
    
    /// Process audio buffer data
    /// - Parameter buffer: Audio buffer to process
    func processAudioBuffer(_ buffer: CustomRTCAudioBuffer)
}