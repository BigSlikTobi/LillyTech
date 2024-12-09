import XCTest
import WebRTC
import OSLog
@testable import LillyTech

// Create a test-specific logger that captures messages
fileprivate class WebRTCTestLogger: LoggerProtocol {
    private(set) var messages: [String] = []
    
    func debug(_ message: String, category: Logger) {
        messages.append(message)
    }
    
    func info(_ message: String, category: Logger) {
        messages.append(message)
    }
    
    func warning(_ message: String, category: Logger) {
        messages.append(message)
    }
    
    func error(_ message: String, category: Logger) {
        messages.append(message)
    }
    
    func clear() {
        messages.removeAll()
    }
}

final class WebRTCConfigurationTests: XCTestCase {
    
    var sut: WebRTCConfiguration!
    
    override func setUp() {
        super.setUp()
        sut = WebRTCConfiguration()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func testSTUNServersValidation() {
        let config = sut.configuration
        
        // Verify we have exactly 5 STUN servers
        XCTAssertEqual(config.iceServers.count, 5)
        
        // Verify server URLs are correctly formatted
        let expectedBaseURL = "stun:stun"
        let expectedSuffix = ".l.google.com:19302"
        
        config.iceServers.enumerated().forEach { index, server in
            let serverURL = server.urlStrings.first!
            if index == 0 {
                XCTAssertEqual(serverURL, "\(expectedBaseURL)\(expectedSuffix)")
            } else {
                XCTAssertEqual(serverURL, "\(expectedBaseURL)\(index)\(expectedSuffix)")
            }
        }
    }
    
    func testConfigurationLoading() {
        let config = sut.configuration
        
        // Verify connection policies
        XCTAssertEqual(config.bundlePolicy, .maxBundle)
        XCTAssertEqual(config.rtcpMuxPolicy, .require)
        XCTAssertEqual(config.tcpCandidatePolicy, .disabled)
        XCTAssertEqual(config.continualGatheringPolicy, .gatherOnce)
        XCTAssertEqual(config.keyType, .ECDSA)
    }
    
    func testConnectionInitialization() {
        let constraints = sut.defaultConstraints
        
        // Test mandatory constraints (non-optional dictionary)
        XCTAssertEqual(constraints.mandatoryConstraints["OfferToReceiveAudio"], "true")
        XCTAssertEqual(constraints.mandatoryConstraints["OfferToReceiveVideo"], "false")
        
        // Test optional constraints
        XCTAssertNotNil(constraints.optionalConstraints)
        if let optional = constraints.optionalConstraints {
            XCTAssertEqual(optional["DtlsSrtpKeyAgreement"], "true")
            XCTAssertEqual(optional["RtpDataChannels"], "true")
        }
    }
}

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

final class WebRTCServerMonitoringTests: XCTestCase {
    fileprivate var sut: WebRTCConfiguration!
    fileprivate var mockServers: [ICEServer]!
    fileprivate var testLogger: WebRTCTestLogger!
    
    override func setUp() {
        super.setUp()
        testLogger = WebRTCTestLogger()
        let originalLogger = AppLogger.shared.webrtc  // Fixed typo from 'AppLog;ger' to 'AppLogger'
        AppLogger.shared.webrtc = testLogger
        addTeardownBlock { AppLogger.shared.webrtc = originalLogger }
        
        mockServers = [
            ICEServer(urls: ["stun:mock1.test.com"], region: .northAmerica, priority: 100, timeout: 0.1, healthCheckInterval: 0.1),
            ICEServer(urls: ["stun:mock2.test.com"], region: .europe, priority: 90, timeout: 0.1, healthCheckInterval: 0.1)
        ]
        
        sut = WebRTCConfiguration()
    }
    
    override func tearDown() {
        mockServers = nil
        sut = nil
        super.tearDown()
    }
    
    func testMetricsInitialization() {
        let server = mockServers[0]
        
        XCTAssertEqual(server.metrics.atomicResponseTime.get(), 0)
        XCTAssertEqual(server.metrics.atomicSuccessRate.get(), 100)
        XCTAssertTrue(server.metrics.atomicIsHealthy.get())
    }
    
    func testHealthStatusTransitions() async {
        let server = mockServers[0]
        let monitor = WebRTCConfiguration.ServerMonitor()
        
        // Simulate failed health checks
        for _ in 1...5 {
            monitor.updateMetricsForTesting(server, responseTime: 0, success: false)
        }
        
        // Should be unhealthy after multiple failures
        XCTAssertFalse(server.metrics.atomicIsHealthy.get())
        XCTAssertLessThan(server.metrics.atomicSuccessRate.get(), 80)
        
        // Verify logger captured health transition
        XCTAssertTrue(testLogger.messages.contains { $0.contains("health changed to unhealthy") })
    }
    
    func testConcurrentMetricUpdates() async {
        let server = mockServers[0]
        let monitor = WebRTCConfiguration.ServerMonitor()
        let expectation = XCTestExpectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 100
        
        // Simulate multiple concurrent updates
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            monitor.updateMetricsForTesting(server, responseTime: Double.random(in: 0...0.1), success: true)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify metrics are still valid
        XCTAssertTrue(server.metrics.atomicSuccessRate.get() >= 0)
        XCTAssertTrue(server.metrics.atomicSuccessRate.get() <= 100)
    }
    
    func testMonitoringLifecycle() async throws {
        let expectation = XCTestExpectation(description: "Monitoring cycle completed")
        
        sut.startMonitoring()
        XCTAssertTrue(testLogger.messages.contains { $0.contains("monitoring started") })
        
        // Wait a bit to ensure monitoring is running
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Stop monitoring
        sut.stopMonitoring()
        
        // Wait for monitoring to stop
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        XCTAssertTrue(testLogger.messages.contains { $0.contains("monitoring stopped") })
        expectation.fulfill()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    // Add helper method to verify monitoring status
    private func verifyMonitoringStatus(_ isRunning: Bool, timeout: TimeInterval = 1.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if testLogger.messages.contains(where: { 
                $0.contains(isRunning ? "monitoring started" : "monitoring stopped")
            }) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Failed to verify monitoring status (expected: \(isRunning ? "running" : "stopped"))")
    }
}

// Helper extension for testing
extension WebRTCConfiguration.ServerMonitor {
    func updateMetricsForTesting(_ server: ICEServer, responseTime: TimeInterval, success: Bool) {
        updateMetrics(server, responseTime: responseTime, success: success)
    }
}
