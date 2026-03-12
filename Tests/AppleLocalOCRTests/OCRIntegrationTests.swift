#if os(macOS)
import AppKit
import XCTest
@testable import AppleLocalOCRKit

final class OCRIntegrationTests: XCTestCase {
    func test_ocrReadsGeneratedImageAndWritesTxtIntoOutputFolder() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let inputImageURL = tempDir.appendingPathComponent("sample-hello.png")
        try makeTestImage(text: "HELLO OCR", at: inputImageURL)

        let result = await CLI.run(arguments: [inputImageURL.path], currentDirectory: tempDir)
        XCTAssertEqual(result.exitCode, 0, result.stderr)

        let output = tempDir.appendingPathComponent("output/sample-hello.txt")
        let text = try String(contentsOf: output, encoding: .utf8)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("hello"), "OCR output: \(text)")
    }

    private func makeTestImage(text: String, at url: URL) throws {
        let size = NSSize(width: 1000, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 100, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        let attrText = NSAttributedString(string: text, attributes: attributes)
        attrText.draw(at: NSPoint(x: 40, y: 100))
        image.unlockFocus()

        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            XCTFail("Unable to generate png data")
            return
        }

        try png.write(to: url)
    }
}
#endif
