import WebRTC
import AVFoundation

// Add conversion error enum
public enum AudioBufferConversionError: Error {
    case invalidFormat
    case invalidChannelCount
    case bufferSizeMismatch
    case incompatibleSampleRate
    case memoryAllocationFailed
    
    var localizedDescription: String {
        switch self {
        case .invalidFormat:
            return "Invalid audio buffer format"
        case .invalidChannelCount:
            return "Unsupported channel count"
        case .bufferSizeMismatch:
            return "Buffer size mismatch"
        case .incompatibleSampleRate:
            return "Incompatible sample rate"
        case .memoryAllocationFailed:
            return "Failed to allocate memory"
        }
    }
}

public extension RTCAudioBuffer {
    /// Target sample rate for WebRTC audio
    static let targetSampleRate: Double = 48000
    
    /// Convert AVAudioPCMBuffer to RTCAudioBuffer
    /// - Parameter pcmBuffer: Source PCM buffer
    /// - Returns: Configured RTCAudioBuffer
    /// - Throws: AudioBufferConversionError
    static func convert(from pcmBuffer: AVAudioPCMBuffer) throws -> RTCAudioBuffer {
        guard pcmBuffer.format.commonFormat == .pcmFormatFloat32 else {
            throw AudioBufferConversionError.invalidFormat
        }
        
        let frameCount = Int(pcmBuffer.frameLength)
        guard frameCount > 0 else {
            throw AudioBufferConversionError.bufferSizeMismatch
        }
        
        guard let floatData = pcmBuffer.floatChannelData else {
            throw AudioBufferConversionError.invalidFormat
        }
        
        // Create RTCAudioBuffer with appropriate size
        let buffer = try RTCAudioBuffer(capacity: frameCount)
        
        // Copy the first channel data (mono)
        try buffer.copyBytes(from: floatData[0], count: frameCount)
        
        return buffer
    }
    
    /// Convert sample rate if needed
    private static func convertSampleRate(
        from pcmBuffer: AVAudioPCMBuffer,
        to rtcBuffer: RTCAudioBuffer,
        sourceRate: Double
    ) throws {
        // Placeholder for sample rate conversion
        throw AudioBufferConversionError.incompatibleSampleRate
    }
}