//
//  WebSearchTool.swift
//  FoundationChatCore
//
//  WKWebView-based web search tool for real web searches
//

import Foundation
import WebKit

/// Search result from web search
@available(macOS 26.0, iOS 26.0, *)
public struct SearchResult: Sendable {
    /// Title of the result
    public let title: String
    
    /// URL of the result
    public let url: String
    
    /// Snippet/description
    public let snippet: String
    
    /// Extracted content (if fetched)
    public var content: String?
    
    public init(title: String, url: String, snippet: String, content: String? = nil) {
        self.title = title
        self.url = url
        self.snippet = snippet
        self.content = content
    }
}

/// Web search tool using WKWebView
@available(macOS 26.0, iOS 26.0, *)
public actor WebSearchTool {
    /// Search engine to use
    public enum SearchEngine: String, Sendable {
        case google = "Google"
        case bing = "Bing"
        case duckduckgo = "DuckDuckGo"
    }
    
    /// Maximum number of results to return
    private let maxResults: Int
    
    /// Maximum content length per result
    private let maxContentLength: Int
    
    /// Timeout for web operations (seconds)
    private let timeout: TimeInterval
    
    /// Search engine to use
    private let searchEngine: SearchEngine
    
    public init(
        maxResults: Int = 5,
        maxContentLength: Int = 500,
        timeout: TimeInterval = 15.0,
        searchEngine: SearchEngine = .duckduckgo
    ) {
        self.maxResults = maxResults
        self.maxContentLength = maxContentLength
        self.timeout = timeout
        self.searchEngine = searchEngine
    }
    
    /// Perform a web search
    /// - Parameter query: Search query
    /// - Returns: Array of search results
    public func search(query: String) async throws -> [SearchResult] {
        let searchURL = buildSearchURL(query: query)
        
        // Use WKWebView to load and extract results
        let results = try await performSearch(url: searchURL, query: query)
        
        return Array(results.prefix(maxResults))
    }
    
    /// Build search URL for the selected search engine
    private func buildSearchURL(query: String) -> URL {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        let urlString: String
        switch searchEngine {
        case .google:
            urlString = "https://www.google.com/search?q=\(encodedQuery)"
        case .bing:
            urlString = "https://www.bing.com/search?q=\(encodedQuery)"
        case .duckduckgo:
            urlString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)"
        }
        
        guard let url = URL(string: urlString) else {
            fatalError("Invalid search URL: \(urlString)")
        }
        
        return url
    }
    
    /// Perform search using WKWebView
    private func performSearch(url: URL, query: String) async throws -> [SearchResult] {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let webView = WKWebView()
                let delegate = WebViewDelegate(
                    query: query,
                    maxResults: maxResults,
                    continuation: continuation
                )
                
                // Store delegate to prevent deallocation
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                
                webView.navigationDelegate = delegate
                
                // Load the search page
                let request = URLRequest(url: url)
                webView.load(request)
                
                // Set timeout
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if !delegate.hasCompleted {
                        continuation.resume(throwing: WebSearchError.timeout)
                    }
                }
            }
        }
    }
    
    /// Extract content from a URL (optional, for top results)
    /// - Parameter url: URL to extract content from
    /// - Returns: Extracted content
    public func extractContent(from url: URL) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let webView = WKWebView()
                let delegate = ContentExtractionDelegate(
                    maxLength: maxContentLength,
                    continuation: continuation
                )
                
                objc_setAssociatedObject(webView, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                webView.navigationDelegate = delegate
                
                let request = URLRequest(url: url)
                webView.load(request)
                
                Task {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if !delegate.hasCompleted {
                        continuation.resume(throwing: WebSearchError.timeout)
                    }
                }
            }
        }
    }
}

/// Web search errors
@available(macOS 26.0, iOS 26.0, *)
public enum WebSearchError: Error, Sendable {
    case timeout
    case extractionFailed
    case invalidResponse
}

/// WKWebView delegate for search result extraction
@MainActor
private class WebViewDelegate: NSObject, WKNavigationDelegate {
    let query: String
    let maxResults: Int
    let continuation: CheckedContinuation<[SearchResult], Error>
    var hasCompleted = false
    
