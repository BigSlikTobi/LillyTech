import OSLog
import Foundation

struct AppLogger {
    private static let subsystem = "com.Transearly.LillyTech"
    
    static let general = Logger(subsystem: subsystem, category: "general")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
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
    
    static func log(_ message: String, level: Level, category: Logger = general, isProduction: Bool = false) {
        #if DEBUG
        category.log(level: level.osLogType, "\(message)")
        #else
        if isProduction || level == .error {
            category.log(level: level.osLogType, "\(message)")
        }
        #endif
    }
    
    static func debug(_ message: String, category: Logger = general) {
        log(message, level: .debug, category: category)
    }
    
    static func info(_ message: String, category: Logger = general) {
        log(message, level: .info, category: category)
    }
    
    static func warning(_ message: String, category: Logger = general) {
        log(message, level: .warning, category: category)
    }
    
    static func error(_ message: String, category: Logger = general) {
        log(message, level: .error, category: category)
    }
}