//
//  LillyTechUITests.swift
//  LillyTechUITests
//
//  Created by Tobias Latta on 24.11.24.
//

import XCTest

final class LillyTechUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.Transearly.LillyTech")
        app.launchArguments = ["--uitesting"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testBasicAppLaunch() throws {
        app.launch()
        // Add more specific UI element checks
        XCTAssertTrue(app.exists)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }
    
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
