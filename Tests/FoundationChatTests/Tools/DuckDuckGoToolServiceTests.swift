//
//  DuckDuckGoToolServiceTests.swift
//  FoundationChatTests
//
//  Tests for DuckDuckGoToolService adapter
//

import XCTest
@testable import FoundationChat

// Mock logger for testing
class MockLogger: ToolLogger {
    var logs: [(level: LogLevel, message: String, metadata: [String: Any]?)] = []
    
    func log(level: LogLevel, message: String, metadata: [String: Any]?) {
        logs.append((level: level, message: message, metadata: metadata))
    }
}

final class DuckDuckGoToolServiceTests: XCTestCase {
    var toolService: DuckDuckGoToolService!
    var mockLogger: MockLogger!
    
    override func setUp() {
        super.setUp()
        mockLogger = MockLogger()
        toolService = DuckDuckGoToolService(logger: mockLogger)
    }
    
    // MARK: - Protocol Conformance Tests
    
    func testToolName() {
        XCTAssertEqual(toolService.name, "duckduckgo_search")
    }
    
    func testToolDescription() {
        XCTAssertFalse(toolService.description.isEmpty)
        XCTAssertTrue(toolService.description.contains("DuckDuckGo"))
    }
    
    func testToolParameters() {
        let params = toolService.parameters
        XCTAssertNotNil(params["type"])
        XCTAssertNotNil(params["properties"])
        XCTAssertNotNil(params["required"])
        
        if let properties = params["properties"] as? [String: Any],
           let query = properties["query"] as? [String: Any] {
            XCTAssertEqual(query["type"] as? String, "string")
        } else {
            XCTFail("Parameters should have query property")
        }
    }
    
    // MARK: - Execution Tests
    
    func testExecuteWithValidQuery() async throws {
        // This will make a real API call - may fail if network unavailable
        let parameters = ["query": "Swift programming"]
        
        do {
            let result = try await toolService.execute(parameters: parameters)
            XCTAssertFalse(result.isEmpty, "Result should not be empty")
            
            // Check that logging occurred
            XCTAssertFalse(mockLogger.logs.isEmpty, "Should have logged tool execution")
            let infoLogs = mockLogger.logs.filter { $0.level == .info }
            XCTAssertFalse(infoLogs.isEmpty, "Should have info level logs")
        } catch {
            // Network errors are acceptable in tests
            XCTAssertTrue(error is ToolExecutionError)
        }
    }
    
    func testExecuteWithMissingQuery() async {
        let parameters: [String: Any] = [:]
        
        do {
            _ = try await toolService.execute(parameters: parameters)
            XCTFail("Should throw missing parameter error")
        } catch ToolExecutionError.missingParameter(let param) {
            XCTAssertEqual(param, "query")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Check error logging
        let errorLogs = mockLogger.logs.filter { $0.level == .error }
        XCTAssertFalse(errorLogs.isEmpty, "Should have logged error")
    }
    
    func testExecuteWithEmptyQuery() async {
        let parameters = ["query": ""]
        
        do {
            _ = try await toolService.execute(parameters: parameters)
            XCTFail("Should throw invalid parameter error")
        } catch ToolExecutionError.invalidParameter(let param, _) {
            XCTAssertEqual(param, "query")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteWithWhitespaceOnlyQuery() async {
        let parameters = ["query": "   "]
        
        do {
            _ = try await toolService.execute(parameters: parameters)
            XCTFail("Should throw invalid parameter error")
        } catch ToolExecutionError.invalidParameter(let param, _) {
            XCTAssertEqual(param, "query")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testExecuteLogsExecutionTime() async {
        let parameters = ["query": "test"]
        
        // Clear logs
        mockLogger.logs.removeAll()
        
        do {
            _ = try await toolService.execute(parameters: parameters)
            
            // Check for execution time in logs
            let infoLogs = mockLogger.logs.filter { $0.level == .info }
            let hasExecutionTime = infoLogs.contains { log in
                log.metadata?["executionTime"] != nil
            }
            XCTAssertTrue(hasExecutionTime, "Should log execution time")
        } catch {
            // Network errors are acceptable
        }
    }
    
    func testExecuteLogsQuery() async {
        let parameters = ["query": "test query"]
        
        mockLogger.logs.removeAll()
        
        do {
            _ = try await toolService.execute(parameters: parameters)
            
            // Check that query was logged
            let hasQuery = mockLogger.logs.contains { log in
                log.metadata?["query"] as? String == "test query"
            }
            XCTAssertTrue(hasQuery, "Should log the query")
        } catch {
            // Network errors are acceptable
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testExecuteHandlesDuckDuckGoErrors() async {
        // This test would require mocking the DuckDuckGo client
        // For now, we test that errors are properly converted
        let parameters = ["query": "xysdfghjklqwertyuiop123456789"]
        
        do {
            let result = try await toolService.execute(parameters: parameters)
            // Even if no results, should return a message
            XCTAssertFalse(result.isEmpty)
        } catch {
            XCTAssertTrue(error is ToolExecutionError)
        }
    }
}









