//
//  VisionAnalysisServiceTests.swift
//  FoundationChatCoreTests
//
//  Unit tests for VisionAnalysisService (OCR + detections scaffolding)
//

import XCTest
@testable import FoundationChatCore

@available(macOS 26.0, iOS 26.0, *)
final class VisionAnalysisServiceTests: XCTestCase {
    func testAnalyzeImageReturnsMetadataForPNG() async throws {
        let imagePath = "/tmp/test_image.png"
        let pngData = createMinimalPNG()
        try pngData.write(to: URL(fileURLWithPath: imagePath))
        defer { try? FileManager.default.removeItem(atPath: imagePath) }
        
        let result = await VisionAnalysisService.analyzeImage(atPath: imagePath)
        
        XCTAssertEqual(result.fileName, "test_image.png")
        XCTAssertGreaterThan(result.fileSizeBytes, 0)
        XCTAssertEqual(result.pixelWidth, 1)
        XCTAssertEqual(result.pixelHeight, 1)
        XCTAssertLessThanOrEqual(result.classifications.count, 8)
        XCTAssertNil(result.recognizedText)
        XCTAssertTrue(result.barcodePayloads.isEmpty)
        XCTAssertEqual(result.faceCount, 0)
    }
    
    private func createMinimalPNG() -> Data {
        let pngHeader: [UInt8] = [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, // IHDR chunk length
            0x49, 0x48, 0x44, 0x52, // IHDR
            0x00, 0x00, 0x00, 0x01, // Width: 1
            0x00, 0x00, 0x00, 0x01, // Height: 1
            0x08, 0x02, 0x00, 0x00, 0x00, // Bit depth, color type, etc.
            0x90, 0x77, 0x53, 0xDE, // CRC
            0x00, 0x00, 0x00, 0x0A, // IDAT chunk length
            0x49, 0x44, 0x41, 0x54, // IDAT
            0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // Compressed data
            0x0D, 0x0A, 0x2D, 0xB4, // CRC
            0x00, 0x00, 0x00, 0x00, // IEND chunk length
            0x49, 0x45, 0x4E, 0x44, // IEND
            0xAE, 0x42, 0x60, 0x82  // CRC
        ]
        return Data(pngHeader)
    }
}
