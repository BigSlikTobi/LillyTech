import AVFoundation
import WebRTC
import Combine
import os.log

/// WebRTCAudioCaptureService cleanup requirements:
/// Order of operations:
/// 1. Stop active capture if running
/// 2. Remove audio tap from input node
/// 3. Stop and reset AVAudioEngine
/// 4. Deactivate audio session
/// 5. Remove notification observers
///
/// Threading considerations:
/// - Must handle background task completion
/// - Audio session deactivation must be synchronized
public final class WebRTCAudioCaptureService {
    
    private enum Constants {
        static let sampleRate: Double = 48000.0
        static let channelCount: Int = 1
        static let bufferSize: UInt32 = 960 // 20ms at 48kHz
    }
    
    // Audio format validation constants
    private struct AudioFormatConstants {
        static let validSampleRates: Set<Double> = [8000, 16000, 44100, 48000]
        static let validChannelCounts: Set<Int> = [1, 2]
    }
    
    private let logger = Logger(subsystem: "WebRTCAudioCaptureService", category: "capture")
    private let audioManager: WebRTCAudioManaging
    private let audioEngine: AVAudioEngine
    private let audioSession: AVAudioSession
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    
    private var cancellables = Set<AnyCancellable>()
    private let isCapturingLock = NSLock()
    private var _isCapturing = false
    private var isCapturing: Bool {
        get {
            isCapturingLock.lock()
            defer { isCapturingLock.unlock() }
            return _isCapturing
        }
        set {
            isCapturingLock.lock()
            _isCapturing = newValue 
            isCapturingLock.unlock()
        }
    }
    
    public init(audioManager: WebRTCAudioManaging, audioSession: AVAudioSession = .sharedInstance()) {
        self.audioManager = audioManager
        self.audioSession = audioSession
        self.audioEngine = AVAudioEngine()
        setupNotifications()
        
        // Ensure proper setup
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: .defaultToSpeaker)
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to initialize audio session: \(error.localizedDescription)")
        }
    }
    
    deinit {
        logger.info("Starting WebRTCAudioCaptureService cleanup")
        do {
            try cleanup()
        } catch {
            logger.error("Cleanup failed: \(error.localizedDescription)")
        }
        try? audioSession.setActive(false)
    }
    
    public func startCapture() async throws {
        guard !isCapturing else { return }
        
        try await checkMicrophonePermission()
        try configureAudioSession()
        try setupAudioProcessingPipeline()
        
        do {
            try audioEngine.start()
            isCapturing = true
            logger.info("Audio capture started")
            _ = audioManager.startCapture()
        } catch {
            logger.error("Failed to start audio capture: \(error.localizedDescription)")
            throw CaptureError.engineStartFailed
        }
    }
    
    public func stopCapture() {
        isCapturingLock.lock()
        defer { isCapturingLock.unlock() }
        
        if _isCapturing {
            inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            _isCapturing = false
            _ = audioManager.stopCapture()
        }
        
        logger.info("Audio capture stopped")
    }
    
    private func checkMicrophonePermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw CaptureError.permissionDenied }
        default:
            throw CaptureError.permissionDenied
        }
    }
    
    private func configureAudioSession() throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.defaultToSpeaker, .allowBluetooth]
        )
        try audioSession.setPreferredSampleRate(Constants.sampleRate)
        try audioSession.setPreferredIOBufferDuration(0.02) // 20ms
        try audioSession.setActive(true)
    }
    
    private func isAudioFormatValid(_ format: AVAudioFormat) -> Bool {
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        
        return AudioFormatConstants.validSampleRates.contains(sampleRate) &&
               AudioFormatConstants.validChannelCounts.contains(channelCount)
    }
    
    private func setupAudioProcessingPipeline() throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Constants.sampleRate,
            channels: UInt32(Constants.channelCount)
        )
        guard let format = format else {
            throw CaptureError.invalidFormat("Failed to create audio format")
        }
        
        inputNode.installTap(
            onBus: 0,
            bufferSize: Constants.bufferSize,
            format: format
        ) { [weak self] buffer, time in
            self?.processAudioBuffer(buffer, time: time)
        }
        
        try audioEngine.start()
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channelData = buffer.floatChannelData else { return }
        
        // Convert to WebRTC audio buffer format
        do {
            let rtcBuffer = try RTCAudioBuffer(capacity: Int(buffer.frameLength))
            try rtcBuffer.copyBytes(from: channelData[0], count: Int(buffer.frameLength))
            
            // Create CustomRTCAudioBuffer for WebRTCAudioManaging interface
            let customBuffer = CustomRTCAudioBuffer(
                data: channelData[0],
                samples: UInt32(buffer.frameLength),
                channels: Int32(buffer.format.channelCount)
            )
            
            // Process through WebRTC audio pipeline
            audioManager.processAudioBuffer(customBuffer)
        } catch {
            logger.error("Failed to process audio buffer: \(error.localizedDescription)")
        }
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                self?.handleAudioInterruption(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                self?.handleRouteChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            stopCapture()
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume) else {
                return
            }
            Task {
                try? await startCapture()
            }
        @unknown default:
            break
        }
    }
    
    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            stopCapture()
        case .newDeviceAvailable:
            Task {
                try? await startCapture()
            }
        default:
            break
        }
    }
    
    private func cleanup() throws {
        // Call stopCapture to ensure audioManager is notified
        stopCapture()
        
        audioEngine.reset()
        
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
            throw CleanupError.audioSessionDeactivationFailed
        }

        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
}

// MARK: - Error Types
extension WebRTCAudioCaptureService {
    enum CaptureError: Error {
        case permissionDenied
        case engineStartFailed
        case invalidConfiguration
        case invalidFormat(String)
        
        var localizedDescription: String {
            switch self {
            case .permissionDenied:
                return "Microphone access denied"
            case .engineStartFailed:
                return "Failed to start audio engine"
            case .invalidConfiguration:
                return "Invalid audio configuration"
            case .invalidFormat(let message):
                return message
            }
        }
    }
    
    enum CleanupError: Error {
        case audioSessionDeactivationFailed
        
        var localizedDescription: String {
            switch self {
            case .audioSessionDeactivationFailed:
                return "Failed to deactivate audio session during cleanup"
            }
        }
    }
    
    enum AudioCaptureError: Error {
        case invalidFormat(String)
        case engineStartFailed
    }
}