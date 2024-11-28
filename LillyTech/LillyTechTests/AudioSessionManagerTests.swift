import XCTest
import AVFAudio
@testable import LillyTech

final class AudioSessionManagerTests: XCTestCase {
    private var sut: AudioSessionManager!
    private var mockAudioSession: MockAudioSession!
    private var mockLogger: AppLogger!
    
    override func setUp() {
        super.setUp()
        mockAudioSession = MockAudioSession()
        mockLogger = AppLogger.shared
        sut = AudioSessionManager(audioSession: mockAudioSession)
    }
    
    override func tearDown() {
        sut = nil
        mockAudioSession = nil
        mockLogger = nil
        super.tearDown()
    }
    
    func testStartConfiguresAudioSessionSuccessfully() {
        // When
        let result = sut.start()
        
        // Then
        switch result {
        case .success:
            XCTAssertTrue(mockAudioSession.isActive)
            XCTAssertEqual(mockAudioSession.currentCategory, AVAudioSession.Category.playAndRecord)
            XCTAssertEqual(mockAudioSession.currentMode, AVAudioSession.Mode.voiceChat)
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testStopDeactivatesAudioSession() {
        // Given
        _ = sut.start()
        
        // When
        let result = sut.stop()
        
        // Then
        switch result {
        case .success:
            XCTAssertFalse(mockAudioSession.isActive)
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testConfigureForVoiceChatSetsCorrectOptions() {
        // When
        let result = sut.configureForVoiceChat()
        
        // Then
        switch result {
        case .success:
            XCTAssertTrue(mockAudioSession.categoryOptions.contains(AVAudioSession.CategoryOptions.allowBluetooth))
            XCTAssertTrue(mockAudioSession.categoryOptions.contains(AVAudioSession.CategoryOptions.defaultToSpeaker))
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }
    
    func testStartHandlesError() {
        // Given
        mockAudioSession.shouldFail = true
        
        // When
        let result = sut.start()
        
        // Then
        switch result {
        case .success:
            XCTFail("Expected failure but got success")
        case .failure(let error):
            XCTAssertNotNil(error)
        }
    }
    
    func testHandleInterruption() {
        // When
        sut.handleInterruption(notification: Notification(name: AVAudioSession.interruptionNotification))
        
        // Then
        // Add assertions based on expected behavior
        XCTAssertFalse(mockAudioSession.isActive)
    }
    
    func testHandleRouteChange() {
        // When
        sut.handleRouteChange(notification: Notification(name: AVAudioSession.routeChangeNotification))
        
        // Then
        // Add assertions based on expected behavior
        XCTAssertEqual(mockAudioSession.currentRoute.outputs.count, 0)
    }
}

// Mock implementation of AudioSessionProtocol for testing
private class MockAudioSession: AudioSessionProtocol {
    var isActive = false
    var currentCategory: AVAudioSession.Category = .ambient
    var currentMode: AVAudioSession.Mode = .default
    var categoryOptions: AVAudioSession.CategoryOptions = []
    var isOtherAudioPlaying = false
    var shouldFail = false
    
    var currentRoute: AVAudioSessionRouteDescription {
        // Return a dummy route description
        AVAudioSessionRouteDescription()
    }
    
    func setCategory(_ category: AVAudioSession.Category, 
                    mode: AVAudioSession.Mode, 
                    options: AVAudioSession.CategoryOptions) throws {
        if shouldFail {
            throw NSError(domain: "MockError", code: 1, userInfo: nil)
        }
        currentCategory = category
        currentMode = mode
        categoryOptions = options
    }
    
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        if shouldFail {
            throw NSError(domain: "MockError", code: 2, userInfo: nil)
        }
        isActive = active
    }
    
    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        response(true)
    }
}