import XCTest
@testable import AppleLocalOCRKit

final class OutputWriterTests: XCTestCase {
    func test_outputPathDefaultsToOutputFolderAndTxtExtension() {
        let input = URL(fileURLWithPath: "/tmp/receipt.jpg")
        let workingDirectory = URL(fileURLWithPath: "/tmp")

        let output = OutputWriter.defaultOutputURL(forInput: input, workingDirectory: workingDirectory)

        XCTAssertEqual(output.path, "/tmp/output/receipt.txt")
    }
}
