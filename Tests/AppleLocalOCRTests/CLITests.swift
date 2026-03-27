import AppKit
import PDFKit
import XCTest
@testable import AppleLocalOCRKit

final class CLITests: XCTestCase {
    func test_versionFlag_printsToolVersion() async {
        let result = await CLI.run(arguments: ["--version"], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "\(CLI.toolVersion)\n")
        XCTAssertEqual(result.stderr, "")
    }

    func test_missingInputArgumentReturnsUsageMessage() async {
        let result = await CLI.run(arguments: [], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }

    func test_nonImageFileReturnsReadableError() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let notesURL = tempDir.appendingPathComponent("notes.txt")
        try? Data("notes".utf8).write(to: notesURL)

        let result = await CLI.run(arguments: [notesURL.path], currentDirectory: tempDir)

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("image"))
    }

    func test_invalidEngineReturnsUsageError() async {
        let result = await CLI.run(arguments: ["--engine", "invalid", "image.png"], currentDirectory: URL(fileURLWithPath: "/tmp"))

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertTrue(result.stderr.contains("Invalid engine"))
    }

    func test_errorFormatJSON_returnsStructuredUsageError() async throws {
        let result = await CLI.run(
            arguments: ["--error-format", "json", "--engine", "invalid", "image.png"],
            currentDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertEqual(result.exitCode, 64)
        XCTAssertEqual(result.stdout, "")

        let data = try XCTUnwrap(result.stderr.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? String, CLI.outputSchemaVersion)
        XCTAssertEqual(object["toolVersion"] as? String, CLI.toolVersion)
        XCTAssertEqual(object["kind"] as? String, "usage_error")
        XCTAssertEqual(object["exitCode"] as? Int, 64)
        XCTAssertTrue((object["message"] as? String)?.contains("Invalid engine") == true)
    }

    func test_errorFormatJSON_returnsStructuredInputError() async throws {
        let result = await CLI.run(
            arguments: ["--error-format", "json", "/tmp/does-not-exist.png"],
            currentDirectory: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertEqual(result.exitCode, 66)
        XCTAssertEqual(result.stdout, "")

        let data = try XCTUnwrap(result.stderr.data(using: .utf8))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? String, CLI.outputSchemaVersion)
        XCTAssertEqual(object["toolVersion"] as? String, CLI.toolVersion)
        XCTAssertEqual(object["kind"] as? String, "input_error")
        XCTAssertEqual(object["exitCode"] as? Int, 66)
        XCTAssertTrue((object["message"] as? String)?.contains("Input not found") == true)
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

    func test_directoryInput_skipsImagesWithExistingOutputTxt() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        let outputDir = tempDir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let skippedImage = inputDir.appendingPathComponent("a.png")
        let processImage = inputDir.appendingPathComponent("b.jpg")
        try Data([0x01]).write(to: skippedImage)
        try Data([0x02]).write(to: processImage)
        try "already done".write(to: outputDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let recorder = RecordingRecognizer(textToReturn: "fresh ocr")
        let result = await CLI.run(
            arguments: [inputDir.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls[0].imageURL.lastPathComponent, "b.jpg")
        XCTAssertTrue(result.stdout.contains("Skipped existing output"))
        XCTAssertTrue(result.stdout.contains("Summary -> total files: 2, wrote: 1, skipped: 1, failed: 0"))
        XCTAssertTrue(result.stdout.contains("elapsed:"))

        let skippedOutput = try String(contentsOf: outputDir.appendingPathComponent("a.txt"), encoding: .utf8)
        XCTAssertEqual(skippedOutput, "already done")

        let newOutput = try String(contentsOf: outputDir.appendingPathComponent("b.txt"), encoding: .utf8)
        XCTAssertEqual(newOutput, "fresh ocr")
    }

    func test_directoryInput_withoutSupportedImages_returnsReadableError() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: inputDir.appendingPathComponent("note.md"))

        let recorder = RecordingRecognizer(textToReturn: "unused")
        let result = await CLI.run(
            arguments: [inputDir.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 65)
        XCTAssertTrue(result.stderr.contains("No supported image or PDF files"))
        XCTAssertEqual(recorder.calls.count, 0)
    }

    func test_outputFlag_writesResultIntoProvidedDirectory() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("receipt.png")
        let customOutputDir = tempDir.appendingPathComponent("custom-output", isDirectory: true)
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "receipt text")
        let result = await CLI.run(
            arguments: ["--output", customOutputDir.path, inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertTrue(result.stdout.contains(customOutputDir.appendingPathComponent("receipt.txt").path))
        XCTAssertEqual(
            try String(contentsOf: customOutputDir.appendingPathComponent("receipt.txt"), encoding: .utf8),
            "receipt text"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("output/receipt.txt").path)
        )
    }

    func test_stdoutFlag_printsRecognizedTextWithoutWritingFile() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("stdout.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "hello stdout")
        let result = await CLI.run(
            arguments: ["--stdout", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(result.stdout, "hello stdout\n")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("output/stdout.txt").path)
        )
    }

    func test_recursivePreserveStructure_keepsNestedPathsUnderOutputDirectory() async throws {
        let tempDir = try makeTempDirectory()
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        let nestedDir = inputDir.appendingPathComponent("nested/deeper", isDirectory: true)
        let customOutputDir = tempDir.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)

        let nestedImage = nestedDir.appendingPathComponent("invoice.png")
        try Data([0x00]).write(to: nestedImage)

        let recorder = RecordingRecognizer(textToReturn: "nested text")
        let result = await CLI.run(
            arguments: [
                "--recursive",
                "--preserve-structure",
                "--output", customOutputDir.path,
                inputDir.path
            ],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)

        let expectedOutput = customOutputDir.appendingPathComponent("input/nested/deeper/invoice.txt")
        XCTAssertEqual(try String(contentsOf: expectedOutput, encoding: .utf8), "nested text")
    }

    func test_multipleInputs_processesStandaloneFilesAndDirectoriesTogether() async throws {
        let tempDir = try makeTempDirectory()
        let standaloneInput = tempDir.appendingPathComponent("standalone.png")
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: standaloneInput)
        try Data([0x01]).write(to: inputDir.appendingPathComponent("folder-image.jpg"))

        let recorder = RecordingRecognizer(textToReturn: "ocr text")
        let result = await CLI.run(
            arguments: [standaloneInput.path, inputDir.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertTrue(result.stdout.contains("Summary -> total files: 2"))
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/standalone.txt"), encoding: .utf8),
            "ocr text"
        )
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/folder-image.txt"), encoding: .utf8),
            "ocr text"
        )
    }

    func test_failOnExisting_returnsErrorWithoutRunningOCR() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("existing.png")
        let outputDir = tempDir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: inputURL)
        try "previous text".write(to: outputDir.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)

        let recorder = RecordingRecognizer(textToReturn: "new text")
        let result = await CLI.run(
            arguments: ["--fail-on-existing", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertEqual(recorder.calls.count, 0)
        XCTAssertTrue(result.stderr.contains("Output already exists"))
        XCTAssertEqual(
            try String(contentsOf: outputDir.appendingPathComponent("existing.txt"), encoding: .utf8),
            "previous text"
        )
    }

    func test_jsonFormat_writesStructuredOutput() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("metadata.png")
        let outputDir = tempDir.appendingPathComponent("json-out", isDirectory: true)
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "hello json")
        let result = await CLI.run(
            arguments: ["--format", "json", "--output", outputDir.path, inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)

        let outputURL = outputDir.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: outputURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? String, CLI.outputSchemaVersion)
        XCTAssertEqual(object["toolVersion"] as? String, CLI.toolVersion)
        XCTAssertEqual(object["text"] as? String, "hello json")
        XCTAssertEqual(object["engine"] as? String, "liveText")
        XCTAssertEqual(object["inputPath"] as? String, inputURL.path)
        XCTAssertEqual(object["format"] as? String, "json")
    }

    func test_pdfInput_combinedMode_writesSingleOutputWithJoinedPageText() async throws {
        let tempDir = try makeTempDirectory()
        let pdfURL = tempDir.appendingPathComponent("report.pdf")
        try makeTestPDF(
            pageTexts: ["Page 1 source", "Page 2 source"],
            at: pdfURL
        )

        let recorder = RecordingRecognizer(textSequence: ["first page", "second page"])
        let result = await CLI.run(
            arguments: ["--page-separator", "\n--PAGE--\n", pdfURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/report.txt"), encoding: .utf8),
            "first page\n--PAGE--\nsecond page"
        )
    }

    func test_pdfInput_perPageMode_writesOneOutputPerPage() async throws {
        let tempDir = try makeTempDirectory()
        let pdfURL = tempDir.appendingPathComponent("pages.pdf")
        try makeTestPDF(
            pageTexts: ["Page 1 source", "Page 2 source"],
            at: pdfURL
        )

        let recorder = RecordingRecognizer(textSequence: ["page one", "page two"])
        let result = await CLI.run(
            arguments: ["--pdf-mode", "per-page", pdfURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 2)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/pages-page-1.txt"), encoding: .utf8),
            "page one"
        )
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/pages-page-2.txt"), encoding: .utf8),
            "page two"
        )
    }

    func test_pdfInput_pageRange_limitsProcessedPages() async throws {
        let tempDir = try makeTempDirectory()
        let pdfURL = tempDir.appendingPathComponent("subset.pdf")
        try makeTestPDF(
            pageTexts: ["One", "Two", "Three"],
            at: pdfURL
        )

        let recorder = RecordingRecognizer(textSequence: ["page two"])
        let result = await CLI.run(
            arguments: ["--page-range", "2", pdfURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/subset.txt"), encoding: .utf8),
            "page two"
        )
    }

    func test_pdfInput_jsonFormat_includesPageMetadata() async throws {
        let tempDir = try makeTempDirectory()
        let pdfURL = tempDir.appendingPathComponent("metadata.pdf")
        let outputDir = tempDir.appendingPathComponent("json-out", isDirectory: true)
        try makeTestPDF(
            pageTexts: ["One", "Two"],
            at: pdfURL
        )

        let recorder = RecordingRecognizer(textSequence: ["json one", "json two"])
        let result = await CLI.run(
            arguments: ["--format", "json", "--output", outputDir.path, pdfURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 2)

        let outputURL = outputDir.appendingPathComponent("metadata.json")
        let data = try Data(contentsOf: outputURL)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])

        XCTAssertEqual(object["schemaVersion"] as? String, CLI.outputSchemaVersion)
        XCTAssertEqual(object["toolVersion"] as? String, CLI.toolVersion)
        XCTAssertEqual(object["text"] as? String, "json one\n\njson two")
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0]["pageNumber"] as? Int, 1)
        XCTAssertEqual(pages[0]["text"] as? String, "json one")
        XCTAssertEqual(pages[1]["pageNumber"] as? Int, 2)
        XCTAssertEqual(pages[1]["text"] as? String, "json two")
    }

    func test_inspectSubcommand_listsResolvedJobsWithoutRunningOCR() async throws {
        let tempDir = try makeTempDirectory()
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        let imageURL = inputDir.appendingPathComponent("photo.png")
        let pdfURL = inputDir.appendingPathComponent("paper.pdf")
        try Data([0x00]).write(to: imageURL)
        try makeTestPDF(pageTexts: ["One", "Two"], at: pdfURL)

        let recorder = RecordingRecognizer(textToReturn: "unused")
        let result = await CLI.run(
            arguments: ["inspect", "--pdf-mode", "per-page", inputDir.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 0)
        XCTAssertTrue(result.stdout.contains("Inspect -> total jobs: 3"))
        XCTAssertTrue(result.stdout.contains("photo.png"))
        XCTAssertTrue(result.stdout.contains("paper.pdf"))
        XCTAssertTrue(result.stdout.contains("page 1"))
        XCTAssertTrue(result.stdout.contains("page 2"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("output").path))
    }

    func test_jobsFlag_limitsConcurrentOCRWork() async throws {
        let tempDir = try makeTempDirectory()
        let inputDir = tempDir.appendingPathComponent("input", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try Data([0x00]).write(to: inputDir.appendingPathComponent("a.png"))
        try Data([0x00]).write(to: inputDir.appendingPathComponent("b.png"))
        try Data([0x00]).write(to: inputDir.appendingPathComponent("c.png"))

        let recorder = ConcurrencyRecordingRecognizer()
        let result = await CLI.run(
            arguments: ["--jobs", "2", inputDir.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let maxInFlight = await recorder.maxInFlight
        XCTAssertEqual(maxInFlight, 2)
    }

    func test_normalizeWhitespaceFlag_collapsesWhitespaceRuns() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("messy.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "alpha\t\tbeta   gamma")
        let result = await CLI.run(
            arguments: ["--normalize-whitespace", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/messy.txt"), encoding: .utf8),
            "alpha beta gamma"
        )
    }

    func test_trimEmptyLinesFlag_removesBlankLines() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("trim.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "alpha\n\n\nbeta\n\n")
        let result = await CLI.run(
            arguments: ["--trim-empty-lines", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/trim.txt"), encoding: .utf8),
            "alpha\nbeta"
        )
    }

    func test_findAndReplaceFlags_applyReplacementRule() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("replace.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "scan rn value")
        let result = await CLI.run(
            arguments: ["--find", "rn", "--replace", "m", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/replace.txt"), encoding: .utf8),
            "scan m value"
        )
    }

    func test_dictionaryFlag_appliesReplacementRulesFromFile() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("dictionary.png")
        let dictionaryURL = tempDir.appendingPathComponent("rules.txt")
        try Data([0x00]).write(to: inputURL)
        try "teh\tthe\nreciept\treceipt\n".write(to: dictionaryURL, atomically: true, encoding: .utf8)

        let recorder = RecordingRecognizer(textToReturn: "teh reciept")
        let result = await CLI.run(
            arguments: ["--dictionary", dictionaryURL.path, inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/dictionary.txt"), encoding: .utf8),
            "the receipt"
        )
    }

    func test_smartQuotesOff_normalizesCurlyQuotesToAscii() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("quotes-off.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "“Hello”, it’s me")
        let result = await CLI.run(
            arguments: ["--smart-quotes", "off", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/quotes-off.txt"), encoding: .utf8),
            "\"Hello\", it's me"
        )
    }

    func test_smartQuotesOn_convertsStraightQuotesToCurly() async throws {
        let tempDir = try makeTempDirectory()
        let inputURL = tempDir.appendingPathComponent("quotes-on.png")
        try Data([0x00]).write(to: inputURL)

        let recorder = RecordingRecognizer(textToReturn: "\"Hello\", it's me")
        let result = await CLI.run(
            arguments: ["--smart-quotes", "on", inputURL.path],
            currentDirectory: tempDir,
            recognizerFactory: { _ in recorder }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("output/quotes-on.txt"), encoding: .utf8),
            "“Hello”, it’s me"
        )
    }

    func test_languagesSubcommand_listsLanguagesForSelectedEngine() async throws {
        let tempDir = try makeTempDirectory()

        let result = await CLI.run(
            arguments: ["languages", "--engine", "vision"],
            currentDirectory: tempDir,
            recognizerFactory: { _ in RecordingRecognizer(textToReturn: "unused") },
            languageProvider: { engine in
                XCTAssertEqual(engine, .vision)
                return ["en-US", "zh-Hans"]
            }
        )

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertTrue(result.stdout.contains("Supported languages for vision"))
        XCTAssertTrue(result.stdout.contains("en-US"))
        XCTAssertTrue(result.stdout.contains("zh-Hans"))
    }

    func test_watchFlag_processesNewFilesUntilCancelled() async throws {
        let tempDir = try makeTempDirectory()
        let watchDir = tempDir.appendingPathComponent("watch", isDirectory: true)
        let outputDir = tempDir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let recorder = RecordingRecognizer(textToReturn: "watched text")
        let task = Task {
            await CLI.run(
                arguments: ["--watch", watchDir.path, "--output", outputDir.path],
                currentDirectory: tempDir,
                recognizerFactory: { _ in recorder },
                watchPollIntervalNanoseconds: 50_000_000
            )
        }

        try await Task.sleep(nanoseconds: 120_000_000)
        let inputURL = watchDir.appendingPathComponent("incoming.png")
        try Data([0x00]).write(to: inputURL)

        let outputURL = outputDir.appendingPathComponent("incoming.txt")
        try await waitForFile(at: outputURL)

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "watched text")
        XCTAssertTrue(result.stdout.contains("Watching directory"))
    }

    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func waitForFile(at url: URL, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws {
        let deadline = Date().timeIntervalSinceReferenceDate + Double(timeoutNanoseconds) / 1_000_000_000
        while Date().timeIntervalSinceReferenceDate < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        XCTFail("Timed out waiting for file at \(url.path)")
    }

    private func makeTestPDF(pageTexts: [String], at url: URL) throws {
        let document = PDFDocument()
        for (index, text) in pageTexts.enumerated() {
            let image = try makeTestImage(text: text)
            let page = try XCTUnwrap(PDFPage(image: image))
            document.insert(page, at: index)
        }

        let data = try XCTUnwrap(document.dataRepresentation())
        try data.write(to: url)
    }

    private func makeTestImage(text: String) throws -> NSImage {
        let size = NSSize(width: 1200, height: 400)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 40, y: 140))
        image.unlockFocus()
        return image
    }
}

private final class RecordingRecognizer: TextRecognizing {
    struct Call {
        let imageURL: URL
        let configuration: OCRConfiguration
    }

    private let textToReturn: String?
    private let textSequence: [String]
    private(set) var calls: [Call] = []

    init(textToReturn: String) {
        self.textToReturn = textToReturn
        self.textSequence = []
    }

    init(textSequence: [String]) {
        self.textToReturn = nil
        self.textSequence = textSequence
    }

    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String {
        calls.append(Call(imageURL: imageURL, configuration: configuration))
        if let textToReturn {
            return textToReturn
        }

        let index = calls.count - 1
        if index < textSequence.count {
            return textSequence[index]
        }

        return ""
    }
}

private actor ConcurrencyRecordingRecognizer: TextRecognizing {
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0

    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        try await Task.sleep(nanoseconds: 150_000_000)
        inFlight -= 1
        return imageURL.deletingPathExtension().lastPathComponent
    }
}
