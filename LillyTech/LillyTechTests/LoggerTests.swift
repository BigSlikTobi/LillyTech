import XCTest
import OSLog
@testable import LillyTech

final class LoggerTests: XCTestCase {
    func testLogLevels() {
        // Verify all log levels map correctly
        XCTAssertEqual(AppLogger.Level.debug.osLogType, .debug)
        XCTAssertEqual(AppLogger.Level.info.osLogType, .info)
        XCTAssertEqual(AppLogger.Level.warning.osLogType, .default)
        XCTAssertEqual(AppLogger.Level.error.osLogType, .error)
    }
    
    func testLoggersExist() {
        // Verify logger instances exist
        XCTAssertNotNil(AppLogger.general)
        XCTAssertNotNil(AppLogger.network)
        XCTAssertNotNil(AppLogger.ui)
    }
    
    func testLoggingDoesNotCrash() {
        // Verify logging calls don't crash
        XCTAssertNoThrow(AppLogger.debug("Debug message"))
        XCTAssertNoThrow(AppLogger.info("Info message"))
        XCTAssertNoThrow(AppLogger.warning("Warning message"))
        XCTAssertNoThrow(AppLogger.error("Error message"))
    }
    
    func testCategorySpecificLogging() {
        // Test logging with different categories doesn't crash
        XCTAssertNoThrow(AppLogger.debug("Network debug", category: AppLogger.network))
        XCTAssertNoThrow(AppLogger.error("UI error", category: AppLogger.ui))
    }
    
    func testProductionLogging() {
        // Verify production logging doesn't crash
        XCTAssertNoThrow(AppLogger.log("Production message", level: .info, isProduction: true))
        XCTAssertNoThrow(AppLogger.log("Error message", level: .error, isProduction: false))
    }
    
    func testConvenienceMethods() {
        AppLogger.debug("Debug message")
        AppLogger.info("Info message")
        AppLogger.warning("Warning message")
        AppLogger.error("Error message")
        
        // Test with specific categories
        AppLogger.debug("Network debug", category: AppLogger.network)
        AppLogger.error("UI error", category: AppLogger.ui)
    }
}