//
//  VisionAnalysisService.swift
//  FoundationChatCore
//
//  Lightweight on-device image analysis (OCR + basic detections) for VisionAgent.
//

import Foundation
import CoreGraphics
import ImageIO
import Vision

@available(macOS 26.0, iOS 26.0, *)
public struct VisionAnalysisResult: Sendable {
    public let fileName: String
    public let fileSizeBytes: Int
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let classifications: [String]
    public let recognizedText: String?
    public let barcodePayloads: [String]
    public let faceCount: Int
    
    public init(
        fileName: String,
        fileSizeBytes: Int,
        pixelWidth: Int?,
        pixelHeight: Int?,
        classifications: [String],
        recognizedText: String?,
        barcodePayloads: [String],
        faceCount: Int
    ) {
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.classifications = classifications
        self.recognizedText = recognizedText
        self.barcodePayloads = barcodePayloads
        self.faceCount = faceCount
    }
}

@available(macOS 26.0, iOS 26.0, *)
public enum VisionAnalysisService {
    /// Max image size to fully process with Vision requests (bytes).
    /// Above this, we still return basic metadata but skip OCR/detections.
    public static let maxProcessableImageBytes = 15 * 1024 * 1024
    
    public static func analyzeImage(atPath path: String) async -> VisionAnalysisResult {
        await analyzeImage(url: URL(fileURLWithPath: path))
    }
    
    public static func analyzeImage(url: URL) async -> VisionAnalysisResult {
        await Task.detached(priority: .userInitiated) {
            let fileName = url.lastPathComponent
            let fileSizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            
            let (pixelWidth, pixelHeight) = imageDimensions(url: url)
            
            guard fileSizeBytes <= maxProcessableImageBytes else {
                return VisionAnalysisResult(
                    fileName: fileName,
                    fileSizeBytes: fileSizeBytes,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    classifications: [],
                    recognizedText: nil,
                    barcodePayloads: [],
                    faceCount: 0
                )
            }
            
            guard let cgImage = loadCGImage(url: url) else {
                return VisionAnalysisResult(
                    fileName: fileName,
                    fileSizeBytes: fileSizeBytes,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    classifications: [],
                    recognizedText: nil,
                    barcodePayloads: [],
                    faceCount: 0
                )
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            
            let barcodeRequest = VNDetectBarcodesRequest()
            let facesRequest = VNDetectFaceRectanglesRequest()
            let classifyRequest = VNClassifyImageRequest()
            
            do {
                try handler.perform([textRequest, barcodeRequest, facesRequest, classifyRequest])
            } catch {
                return VisionAnalysisResult(
                    fileName: fileName,
                    fileSizeBytes: fileSizeBytes,
                    pixelWidth: pixelWidth,
                    pixelHeight: pixelHeight,
                    classifications: [],
                    recognizedText: nil,
                    barcodePayloads: [],
                    faceCount: 0
                )
            }
            
            let recognizedText = textRequest.results?
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            let barcodePayloads = barcodeRequest.results?
                .compactMap { $0.payloadStringValue }
                .filter { !$0.isEmpty } ?? []
            
            let faceCount = facesRequest.results?.count ?? 0
            
            let classifications = (classifyRequest.results ?? [])
                .prefix(8)
                .map { obs in
                    let pct = Int((obs.confidence * 100.0).rounded())
                    return "\(obs.identifier) (\(pct)%)"
                }
            
            return VisionAnalysisResult(
                fileName: fileName,
                fileSizeBytes: fileSizeBytes,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                classifications: classifications,
                recognizedText: recognizedText?.isEmpty == true ? nil : recognizedText,
                barcodePayloads: barcodePayloads,
                faceCount: faceCount
            )
        }.value
    }
    
    private static func imageDimensions(url: URL) -> (Int?, Int?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return (nil, nil) }
        
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        return (width, height)
    }
    
    private static func loadCGImage(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
