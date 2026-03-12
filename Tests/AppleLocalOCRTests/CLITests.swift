import XCTest
@testable import AppleLocalOCRKit

final class CLITests: XCTestCase {
    func test_missingInputArgumentReturnsUsageMessage() async {
        let result = await CLI.run(arguments: [], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }

    func test_nonImageFileReturnsReadableError() async {
        let result = await CLI.run(arguments: ["notes.txt"], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("image"))
    }

    func test_invalidEngineReturnsUsageError() async {
        let result = await CLI.run(arguments: ["--engine", "invalid", "image.png"], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("Invalid engine"))
    }

    func test_passesLanguageAndCorrectionFlagsToRecognizer() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let inputURL = tempDir.appendingPathComponent("test.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "hello")
        let result = await CLI.run(
            arguments: ["--engine", "liveText", "--lang", "zh-Hans,en-US", "--no-correction", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls[0].configuration.engine, .liveText)
        XCTAssertEqual(recorder.calls[0].configuration.recognitionLanguages, ["zh-Hans", "en-US"])
        XCTAssertEqual(recorder.calls[0].configuration.usesLanguageCorrection, false)
    }

    func test_defaultsToLiveTextEngineAndLanguages() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let inputURL = tempDir.appendingPathComponent("test.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "hello")
        let result = await CLI.run(
            arguments: [inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls[0].configuration.engine, .liveText)
        XCTAssertEqual(recorder.calls[0].configuration.recognitionLanguages, ["zh-Hans", "en-US"])
        XCTAssertTrue(result.stdout.contains("OCR settings -> engine: liveText"))
        XCTAssertTrue(result.stdout.contains("languages: zh-Hans,en-US"))
    }
}

private final class RecordingRecognizer: TextRecognizing {
    struct Call {
        let imageURL: URL
        let configuration: OCRConfiguration
    }

    private let textToReturn: String
    private(set) var calls: [Call] = []

    init(textToReturn: String) {
        self.textToReturn = textToReturn
    }

    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String {
        calls.append(Call(imageURL: imageURL, configuration: configuration))
        return textToReturn
    }
}
