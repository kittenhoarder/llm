//
//  VisionAgent.swift
//  FoundationChatCore
//
//  Agent specialized in analyzing images using vision models
//

import Foundation
import UniformTypeIdentifiers
import FoundationModels

/// Agent that analyzes images using vision capabilities
///
/// **Status**: ✅ Functional
/// - Detects image file types (PNG, JPEG, HEIC, etc.)
/// - Loads images from file paths
/// - Passes images to ModelService with proper image segments
/// - Handles image-specific prompts
@available(macOS 26.0, iOS 26.0, *)
public class VisionAgent: BaseAgent, @unchecked Sendable {
    /// FileManagerService for reading image files
    private let fileManagerService = FileManagerService.shared
    
    public init() {
        super.init(
            name: AgentName.visionAgent,
            description: "Analyzes images using vision models. Can describe images, identify objects, read text in images, and answer questions about visual content.",
            capabilities: [.imageAnalysis],
            tools: []
        )
    }
    
    public override func process(task: AgentTask, context: AgentContext) async throws -> AgentResult {
        // Extract image file path from task or context
        guard let imagePath = task.parameters["imagePath"] ?? context.fileReferences.first(where: { path in
            // Check if this path points to an image file
            let url = URL(fileURLWithPath: path)
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
                return type.conforms(to: .image)
            }
            // Fallback: check file extension
            let ext = url.pathExtension.lowercased()
            return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"].contains(ext)
        }) else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "No image file path specified. Please provide an image file path in the task parameters or context.",
                success: false,
                error: "Missing image file path"
            )
        }
        
        // Verify the file is actually an image
        let imageURL = URL(fileURLWithPath: imagePath)
        guard let contentType = try? imageURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
              contentType.conforms(to: .image) else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "File at path \(imagePath) is not a recognized image format.",
                success: false,
                error: "Invalid image file"
            )
        }
        
        // Load image data
        let imageData: Data
        do {
            imageData = try Data(contentsOf: imageURL)
        } catch {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "Failed to load image from \(imagePath): \(error.localizedDescription)",
                success: false,
                error: error.localizedDescription
            )
        }
        
        // Build prompt for image analysis
        let userQuery = task.description.isEmpty ? "What's in this image? Describe it in detail." : task.description
        
        // Get ModelService and create a response with image
        let service = await modelService
        
        // Create a prompt that includes both text and image
        // We'll use ModelService's respond method which will handle image segments
        // For now, we'll pass the image data through the context and let ModelService handle it
        var updatedContext = context
        updatedContext.fileReferences.append(imagePath)
        updatedContext.metadata["imageData"] = imageData.base64EncodedString() // Store as base64 for now
        updatedContext.metadata["imagePath"] = imagePath
        
        // Use ModelService to respond with image
        // Pass the image path so ModelService can handle it
        let response = try await service.respond(to: userQuery, withImages: [imagePath])
        
        return AgentResult(
            agentId: id,
            taskId: task.id,
            content: response.content,
            success: true,
            toolCalls: response.toolCalls,
            updatedContext: updatedContext
        )
    }
    
    /// Check if a file path points to an image
    /// - Parameter path: File path to check
    /// - Returns: True if the file is an image
    private func isImageFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.conforms(to: .image)
        }
        // Fallback: check file extension
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"].contains(ext)
    }
}

/// Errors specific to VisionAgent operations
@available(macOS 26.0, iOS 26.0, *)
public enum VisionAgentError: Error, LocalizedError, Sendable {
    case imageNotFound(String)
    case invalidImageFormat(String)
    case imageLoadFailed(String)
    case visionModelUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .imageNotFound(let path):
            return "Image not found at path: \(path)"
        case .invalidImageFormat(let path):
            return "Invalid image format at path: \(path)"
        case .imageLoadFailed(let message):
            return "Failed to load image: \(message)"
        case .visionModelUnavailable:
            return "Vision model is not available"
        }
    }
}

