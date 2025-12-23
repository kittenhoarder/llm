
import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class TaskDecompositionParserJSONTests: XCTestCase {
    
    var parser: TaskDecompositionParser!
    var agents: [any Agent]!
    
    override func setUp() {
        super.setUp()
        parser = TaskDecompositionParser()
        
        // Mock agents
        agents = [
            BaseAgent(
                name: "WebFinder", 
                description: "Search web", 
                capabilities: [.webSearch]
            ),
            BaseAgent(
                name: "CodeScanner", 
                description: "Read code", 
                capabilities: [.codeAnalysis]
            ),
             BaseAgent(
                name: "Reviewer", 
                description: "Review logic", 
                capabilities: [.generalReasoning]
            )
        ]
    }
    
    func testParseJSONDecomposition() async {
        let jsonOutput = """
        Here is the plan:
        ```json
        {
          "subtasks": [
            {
              "id": 1,
              "description": "Search for documentation on Swift Actors",
              "agent": "WebFinder",
              "dependencies": []
            },
            {
              "id": 2,
              "description": "Analyze Actor implementation in codebase",
              "agent": "CodeScanner",
              "dependencies": [1]
            },
             {
              "id": 3,
              "description": "Synthesize findings",
              "agent": "Reviewer",
              "dependencies": [1, 2]
            }
          ]
        }
        ```
        """
        
        let result = await parser.parse(jsonOutput, availableAgents: agents)
        
        XCTAssertNotNil(result, "Should parse JSON successfully")
        XCTAssertEqual(result?.subtasks.count, 3)
        
        let first = result?.subtasks.first(where: { $0.description.contains("Search") })
        XCTAssertEqual(first?.agentName, "WebFinder")
        XCTAssertTrue(first?.dependencies.isEmpty ?? false)
        
        let second = result?.subtasks.first(where: { $0.description.contains("Analyze") })
        XCTAssertEqual(second?.agentName, "CodeScanner")
        XCTAssertEqual(second?.dependencies.count, 1)
        
        let third = result?.subtasks.first(where: { $0.description.contains("Synthesize") })
        XCTAssertEqual(third?.dependencies.count, 2)
    }
    
    func testParseJSONWithoutMarkdown() async {
        let jsonOutput = """
        {
          "subtasks": [
            {
              "id": 1,
              "description": "Just one task",
              "agent": "WebFinder",
              "dependencies": []
            }
          ]
        }
        """
        
        let result = await parser.parse(jsonOutput, availableAgents: agents)
        
        XCTAssertNotNil(result, "Should parse raw JSON successfully")
        XCTAssertEqual(result?.subtasks.count, 1)
        XCTAssertEqual(result?.subtasks.first?.agentName, "WebFinder")
    }
}
