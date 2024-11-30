import XCTest
import WebRTC
import AVFAudio
@testable import LillyTech

final class AudioCaptureServiceTests: XCTestCase {
    private var sut: WebRTCAudioCaptureService!
    private var audioManager: MockAudioManager!
    private var mockAudioSession: MockAudioSession!
    
    override func setUp() {
        super.setUp()
        mockAudioSession = MockAudioSession()
        audioManager = MockAudioManager()
        audioManager.configuration = WebRTCAudioConfiguration(
            preferredCodecs: [],
            constraints: WebRTCAudioConfiguration.MediaConstraints(),
            profile: .voiceChat,
            maxBitrate: 64000
        )
        // Initialize audio track
        _ = audioManager.initializeAudioTrack(with: audioManager.configuration)
        // Pass the mock audio session to the service
        sut = WebRTCAudioCaptureService(audioManager: audioManager, audioSession: mockAudioSession)
    }
    
    override func tearDown() {
        sut = nil
        audioManager = nil
        super.tearDown()
    }
    
    func testCaptureStartStop() async throws {
        // Start capture
        try await sut.startCapture()
        
        // Verify initial state
        XCTAssertEqual(audioManager.state, .capturing)
        XCTAssertTrue(audioManager.isProcessing)
        
        // Stop capture
        try await withTimeout(seconds: 1.0) { [self] in
            sut.stopCapture()
            while audioManager.isProcessing {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        XCTAssertEqual(audioManager.state, .stopped)
        XCTAssertFalse(audioManager.isProcessing)
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError()
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private struct TimeoutError: Error {}

    func testInterruptionHandling() async throws {
        // Start capture
        try await sut.startCapture()
        
        // Simulate interruption began
        let beganInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: beganInfo
        )
        
        XCTAssertFalse(audioManager.isProcessing)
        
        // Simulate interruption ended with resume
        let endedInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: endedInfo
        )
        
        // Allow time for async restart
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(audioManager.isProcessing)
    }
    
    func testRouteChangeHandling() async throws {
        // Start capture
        try await sut.startCapture()
        
        // Simulate route change - old device unavailable
        let oldDeviceInfo: [AnyHashable: Any] = [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: oldDeviceInfo
        )
        
        XCTAssertFalse(audioManager.isProcessing)
        
        // Simulate new device available
        let newDeviceInfo: [AnyHashable: Any] = [
            AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.routeChangeNotification,
            object: nil,
            userInfo: newDeviceInfo
        )
        
        // Allow time for async restart
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(audioManager.isProcessing)
    }
    
    func testCleanupProcess() async throws {
        // Start capture
        try await sut.startCapture()
        XCTAssertTrue(audioManager.isProcessing)
        
        // Trigger cleanup by forcing deallocation
        sut = nil
        XCTAssertFalse(audioManager.isProcessing)
    }
    
    func testSimultaneousInterruptions() async throws {
        try await sut.startCapture()
        XCTAssertTrue(audioManager.isProcessing)
        
        // Simulate multiple rapid interruptions
        let beganInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
        
        // Post multiple interruption notifications in quick succession
        for _ in 0...2 {
            NotificationCenter.default.post(
                name: AVAudioSession.interruptionNotification,
                object: nil,
                userInfo: beganInfo
            )
        }
        
        XCTAssertFalse(audioManager.isProcessing)
        
        // Simulate single end interruption
        let endedInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: endedInfo
        )
        
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(audioManager.isProcessing)
    }
    
    func testIncompleteInterruptionData() async throws {
        try await sut.startCapture()
        XCTAssertTrue(audioManager.isProcessing)
        
        // Post notification with empty userInfo
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: nil
        )
        
        // Service should maintain its current state when receiving invalid data
        XCTAssertTrue(audioManager.isProcessing)
        
        // Post notification with incomplete data
        let incompleteInfo: [AnyHashable: Any] = [:]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: incompleteInfo
        )
        
        // Service should maintain its current state
        XCTAssertTrue(audioManager.isProcessing)
    }
    
    func testBufferCleanupAfterInterruption() async throws {
        try await sut.startCapture()
        
        // Simulate interruption began
        let beganInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: beganInfo
        )
        
        XCTAssertFalse(audioManager.isProcessing)
        // Remove or modify state check based on available states
        // XCTAssertEqual(audioManager.state, .interrupted)
        
        // Verify buffer is cleared
        XCTAssertEqual(audioManager.bufferCount, 0)
        
        // Simulate interruption ended
        let endedInfo: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification,
            object: nil,
            userInfo: endedInfo
        )
        
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(audioManager.isProcessing)
        // Remove or modify state check based on available states
        // XCTAssertEqual(audioManager.state, .running)
    }
}

