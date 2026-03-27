#if os(macOS)
import XCTest
@testable import AppleLocalOCRKit

final class OCRIntegrationTests: XCTestCase {
    func test_ocrReadsSampleEnglishImageAndWritesTxtIntoOutputFolder() async throws {
        let tempDir = try makeTempDirectory()
        let inputImageURL = sampleDirectory().appendingPathComponent("sample-ocr-en.png")

        let result = await CLI.run(arguments: [inputImageURL.path], currentDirectory: tempDir)
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        let output = tempDir.appendingPathComponent("output/sample-ocr-en.txt")
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("invoice"), "OCR output: \(text)")
        XCTAssertTrue(text.localizedCaseInsensitiveContains("openclaw"), "OCR output: \(text)")
    }

    func test_ocrReadsSampleMultilingualPDFAndWritesCombinedTxtIntoOutputFolder() async throws {
        let tempDir = try makeTempDirectory()
        let inputPDFURL = sampleDirectory().appendingPathComponent("sample-ocr.pdf")

        let result = await CLI.run(
            arguments: ["--lang", "zh-Hans,en-US", inputPDFURL.path],
            currentDirectory: tempDir
        )
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        let output = tempDir.appendingPathComponent("output/sample-ocr.txt")
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("invoice"), "OCR output: \(text)")
        XCTAssertTrue(text.contains("订单编号") || text.contains("订单"), "OCR output: \(text)")
    }

    private func repoRoot(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sampleDirectory(file: StaticString = #filePath) -> URL {
        repoRoot(file: file).appendingPathComponent("sample", isDirectory: true)
    }

    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }
}
#endif
