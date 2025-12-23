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
/// - Performs on-device analysis (OCR + basic detections) via Vision
/// - Feeds extracted signals to ModelService as text (works without raw pixel support)
/// - Handles image-specific prompts and follow-ups when needed
@available(macOS 26.0, iOS 26.0, *)
public class VisionAgent: BaseAgent, @unchecked Sendable {
    /// FileManagerService for reading image files
    private let fileManagerService = FileManagerService.shared
    
    private static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "bmp", "tiff", "tif"
    ]
    
    public init() {
        super.init(
            id: AgentId.visionAgent,
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
            return Self.supportedImageExtensions.contains(ext)
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
        let fileExists = FileManager.default.fileExists(atPath: imagePath)
        
        guard fileExists else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "Image not found at path: \(imagePath)",
                success: false,
                error: VisionAgentError.imageNotFound(imagePath).localizedDescription
            )
        }
        
        // Get contentType separately so we can use it in error logging
        let contentType = try? imageURL.resourceValues(forKeys: [.contentTypeKey]).contentType
        let ext = imageURL.pathExtension.lowercased()
        let isImageByExtension = Self.supportedImageExtensions.contains(ext)
        
        guard (contentType?.conforms(to: .image) ?? false) || isImageByExtension else {
            return AgentResult(
                agentId: id,
                taskId: task.id,
                content: "File at path \(imagePath) is not a recognized image format.",
                success: false,
                error: "Invalid image file"
            )
        }
        
        // Build prompt for image analysis
        let userQuery = task.description.isEmpty ? "What's in this image? Describe it in detail." : task.description
        let analysis = await VisionAnalysisService.analyzeImage(atPath: imagePath)
        
        // Get ModelService and create a response with image
        let service = await modelService
        
        // Create a prompt that includes both text and image
        // We'll use ModelService's respond method which will handle image segments
        // For now, we'll pass the image data through the context and let ModelService handle it
        var analysisBlock = """
        Image: \(imageURL.lastPathComponent)
        Path: \(imagePath)
        """
        
        if let w = analysis.pixelWidth, let h = analysis.pixelHeight {
                analysisBlock += "\nDimensions: \(w)x\(h) px"
            analysisBlock += "\nFile size: \(analysis.fileSizeBytes) bytes"
            if !analysis.classifications.isEmpty {
                analysisBlock += "\nLikely contents: \(analysis.classifications.joined(separator: ", "))"
            }
            analysisBlock += "\nFaces detected: \(analysis.faceCount)"
            if !analysis.barcodePayloads.isEmpty {
                analysisBlock += "\nBarcodes: \(analysis.barcodePayloads.joined(separator: ", "))"
            }
            if let text = analysis.recognizedText, !text.isEmpty {
                let maxChars = 6000
                let clipped = text.count > maxChars ? String(text.prefix(maxChars)) + "\n…(truncated)" : text
                analysisBlock += "\n\nOCR text:\n\(clipped)"
            }
        } else {
            analysisBlock += "\nFile size: \(analysis.fileSizeBytes) bytes"
            analysisBlock += "\nFaces detected: \(analysis.faceCount)"
        }
        
        let prompt = """
        You are helping a user with an image-related request.
        
        User question:
        \(userQuery)
        
        On-device extracted signals from the image (OCR + detections; no direct pixel access):
        \(analysisBlock)
        
        Instructions:
        - Answer using the extracted signals.
        - If the question requires visual details not present in OCR/detections, ask a precise follow-up question.
        """
        var updatedContext = context
        updatedContext.fileReferences.append(imagePath)
        updatedContext.metadata["imagePath"] = imagePath
        updatedContext.metadata["imageFileName"] = analysis.fileName
        updatedContext.metadata["imageFileSizeBytes"] = String(analysis.fileSizeBytes)
        if let w = analysis.pixelWidth { updatedContext.metadata["imagePixelWidth"] = String(w) }
        if let h = analysis.pixelHeight { updatedContext.metadata["imagePixelHeight"] = String(h) }
        if !analysis.classifications.isEmpty { updatedContext.metadata["imageClassifications"] = analysis.classifications.joined(separator: ", ") }
        updatedContext.metadata["imageFaceCount"] = String(analysis.faceCount)
        if let text = analysis.recognizedText { updatedContext.metadata["imageRecognizedText"] = text }
        if !analysis.barcodePayloads.isEmpty {
            updatedContext.metadata["imageBarcodes"] = analysis.barcodePayloads.joined(separator: ", ")
        }
        
        // Use ModelService to respond with image
        // Pass the image path so ModelService can handle it
        let response = try await service.respond(to: prompt)
        
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
        return Self.supportedImageExtensions.contains(ext)
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
