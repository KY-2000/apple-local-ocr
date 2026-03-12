import Foundation

public struct CLIResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum CLI {
    public static func run(
        arguments: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) async -> CLIResult {
        await run(arguments: arguments, currentDirectory: currentDirectory, recognizerFactory: defaultRecognizer)
    }

    static func run(
        arguments: [String],
        currentDirectory: URL,
        recognizerFactory: (OCREngine) -> any TextRecognizing
    ) async -> CLIResult {
        if arguments.contains("--help") || arguments.contains("-h") {
            return CLIResult(exitCode: 0, stdout: usageText(), stderr: "")
        }

        let parsed: ParsedArguments
        do {
            parsed = try parse(arguments: arguments)
        } catch let error as UsageError {
            return CLIResult(exitCode: 64, stdout: "", stderr: "\(error.message)\n\(usageText())")
        } catch {
            return CLIResult(exitCode: 64, stdout: "", stderr: "Invalid arguments.\n\(usageText())")
        }

        let inputURL = makeAbsoluteURL(path: parsed.inputPath, currentDirectory: currentDirectory)
        let ext = inputURL.pathExtension.lowercased()
        let supportedImageExtensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif"])
        let settingsLog = "OCR settings -> engine: \(parsed.configuration.engine.rawValue), languages: \(formatLanguages(parsed.configuration.recognitionLanguages))\n"

        guard supportedImageExtensions.contains(ext) else {
            return CLIResult(exitCode: 65, stdout: "", stderr: "Input must be an image file.\n")
        }

        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            return CLIResult(exitCode: 66, stdout: "", stderr: "Input image not found at path: \(inputURL.path)\n")
        }

        do {
            let recognizer = recognizerFactory(parsed.configuration.engine)
            let recognizedText = try await recognizer.recognizeText(from: inputURL, configuration: parsed.configuration)
            let outputURL = OutputWriter.defaultOutputURL(
                forInput: inputURL,
                workingDirectory: currentDirectory
            )
            try OutputWriter.write(text: recognizedText, to: outputURL)
            return CLIResult(exitCode: 0, stdout: settingsLog + "Wrote OCR text to: \(outputURL.path)\n", stderr: "")
        } catch {
            return CLIResult(exitCode: 1, stdout: settingsLog, stderr: "OCR failed: \(error.localizedDescription)\n")
        }
    }

    private static func defaultRecognizer(for engine: OCREngine) -> any TextRecognizing {
        switch engine {
        case .vision:
            return OCRService()
        case .liveText:
            return LiveTextOCRService()
        }
    }

    private static func usageText() -> String {
        """
        Usage: apple-local-ocr [--engine vision|liveText] [--lang code1,code2] [--no-correction] <image-path>
          --engine          OCR backend (default: liveText)
          --lang            Comma-separated language codes (example: zh-Hans,en-US)
          --no-correction   Disable language correction (Vision engine only)
        """
        + "\n"
    }

    private static func parse(arguments: [String]) throws -> ParsedArguments {
        guard !arguments.isEmpty else {
            throw UsageError(message: "Missing image path.")
        }

        var engine: OCREngine = .liveText
        var languages: [String] = ["zh-Hans", "en-US"]
        var usesLanguageCorrection = true
        var inputPath: String?

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]

            if arg == "--no-correction" {
                usesLanguageCorrection = false
                index += 1
                continue
            }

            if arg.hasPrefix("--engine=") {
                let value = String(arg.dropFirst("--engine=".count))
                engine = try parseEngine(value)
                index += 1
                continue
            }

            if arg == "--engine" {
                let value = try valueAfterFlag(arguments: arguments, index: index, flag: "--engine")
                engine = try parseEngine(value)
                index += 2
                continue
            }

            if arg.hasPrefix("--lang=") {
                let raw = String(arg.dropFirst("--lang=".count))
                languages = parseLanguages(raw)
                index += 1
                continue
            }

            if arg == "--lang" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--lang")
                languages = parseLanguages(raw)
                index += 2
                continue
            }

            if arg.hasPrefix("-") {
                throw UsageError(message: "Unknown option: \(arg)")
            }

            if inputPath != nil {
                throw UsageError(message: "Only one image path is allowed.")
            }
            inputPath = arg
            index += 1
        }

        guard let inputPath else {
            throw UsageError(message: "Missing image path.")
        }

        return ParsedArguments(
            inputPath: inputPath,
            configuration: OCRConfiguration(
                engine: engine,
                recognitionLanguages: languages,
                usesLanguageCorrection: usesLanguageCorrection
            )
        )
    }

    private static func parseEngine(_ rawValue: String) throws -> OCREngine {
        guard let engine = OCREngine(rawValue: rawValue) else {
            throw UsageError(message: "Invalid engine '\(rawValue)'. Use 'vision' or 'liveText'.")
        }
        return engine
    }

    private static func parseLanguages(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func valueAfterFlag(arguments: [String], index: Int, flag: String) throws -> String {
        let nextIndex = index + 1
        guard nextIndex < arguments.count else {
            throw UsageError(message: "Missing value for \(flag).")
        }
        return arguments[nextIndex]
    }

    private static func formatLanguages(_ languages: [String]) -> String {
        if languages.isEmpty {
            return "auto"
        }
        return languages.joined(separator: ",")
    }

    private static func makeAbsoluteURL(path: String, currentDirectory: URL) -> URL {
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return currentDirectory.appendingPathComponent(path)
    }
}

private struct ParsedArguments {
    let inputPath: String
    let configuration: OCRConfiguration
}

private struct UsageError: Error {
    let message: String
}
