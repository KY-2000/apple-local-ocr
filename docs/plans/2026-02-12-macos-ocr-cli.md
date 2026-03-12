# macOS OCR CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a local macOS command-line tool that takes an image path, extracts text using Apple Vision OCR, and writes the recognized text to `output/<image-name>.txt`.

**Architecture:** Use a Swift Package executable with a small layered design: `CLI` (argument parsing), `OCRService` (Vision text recognition), and `OutputWriter` (file persistence). Keep behavior deterministic and testable by isolating pure logic (path handling/output naming) from framework calls. Add one integration test with a fixture image to confirm end-to-end OCR on macOS.

**Tech Stack:** Swift 5.10+, Apple Vision framework, XCTest, Swift Package Manager

---

### Task 1: Scaffold the Swift Package and project layout

**Files:**
- Create: `Package.swift`
- Create: `Sources/apple-local-ocr/main.swift`
- Create: `Sources/apple-local-ocr/OCRService.swift`
- Create: `Sources/apple-local-ocr/OutputWriter.swift`
- Create: `Tests/apple-local-ocrTests/CLITests.swift`
- Create: `Tests/apple-local-ocrTests/OutputWriterTests.swift`
- Create: `Tests/apple-local-ocrTests/OCRIntegrationTests.swift`
- Create: `Tests/Fixtures/sample-hello.png`
- Create: `.gitignore`

**Step 1: Write the failing test**

```swift
func test_outputPathDefaultsToOutputFolderAndTxtExtension() throws {
    let input = URL(fileURLWithPath: "/tmp/receipt.jpg")
    let output = try OutputWriter.defaultOutputURL(forInput: input)
    XCTAssertEqual(output.path, "/tmp/output/receipt.txt")
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter OutputWriterTests/test_outputPathDefaultsToOutputFolderAndTxtExtension -v`  
Expected: FAIL with missing `OutputWriter` symbol

**Step 3: Write minimal implementation**

```swift
enum OutputWriter {
    static func defaultOutputURL(forInput input: URL) throws -> URL {
        let folder = input.deletingLastPathComponent().appendingPathComponent("output", isDirectory: true)
        return folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent + ".txt")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter OutputWriterTests/test_outputPathDefaultsToOutputFolderAndTxtExtension -v`  
Expected: PASS

**Step 5: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "chore: scaffold swift OCR CLI package"
```

### Task 2: Implement CLI argument handling with clear errors

**Files:**
- Modify: `Sources/apple-local-ocr/main.swift`
- Modify: `Tests/apple-local-ocrTests/CLITests.swift`

**Step 1: Write the failing test**

```swift
func test_missingInputArgumentReturnsUsageMessage() {
    let result = CLI.run(arguments: [])
    XCTAssertEqual(result.exitCode, 64)
    XCTAssertTrue(result.stderr.contains("Usage:"))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CLITests/test_missingInputArgumentReturnsUsageMessage -v`  
Expected: FAIL with missing `CLI.run`

**Step 3: Write minimal implementation**

```swift
enum CLI {
    static func run(arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        guard let rawPath = arguments.first else {
            return (64, "", "Usage: apple-local-ocr <image-path>\n")
        }
        return (0, rawPath, "")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter CLITests/test_missingInputArgumentReturnsUsageMessage -v`  
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/apple-local-ocr/main.swift Tests/apple-local-ocrTests/CLITests.swift
git commit -m "feat: add basic CLI argument validation"
```

### Task 3: Implement OCRService with Apple Vision and wire end-to-end flow

**Files:**
- Modify: `Sources/apple-local-ocr/OCRService.swift`
- Modify: `Sources/apple-local-ocr/main.swift`
- Modify: `Sources/apple-local-ocr/OutputWriter.swift`
- Modify: `Tests/apple-local-ocrTests/OCRIntegrationTests.swift`

**Step 1: Write the failing test**

```swift
func test_ocrReadsFixtureAndWritesTxtIntoOutputFolder() throws {
    let input = fixtureURL("sample-hello.png")
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let exitCode = try runCLI(inputPath: input.path, workingDirectory: tempDir.path)
    XCTAssertEqual(exitCode, 0)
    let output = tempDir.appendingPathComponent("output/sample-hello.txt")
    let text = try String(contentsOf: output, encoding: .utf8)
    XCTAssertTrue(text.localizedCaseInsensitiveContains("hello"))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter OCRIntegrationTests/test_ocrReadsFixtureAndWritesTxtIntoOutputFolder -v`  
Expected: FAIL because OCR logic is not implemented

**Step 3: Write minimal implementation**

```swift
import Vision
import AppKit

struct OCRService {
    func recognizeText(from imageURL: URL) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let handler = try VNImageRequestHandler(url: imageURL)
        try handler.perform([request])
        let lines = (request.results as? [VNRecognizedTextObservation])?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        return lines.joined(separator: "\n")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `swift test --filter OCRIntegrationTests/test_ocrReadsFixtureAndWritesTxtIntoOutputFolder -v`  
Expected: PASS on macOS

**Step 5: Commit**

```bash
git add Sources/apple-local-ocr/OCRService.swift Sources/apple-local-ocr/main.swift Sources/apple-local-ocr/OutputWriter.swift Tests/apple-local-ocrTests/OCRIntegrationTests.swift
git commit -m "feat: integrate Apple Vision OCR and output file writing"
```

### Task 4: Add usability polish, validation, and README

**Files:**
- Modify: `Sources/apple-local-ocr/main.swift`
- Create: `README.md`
- Modify: `Tests/apple-local-ocrTests/CLITests.swift`

**Step 1: Write the failing test**

```swift
func test_nonImageFileReturnsReadableError() {
    let result = CLI.run(arguments: ["./Tests/Fixtures/not-image.txt"])
    XCTAssertEqual(result.exitCode, 65)
    XCTAssertTrue(result.stderr.contains("must be an image"))
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter CLITests/test_nonImageFileReturnsReadableError -v`  
Expected: FAIL because image validation is missing

**Step 3: Write minimal implementation**

```swift
let supported = ["png", "jpg", "jpeg", "heic", "tiff", "bmp"]
guard supported.contains(inputURL.pathExtension.lowercased()) else {
    return (65, "", "Input must be an image file.\n")
}
```

**Step 4: Run test suite to verify it passes**

Run: `swift test -v`  
Expected: PASS (all CLI, output, and integration tests)

**Step 5: Commit**

```bash
git add Sources/apple-local-ocr/main.swift Tests/apple-local-ocrTests/CLITests.swift README.md
git commit -m "docs: add usage guide and improve error handling"
```

### Task 5: Manual smoke verification for real user image

**Files:**
- Use: `README.md`
- Use: `output/` (generated)

**Step 1: Build release binary**

Run: `swift build -c release`  
Expected: build succeeds

**Step 2: Run OCR on a real image**

Run: `.build/release/apple-local-ocr ./path/to/your-image.png`  
Expected: exit code `0`, file appears at `./output/your-image.txt`

**Step 3: Verify output content**

Run: `cat ./output/your-image.txt`  
Expected: text content exists and matches image text reasonably well

**Step 4: Commit**

```bash
git add output/ README.md
git commit -m "test: manual smoke check for OCR output flow"
```

