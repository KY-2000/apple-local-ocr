import XCTest
@testable import AppleLocalOCRKit

final class OutputWriterTests: XCTestCase {
    func test_outputPathDefaultsToOutputFolderAndTxtExtension() {
        let input = URL(fileURLWithPath: "/tmp/receipt.jpg")
        let workingDirectory = URL(fileURLWithPath: "/tmp")

        let output = OutputWriter.defaultOutputURL(forInput: input, workingDirectory: workingDirectory)

        XCTAssertEqual(output.path, "/tmp/output/receipt.txt")
    }

    func test_outputPathUsesProvidedDirectoryAndFormat() {
        let input = URL(fileURLWithPath: "/tmp/source/receipt.jpg")
        let outputDirectory = URL(fileURLWithPath: "/tmp/custom-output", isDirectory: true)

        let output = OutputWriter.outputURL(
            forInput: input,
            outputDirectory: outputDirectory,
            relativeOutputPath: nil,
            format: .json
        )

        XCTAssertEqual(output.path, "/tmp/custom-output/receipt.json")
    }

    func test_outputPathUsesRelativeOutputPathWhenProvided() {
        let input = URL(fileURLWithPath: "/tmp/source/receipt.jpg")
        let outputDirectory = URL(fileURLWithPath: "/tmp/custom-output", isDirectory: true)

        let output = OutputWriter.outputURL(
            forInput: input,
            outputDirectory: outputDirectory,
            relativeOutputPath: "input/nested/receipt.md",
            format: .md
        )

        XCTAssertEqual(output.path, "/tmp/custom-output/input/nested/receipt.md")
    }
}
