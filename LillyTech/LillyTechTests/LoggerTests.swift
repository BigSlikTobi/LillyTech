import XCTest
import OSLog
@testable import LillyTech

final class LoggerTests: XCTestCase {
    private var logger: AppLogger!
    
    override func setUp() {
        super.setUp()
        logger = AppLogger.shared
    }
    
    override func tearDown() {
        logger = nil
        super.tearDown()
    }
    
    func testLogLevels() {
        // Verify all log levels map correctly
        XCTAssertEqual(AppLogger.Level.debug.osLogType, .debug)
        XCTAssertEqual(AppLogger.Level.info.osLogType, .info)
        XCTAssertEqual(AppLogger.Level.warning.osLogType, .default)
        XCTAssertEqual(AppLogger.Level.error.osLogType, .error)
    }
    
    func testLoggersExist() {
        XCTAssertNotNil(logger.general)
        XCTAssertNotNil(logger.network)
        XCTAssertNotNil(logger.ui)
    }
    
    func testLoggingDoesNotCrash() {
        XCTAssertNoThrow(logger.debug("Debug message"))
        XCTAssertNoThrow(logger.info("Info message"))
        XCTAssertNoThrow(logger.warning("Warning message"))
        XCTAssertNoThrow(logger.error("Error message"))
    }
    
    func testCategorySpecificLogging() {
        XCTAssertNoThrow(logger.debug("Network debug", category: logger.network))
        XCTAssertNoThrow(logger.error("UI error", category: logger.ui))
    }
    
    func testProductionLogging() {
        XCTAssertNoThrow(logger.log("Production message", level: .info, isProduction: true))
        XCTAssertNoThrow(logger.log("Error message", level: .error, isProduction: false))
    }
    
    func testConvenienceMethods() {
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        
        // Test with specific categories
        logger.debug("Network debug", category: logger.network)
        logger.error("UI error", category: logger.ui)
    }
}