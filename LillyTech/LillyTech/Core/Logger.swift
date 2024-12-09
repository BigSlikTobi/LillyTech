import OSLog
import Foundation

// Define LoggerProtocol at file scope
protocol LoggerProtocol {
    func debug(_ message: String, category: Logger)
    func info(_ message: String, category: Logger)
    func warning(_ message: String, category: Logger)
    func error(_ message: String, category: Logger)
}

class LoggerWrapper: LoggerProtocol {
    private let logger: Logger
    
    init(_ logger: Logger) {
        self.logger = logger
    }
    
    func debug(_ message: String, category: Logger) {
        logger.log(level: .debug, "\(message)")
    }
    
    func info(_ message: String, category: Logger) {
        logger.log(level: .info, "\(message)")
    }
    
    func warning(_ message: String, category: Logger) {
        logger.log(level: .default, "\(message)")
    }
    
    func error(_ message: String, category: Logger) {
        logger.log(level: .error, "\(message)")
    }
}

// Change AppLogger to a class and add a shared instance
class AppLogger {
    private static let subsystem = "com.Transearly.LillyTech"
    
    // Singleton instance
    static let shared = AppLogger()
    
    // Logger categories as instance properties
    let general: Logger
    let network: Logger
    let ui: Logger
    let audio: Logger
    public var webrtc: LoggerProtocol  // Change webrtc type to LoggerProtocol
    let signaling: Logger  // Add this line
    
    // Initialize loggers
    private init() {
        general = Logger(subsystem: AppLogger.subsystem, category: "general")
        network = Logger(subsystem: AppLogger.subsystem, category: "network")
        ui = Logger(subsystem: AppLogger.subsystem, category: "ui")
        audio = Logger(subsystem: AppLogger.subsystem, category: "audio")
        webrtc = LoggerWrapper(Logger(subsystem: AppLogger.subsystem, category: "webrtc"))  // Wrap Logger in LoggerWrapper
        signaling = Logger(subsystem: AppLogger.subsystem, category: "signaling")
    }
    
    enum Level {
        case debug
        case info
        case warning
        case error
        
        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
    }
    
    // Convert static methods to instance methods
    func log(_ message: String, level: Level, category: Logger = AppLogger.shared.general, isProduction: Bool = false) {
        #if DEBUG
        category.log(level: level.osLogType, "\(message)")
        #else
        if isProduction || level == .error {
            category.log(level: level.osLogType, "\(message)")
        }
        #endif
    }
    
    func debug(_ message: String, category: Logger = AppLogger.shared.general) {
        log(message, level: .debug, category: category)
    }
    
    func info(_ message: String, category: Logger = AppLogger.shared.general) {
        log(message, level: .info, category: category)
    }
    
    func warning(_ message: String, category: Logger = AppLogger.shared.general) {
        log(message, level: .warning, category: category)
    }
    
    func error(_ message: String, category: Logger = AppLogger.shared.general) {
        log(message, level: .error, category: category)
    }
    
    // Add signaling-specific convenience methods
    func debugSignaling(_ message: String) {
        log(message, level: .debug, category: signaling)
    }
    
    func infoSignaling(_ message: String) {
        log(message, level: .info, category: signaling)
    }
    
    func warningSignaling(_ message: String) {
        log(message, level: .warning, category: signaling)
    }
    
    func errorSignaling(_ message: String) {
        log(message, level: .error, category: signaling)
    }
}