    init(query: String, maxResults: Int, continuation: CheckedContinuation<[SearchResult], Error>) {
        self.query = query
        self.maxResults = maxResults
        self.continuation = continuation
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }
        hasCompleted = true
        
        // Extract search results using JavaScript
        webView.evaluateJavaScript(extractSearchResultsScript) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.continuation.resume(throwing: error)
                return
            }
            
            guard let results = self.parseSearchResults(result) else {
                self.continuation.resume(throwing: WebSearchError.extractionFailed)
                return
            }
            
            self.continuation.resume(returning: results)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        continuation.resume(throwing: error)
    }
    
    /// JavaScript to extract search results
    private var extractSearchResultsScript: String {
        """
        (function() {
            var results = [];
            
            // Try Google results
            var googleResults = document.querySelectorAll('div.g');
            if (googleResults.length > 0) {
                googleResults.forEach(function(result, index) {
                    if (index >= \(maxResults)) return;
                    var titleEl = result.querySelector('h3');
                    var linkEl = result.querySelector('a');
                    var snippetEl = result.querySelector('span');
                    if (titleEl && linkEl) {
                        results.push({
                            title: titleEl.textContent.trim(),
                            url: linkEl.href,
                            snippet: snippetEl ? snippetEl.textContent.trim() : ''
                        });
                    }
                });
                return results;
            }
            
            // Try Bing results
            var bingResults = document.querySelectorAll('li.b_algo');
            if (bingResults.length > 0) {
                bingResults.forEach(function(result, index) {
                    if (index >= \(maxResults)) return;
                    var titleEl = result.querySelector('h2 a');
                    var snippetEl = result.querySelector('p');
                    if (titleEl) {
                        results.push({
                            title: titleEl.textContent.trim(),
                            url: titleEl.href,
                            snippet: snippetEl ? snippetEl.textContent.trim() : ''
                        });
                    }
                });
                return results;
            }
            
            // Try DuckDuckGo results
            var ddgResults = document.querySelectorAll('div.result');
            if (ddgResults.length > 0) {
                ddgResults.forEach(function(result, index) {
                    if (index >= \(maxResults)) return;
                    var titleEl = result.querySelector('a.result__a');
                    var snippetEl = result.querySelector('a.result__snippet');
                    if (titleEl) {
                        results.push({
                            title: titleEl.textContent.trim(),
                            url: titleEl.href,
                            snippet: snippetEl ? snippetEl.textContent.trim() : ''
                        });
                    }
                });
                return results;
            }
            
            return results;
        })();
        """
    }
    
    /// Parse JavaScript results into SearchResult array
    private func parseSearchResults(_ result: Any?) -> [SearchResult]? {
        guard let results = result as? [[String: Any]] else {
            return nil
        }
        
        return results.compactMap { dict in
            guard let title = dict["title"] as? String,
                  let url = dict["url"] as? String else {
                return nil
            }
            let snippet = dict["snippet"] as? String ?? ""
            return SearchResult(title: title, url: url, snippet: snippet)
        }
    }
}

/// WKWebView delegate for content extraction
@MainActor
private class ContentExtractionDelegate: NSObject, WKNavigationDelegate {
    let maxLength: Int
    let continuation: CheckedContinuation<String, Error>
    var hasCompleted = false
    
    init(maxLength: Int, continuation: CheckedContinuation<String, Error>) {
        self.maxLength = maxLength
        self.continuation = continuation
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !hasCompleted else { return }
        hasCompleted = true
        
        // Extract main content
        let script = """
        (function() {
            // Remove script and style elements
            var scripts = document.querySelectorAll('script, style, nav, header, footer, aside');
            scripts.forEach(function(el) { el.remove(); });
            
            // Get main content
            var main = document.querySelector('main, article, [role="main"]') || document.body;
            var text = main.innerText || main.textContent || '';
            return text.trim().substring(0, \(maxLength));
        })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                self.continuation.resume(throwing: error)
                return
            }
            
            let content = (result as? String) ?? ""
            self.continuation.resume(returning: content)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard !hasCompleted else { return }
        hasCompleted = true
        continuation.resume(throwing: error)
    }
}




