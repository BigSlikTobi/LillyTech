import XCTest
import AVFoundation
@testable import LillyTech

final class RTCAudioBufferTests: XCTestCase {
    
    func testBufferInitialization() throws {
        // Test valid initialization
        let buffer = try RTCAudioBuffer(capacity: 1024)
        XCTAssertNotNil(buffer)
        
        // Test invalid capacity
        XCTAssertThrowsError(try RTCAudioBuffer(capacity: 0)) { error in
            XCTAssertEqual(error as? RTCAudioBuffer.RuntimeError, .invalidCapacity)
        }
    }
    
    func testBufferOverflow() throws {
        let buffer = try RTCAudioBuffer(capacity: 10)
        let sourceData = Array(repeating: Float(1.0), count: 20)
        
        // Test copying more data than capacity
        XCTAssertThrowsError(try buffer.copyBytes(from: sourceData, count: 20)) { error in
            XCTAssertEqual(error as? RTCAudioBuffer.RuntimeError, .bufferOverflow)
        }
        
        // Test valid copy
        XCTAssertNoThrow(try buffer.copyBytes(from: sourceData, count: 10))
    }
    
    func testThreadSafety() throws {
        let buffer = try RTCAudioBuffer(capacity: 1000)
        let expectation = XCTestExpectation(description: "Concurrent buffer access")
        expectation.expectedFulfillmentCount = 10
        
        // Perform concurrent reads and writes
        DispatchQueue.concurrentPerform(iterations: 10) { i in
            let sourceData = Array(repeating: Float(i), count: 100)
            do {
                try buffer.copyBytes(from: sourceData, count: 100)
                buffer.withUnsafeBytes { _ in
                    // Simulate read operation
                }
                expectation.fulfill()
            } catch {
                XCTFail("Thread safety test failed: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testMemoryDeallocation() throws {
        weak var weakBuffer: RTCAudioBuffer?
        
        autoreleasepool {
            let buffer = try? RTCAudioBuffer(capacity: 1024)
            weakBuffer = buffer
            XCTAssertNotNil(weakBuffer)
        }
        
        XCTAssertNil(weakBuffer, "Buffer should be deallocated")
    }
    
    func testConversionFromPCMBuffer() throws {
        // Create AVAudioPCMBuffer
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        pcmBuffer.frameLength = 1024
        
        // Fill with test data
        let channelData = pcmBuffer.floatChannelData![0]
        for i in 0..<1024 {
            channelData[i] = Float(sin(Double(i) * 0.1))
        }
        
        // Convert to RTCAudioBuffer
        let rtcBuffer = try RTCAudioBuffer.convert(from: pcmBuffer)
        XCTAssertNotNil(rtcBuffer)
        
        // Verify data
        rtcBuffer.withUnsafeBytes { ptr in
            for i in 0..<1024 {
                XCTAssertEqual(ptr[i], channelData[i], accuracy: 0.0001)
            }
        }
    }
}