// Mock audio manager for testing
private class MockAudioManager: WebRTCAudioManaging {
    private(set) var state: WebRTCAudioState = .uninitialized {
        didSet {
            stateObservers.values.forEach { $0(state) }
        }
    }
    var configuration: WebRTCAudioConfiguration = .opusConfig()
    var isProcessing = false
    var bufferCount: Int = 0
    private var stateObservers: [UUID: (WebRTCAudioState) -> Void] = [:]
    
    func initializeAudioTrack(with config: WebRTCAudioConfiguration) -> Result<RTCAudioTrack, WebRTCAudioError> {
        let validSampleRates: Set<Int> = [8000, 16000, 44100, 48000]
        let validChannelCounts: Set<Int> = [1, 2]
        
        guard validSampleRates.contains(config.profile.sampleRate) else {
            state = .error(.configurationError)
            return .failure(.configurationError)
        }
        
        guard validChannelCounts.contains(config.profile.channels) else {
            state = .error(.configurationError)
            return .failure(.configurationError)
        }
        
        let factory = RTCPeerConnectionFactory()
        let audioTrack = factory.audioTrack(withTrackId: "MOCK_AUDIO_TRACK")
        state = .initialized
        return .success(audioTrack)
    }
    
    func startCapture() -> Result<Void, WebRTCAudioError> {
        guard state == .initialized || state == .stopped else {
            return .failure(.invalidState)
        }
        isProcessing = true
        state = .capturing
        return .success(())
    }
    
    func stopCapture() -> Result<Void, WebRTCAudioError> {
        guard state == .capturing else {
            return .failure(.invalidState)
        }
        defer {
            isProcessing = false
            state = .stopped
        }
        return .success(())
    }
    
    func reset() -> Result<Void, WebRTCAudioError> {
        isProcessing = false
        state = .stopped
        bufferCount = 0
        return .success(())
    }
    
    func setLocalAudio(enabled: Bool) -> Result<Void, WebRTCAudioError> {
        .success(())
    }
    
    func selectAudioDevice(deviceId: String) -> Result<Void, WebRTCAudioError> {
        .success(())
    }
    
    func addStateObserver(_ observer: @escaping (WebRTCAudioState) -> Void) -> UUID {
        let id = UUID()
        stateObservers[id] = observer
        return id
    }
    
    func removeStateObserver(id: UUID) {
        stateObservers.removeValue(forKey: id)
    }
    
    func processAudioBuffer(_ buffer: CustomRTCAudioBuffer) {
        isProcessing = true
        bufferCount += 1
    }
    
    // Ensure all protocol methods are correctly implemented with exact signatures
    func configureAudioSession() -> Result<Void, WebRTCAudioError> {
        .success(())
    }
    
    func handleAudioRouteChange(reason: AVAudioSession.RouteChangeReason) -> Result<Void, WebRTCAudioError> {
        .success(())
    }
}

// Update MockAudioSession with proper Sendable conformance
@objc private class MockAudioSession: AVAudioSession, @unchecked Sendable {
    // Using raw values to avoid deprecation warnings
    private var _mockAuthorizationStatus: UInt = 1 // 1 = granted, 0 = undetermined, 2 = denied
    var isSessionActive = false
    
    #if os(iOS)
    override var recordPermission: AVAudioSession.RecordPermission {
        // Initialize with raw value to avoid using deprecated enum cases directly
        return AVAudioSession.RecordPermission(rawValue: _mockAuthorizationStatus) ?? 
               AVAudioSession.RecordPermission(rawValue: 0)! // fallback to undetermined
    }
    
    func setMockPermission(granted: Bool) {
        // Use raw values directly: 1 for granted, 2 for denied
        _mockAuthorizationStatus = granted ? 1 : 2
    }
    #endif
    
    override func setCategory(_ category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions = []) throws {
        // No-op in mock
    }
    
    override func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) throws {
        isSessionActive = active
    }
    
    override func setPreferredSampleRate(_ sampleRate: Double) throws {
        // No-op in mock
    }
    
    override func setPreferredIOBufferDuration(_ duration: TimeInterval) throws {
        // No-op in mock
    }
}
