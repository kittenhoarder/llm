//
//  main.swift
//  SerpAPITest
//
//  Standalone executable for manually testing SerpAPI integration
//

import Foundation
import FoundationChatCore

@main
struct SerpAPITest {
    static func main() async {
        print("SerpAPI Manual Test")
        print("==================\n")
        
        // Get API key from command line arguments or environment variable
        let apiKey: String?
        if CommandLine.arguments.count > 2 {
            // Check for --api-key flag
            if let keyIndex = CommandLine.arguments.firstIndex(of: "--api-key"),
               keyIndex + 1 < CommandLine.arguments.count {
                apiKey = CommandLine.arguments[keyIndex + 1]
            } else {
                apiKey = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"]
            }
        } else {
            apiKey = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"]
        }
        
        guard let key = apiKey, !key.isEmpty else {
            print("Error: SerpAPI API key not found.")
            print("Usage:")
            print("  swift run SerpAPITest --api-key YOUR_KEY")
            print("  SERPAPI_API_KEY=YOUR_KEY swift run SerpAPITest")
            exit(1)
        }
        
        print("API Key: \(String(key.prefix(8)))...\(String(key.suffix(4)))")
        print()
        
        // Test queries
        let testQueries = [
            "Swift programming language",
            "Apple Foundation Models",
            "current weather in San Francisco"
        ]
        
        let client = SerpAPIClient(apiKey: key)
        let tool = SerpAPITool(client: client, maxResults: 3)
        
        for (index, query) in testQueries.enumerated() {
            print("Test \(index + 1): Searching for '\(query)'")
            print("-" * 50)
            
            do {
                let result = try await tool.search(query: query)
                print(result)
                print()
            } catch {
                print("Error: \(error.localizedDescription)")
                if let serpapiError = error as? SerpAPIError {
                    print("Failure reason: \(serpapiError.failureReason ?? "Unknown")")
                }
                print()
            }
            
            // Small delay between requests
            if index < testQueries.count - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        print("Tests completed!")
    }
}

// Helper extension for string repetition (for visual separator)
extension String {
    static func *(lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}


