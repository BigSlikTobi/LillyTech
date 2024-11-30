import Foundation

/// Thread-safe audio buffer wrapper for handling raw PCM audio data
/// Used for WebRTC audio processing operations
public final class RTCAudioBuffer {
    
    /// Underlying raw buffer pointer
    private let buffer: UnsafeMutablePointer<Float>
    
    /// Size of allocated buffer in Float units
    private let capacity: Int
    
    /// Queue for synchronizing buffer access
    private let syncQueue = DispatchQueue(label: "com.lillytech.rtcaudiobuffer")
    
    /// Creates a new audio buffer with specified capacity
    /// - Parameter capacity: Size of buffer in Float units
    /// - Throws: RuntimeError if memory allocation fails
    public init(capacity: Int) throws {
        guard capacity > 0 else {
            throw RuntimeError.invalidCapacity
        }
        
        // Allocate memory
        let pointer = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        self.buffer = pointer
        self.capacity = capacity
        
        // Initialize memory to zero
        buffer.initialize(repeating: 0.0, count: capacity)
    }
    
    /// Safely copies data into the buffer
    /// - Parameter source: Source buffer to copy from
    /// - Parameter count: Number of elements to copy
    /// - Throws: RuntimeError if count exceeds capacity
    public func copyBytes(from source: UnsafePointer<Float>, count: Int) throws {
        guard count <= capacity else {
            throw RuntimeError.bufferOverflow
        }
        
        syncQueue.sync {
            buffer.update(from: source, count: count)
        }
    }
    
    /// Provides safe read access to buffer contents
    /// - Parameter body: Closure that receives read-only buffer pointer
    /// - Returns: Result of closure execution
    /// - Throws: Rethrows any errors from closure
    public func withUnsafeBytes<T>(_ body: (UnsafePointer<Float>) throws -> T) rethrows -> T {
        return try syncQueue.sync {
            try body(UnsafePointer(buffer))
        }
    }
    
    deinit {
        // Clean up allocated memory
        buffer.deinitialize(count: capacity)
        buffer.deallocate()
    }
}

// MARK: - Error Handling
extension RTCAudioBuffer {
    public enum RuntimeError: Error {
        case invalidCapacity
        case memoryAllocationFailed
        case bufferOverflow
        
        var localizedDescription: String {
            switch self {
            case .invalidCapacity:
                return "Buffer capacity must be greater than 0"
            case .memoryAllocationFailed:
                return "Failed to allocate memory for audio buffer"
            case .bufferOverflow:
                return "Attempted to copy more data than buffer capacity"
            }
        }
    }
}
