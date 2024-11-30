import WebRTC
import AVFoundation
import os.log

public final class WebRTCAudioManager: WebRTCAudioManaging {
    
    private let logger = Logger(subsystem: "WebRTCAudioManager", category: "audio")
    private let factory: RTCPeerConnectionFactory
    private var audioTrack: RTCAudioTrack?
    private var audioSource: RTCAudioSource?
    private var stateObservers: [UUID: (WebRTCAudioState) -> Void] = [:]
    private var permissionProvider: AudioPermissionProviding = DefaultPermissionProvider()
    
    public private(set) var state: WebRTCAudioState = .uninitialized {
        didSet {
            notifyStateObservers()
            logger.info("Audio state changed to: \(String(describing: self.state))")
        }
    }
    
    public private(set) var configuration: WebRTCAudioConfiguration
    
    public init(
        factory: RTCPeerConnectionFactory,
        configuration: WebRTCAudioConfiguration = .opusConfig()
    ) {
        self.factory = factory
        self.configuration = configuration
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat)
            try session.setActive(true)
            state = .initialized
        } catch {
            logger.error("Failed to setup audio session: \(error.localizedDescription)")
            state = .error(.initializationFailed)
        }
    }
    
    public func initializeAudioTrack(
        with config: WebRTCAudioConfiguration
    ) -> Result<RTCAudioTrack, WebRTCAudioError> {
        do {
            try config.validate()
            
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: nil,
                optionalConstraints: config.constraints.rtcConstraints
            )
            
            audioSource = factory.audioSource(with: constraints)
            
            guard let source = audioSource else {
                throw WebRTCAudioError.initializationFailed
            }
            
            audioTrack = factory.audioTrack(with: source, trackId: UUID().uuidString)
            configuration = config
            
            guard let track = audioTrack else {
                throw WebRTCAudioError.initializationFailed
            }
            
            logger.info("Audio track initialized successfully")
            return .success(track)
            
        } catch {
            logger.error("Failed to initialize audio track: \(error.localizedDescription)")
            state = .error(.initializationFailed)
            return .failure(.initializationFailed)
        }
    }
    
    public func startCapture() -> Result<Void, WebRTCAudioError> {
        guard state == .initialized || state == .stopped else {
            return .failure(.invalidState)
        }
        
        // Check microphone permission asynchronously
        Task {
            let granted = await permissionProvider.requestPermission()
            if granted {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    audioTrack?.isEnabled = true
                    updateState(.capturing)
                    logger.info("Audio capture started")
                } catch {
                    logger.error("Failed to start capture: \(error.localizedDescription)")
                    updateState(.error(.captureStartFailed))
                }
            } else {
                logger.error("Microphone permission denied")
                updateState(.error(.captureStartFailed))
            }
        }
        
        return .success(())
    }
    
    private func updateState(_ newState: WebRTCAudioState) {
        DispatchQueue.main.async {
            self.state = newState
        }
    }
    
    public func stopCapture() -> Result<Void, WebRTCAudioError> {
        guard state == .capturing else {
            return .failure(.invalidState)
        }
        
        audioTrack?.isEnabled = false
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            state = .stopped
            logger.info("Audio capture stopped")
            return .success(())
        } catch {
            logger.error("Failed to stop capture: \(error.localizedDescription)")
            return .failure(.captureStartFailed)
        }
    }
    
    public func setLocalAudio(enabled: Bool) -> Result<Void, WebRTCAudioError> {
        audioTrack?.isEnabled = enabled
        logger.info("Local audio \(enabled ? "enabled" : "disabled")")
        return .success(())
    }
    
    public func selectAudioDevice(deviceId: String) -> Result<Void, WebRTCAudioError> {
        // Implementation depends on platform-specific audio device handling
        logger.info("Audio device selection not implemented")
        return .failure(.deviceNotFound)
    }
    
    public func reset() -> Result<Void, WebRTCAudioError> {
        audioTrack?.isEnabled = false
        audioTrack = nil
        audioSource = nil
        state = .uninitialized
        setupAudioSession()
        logger.info("Audio manager reset")
        return .success(())
    }
    
    public func addStateObserver(_ observer: @escaping (WebRTCAudioState) -> Void) -> UUID {
        let id = UUID()
        stateObservers[id] = observer
        return id
    }
    
    public func removeStateObserver(id: UUID) {
        stateObservers.removeValue(forKey: id)
    }
    
    private func notifyStateObservers() {
        stateObservers.values.forEach { $0(state) }
    }
    
    public func processAudioBuffer(_ buffer: CustomRTCAudioBuffer) {
        guard state == .capturing else {
            logger.error("Cannot process audio buffer when not capturing")
            return
        }
        
        logger.debug("Processing audio buffer: samples=\(buffer.samples), channels=\(buffer.channels)")
    }
    
    deinit {
        try? AVAudioSession.sharedInstance().setActive(false)
        logger.info("Audio manager deallocated")
    }
}

// Add DefaultPermissionProvider implementation
class DefaultPermissionProvider: AudioPermissionProviding {
    func requestPermission() async -> Bool {
        // Assume permission is granted by default
        return true
    }
}

public extension WebRTCAudioManager {
    var currentAudioTrack: RTCAudioTrack? { audioTrack }
    var currentAudioSource: RTCAudioSource? { audioSource }
    
    func setPermissionProvider(_ provider: AudioPermissionProviding) {
        self.permissionProvider = provider
    }
}

public protocol AudioPermissionProviding {
    func requestPermission() async -> Bool
}