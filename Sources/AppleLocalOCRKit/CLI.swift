import Foundation

typealias LanguageProvider = (OCREngine) throws -> [String]
typealias SleepFunction = @Sendable (UInt64) async throws -> Void

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
    public static let toolVersion = "0.4.0"
    public static let outputSchemaVersion = "1.0"

    private static let supportedImageExtensions = Set(["png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif"])
    private static let supportedPDFExtensions = Set(["pdf"])

    public static func run(
        arguments: [String],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) async -> CLIResult {
        await run(arguments: arguments, currentDirectory: currentDirectory, recognizerFactory: defaultRecognizer)
    }

    static func run(
        arguments: [String],
        currentDirectory: URL,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing,
        languageProvider: @escaping LanguageProvider = OCRLanguageSupport.supportedLanguages,
        watchPollIntervalNanoseconds: UInt64 = 500_000_000,
        sleep: @escaping SleepFunction = defaultSleep
    ) async -> CLIResult {
        let requestedErrorFormat: ErrorFormat
        do {
            requestedErrorFormat = try parseRequestedErrorFormat(arguments: arguments)
        } catch let error as UsageError {
            return errorResult(
                exitCode: 64,
                kind: .usageError,
                message: error.message,
                format: .text,
                includeUsage: true
            )
        } catch {
            return errorResult(
                exitCode: 64,
                kind: .usageError,
                message: "Invalid arguments.",
                format: .text,
                includeUsage: true
            )
        }

        if arguments.contains("--version") {
            return CLIResult(exitCode: 0, stdout: "\(toolVersion)\n", stderr: "")
        }

        if arguments.contains("--help") || arguments.contains("-h") {
            return CLIResult(exitCode: 0, stdout: usageText(), stderr: "")
        }

        let parsed: ParsedArguments
        do {
            parsed = try parse(arguments: arguments)
        } catch let error as UsageError {
            return errorResult(
                exitCode: 64,
                kind: .usageError,
                message: error.message,
                format: requestedErrorFormat,
                includeUsage: requestedErrorFormat == .text
            )
        } catch {
            return errorResult(
                exitCode: 64,
                kind: .usageError,
                message: "Invalid arguments.",
                format: requestedErrorFormat,
                includeUsage: requestedErrorFormat == .text
            )
        }

        let outputDirectory = parsed.outputDirectoryPath.map {
            makeAbsoluteURL(path: $0, currentDirectory: currentDirectory)
        } ?? OutputWriter.defaultOutputDirectory(workingDirectory: currentDirectory)

        let postProcessor: PostProcessor
        do {
            postProcessor = try makePostProcessor(parsed: parsed, currentDirectory: currentDirectory)
        } catch let error as PostProcessingError {
            return errorResult(
                exitCode: error.exitCode,
                kind: .configurationError,
                message: error.message,
                format: parsed.errorFormat
            )
        } catch {
            return errorResult(
                exitCode: 70,
                kind: .internalError,
                message: "Failed to configure post-processing.",
                format: parsed.errorFormat
            )
        }

        switch parsed.commandMode {
        case .languages:
            do {
                let stdout = try makeLanguagesOutput(parsed: parsed, languageProvider: languageProvider)
                return CLIResult(exitCode: 0, stdout: stdout, stderr: "")
            } catch {
                return errorResult(
                    exitCode: 70,
                    kind: .internalError,
                    message: "Failed to list supported languages: \(error.localizedDescription)",
                    format: parsed.errorFormat
                )
            }
        case .run, .inspect:
            break
        }

        if let watchDirectoryPath = parsed.watchDirectoryPath {
            return await runWatch(
                watchDirectoryPath: watchDirectoryPath,
                parsed: parsed,
                currentDirectory: currentDirectory,
                outputDirectory: outputDirectory,
                postProcessor: postProcessor,
                recognizerFactory: recognizerFactory,
                watchPollIntervalNanoseconds: watchPollIntervalNanoseconds,
                sleep: sleep
            )
        }

        let resolution = resolveInputs(parsed: parsed, currentDirectory: currentDirectory)
        defer {
            cleanupTemporaryDirectories(resolution.temporaryDirectories)
        }

        return await runSinglePass(
            parsed: parsed,
            resolution: resolution,
            outputDirectory: outputDirectory,
            postProcessor: postProcessor,
            recognizerFactory: recognizerFactory
        )
    }

    private static func executeJobs(
        _ plannedJobs: [PlannedJob],
        parsed: ParsedArguments,
        postProcessor: PostProcessor,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing
    ) async -> [ExecutionResult] {
        guard !plannedJobs.isEmpty else {
            return []
        }

        if parsed.maxJobs <= 1 {
            var results: [ExecutionResult] = []
            for plannedJob in plannedJobs {
                let outcome = await executeJob(
                    plannedJob,
                    parsed: parsed,
                    postProcessor: postProcessor,
                    recognizerFactory: recognizerFactory
                )
                results.append(ExecutionResult(index: plannedJob.index, outcome: outcome))
            }
            return results
        }

        var results: [ExecutionResult] = []
        await withTaskGroup(of: ExecutionResult.self) { group in
            var nextIndex = 0
            let initialCount = min(parsed.maxJobs, plannedJobs.count)
            for _ in 0..<initialCount {
                let plannedJob = plannedJobs[nextIndex]
                nextIndex += 1
                group.addTask {
                    let outcome = await executeJob(
                        plannedJob,
                        parsed: parsed,
                        postProcessor: postProcessor,
                        recognizerFactory: recognizerFactory
                    )
                    return ExecutionResult(index: plannedJob.index, outcome: outcome)
                }
            }

            while let result = await group.next() {
                results.append(result)
                if nextIndex < plannedJobs.count {
                    let plannedJob = plannedJobs[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        let outcome = await executeJob(
                            plannedJob,
                            parsed: parsed,
                            postProcessor: postProcessor,
                            recognizerFactory: recognizerFactory
                        )
                        return ExecutionResult(index: plannedJob.index, outcome: outcome)
                    }
                }
            }
        }
        return results
    }

    private static func executeJob(
        _ plannedJob: PlannedJob,
        parsed: ParsedArguments,
        postProcessor: PostProcessor,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing
    ) async -> ExecutionOutcome {
        do {
            let recognizer = recognizerFactory(parsed.configuration.engine)
            var unitResults: [RecognizedUnitResult] = []
            for unit in plannedJob.job.units {
                let recognizedText = try await recognizer.recognizeText(
                    from: unit.imageURL,
                    configuration: parsed.configuration
                )
                let cleanedText = postProcessor.apply(to: recognizedText)
                unitResults.append(RecognizedUnitResult(pageNumber: unit.pageNumber, text: cleanedText))
            }

            let processedOutput = makeProcessedOutput(
                job: plannedJob.job,
                unitResults: unitResults,
                outputPath: plannedJob.outputURL?.path
            )

            if let outputURL = plannedJob.outputURL {
                let rendered = try renderOutput(
                    for: processedOutput,
                    format: parsed.outputFormat,
                    configuration: parsed.configuration
                )
                try OutputWriter.write(text: rendered, to: outputURL)
            }

            return .success(processedOutput, plannedJob.outputURL)
        } catch {
            return .failure("OCR failed for input: \(plannedJob.job.inputPath)\nReason: \(error.localizedDescription)")
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

    private static let defaultSleep: SleepFunction = { nanoseconds in
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func runSinglePass(
        parsed: ParsedArguments,
        resolution: InputResolution,
        outputDirectory: URL,
        postProcessor: PostProcessor,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing
    ) async -> CLIResult {
        if resolution.jobs.isEmpty {
            let failure = resolution.failures.first
            return errorResult(
                exitCode: failure?.exitCode ?? 65,
                kind: .inputError,
                message: failure?.message ?? "No supported OCR inputs found.",
                format: parsed.errorFormat,
                errors: resolution.failures.map(\.message)
            )
        }

        if parsed.commandMode == .inspect {
            let stdout = makeInspectOutput(
                jobs: resolution.jobs,
                outputDirectory: outputDirectory,
                outputMode: parsed.outputMode,
                format: parsed.outputFormat
            )
            let stderr = resolution.failures.isEmpty ? "" : renderErrorText(
                exitCode: 1,
                kind: .inputError,
                message: resolution.failures.count == 1
                    ? resolution.failures[0].message
                    : "\(resolution.failures.count) input error(s) occurred during inspect.",
                format: parsed.errorFormat,
                errors: resolution.failures.map(\.message)
            )
            let exitCode: Int32 = resolution.failures.isEmpty ? 0 : 1
            return CLIResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
        }

        let settingsLog = parsed.logLevel == .quiet ? "" : settingsLog(for: parsed.configuration)
        let startTime = Date()
        let batchResult = await processResolution(
            resolution: resolution,
            parsed: parsed,
            outputDirectory: outputDirectory,
            postProcessor: postProcessor,
            recognizerFactory: recognizerFactory
        )

        let summary = summaryLog(
            totalCount: resolution.jobs.count,
            wroteCount: batchResult.wroteCount,
            skippedCount: batchResult.skippedCount,
            failedCount: batchResult.failedCount,
            startTime: startTime
        )

        var errorLogs = batchResult.errorLogs
        let stdout: String
        do {
            stdout = try makeStdout(
                parsed: parsed,
                settingsLog: settingsLog,
                infoLogs: batchResult.infoLogs,
                summary: summary,
                includeSummary: resolution.jobs.count > 1 || batchResult.skippedCount > 0 || batchResult.failedCount > 0,
                processedOutputs: batchResult.processedOutputs
            )
        } catch {
            errorLogs.append("Failed to render output: \(error.localizedDescription)")
            return errorResult(
                exitCode: 70,
                kind: .internalError,
                message: "Failed to render output.",
                format: parsed.errorFormat,
                errors: errorLogs
            )
        }

        let exitCode: Int32 = errorLogs.isEmpty ? 0 : 1
        let stderr = errorLogs.isEmpty ? "" : renderErrorText(
            exitCode: exitCode,
            kind: .processingError,
            message: errorLogs.count == 1 ? errorLogs[0] : "\(errorLogs.count) error(s) occurred during OCR processing.",
            format: parsed.errorFormat,
            includeUsage: false,
            errors: errorLogs
        )
        return CLIResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    private static func runWatch(
        watchDirectoryPath: String,
        parsed: ParsedArguments,
        currentDirectory: URL,
        outputDirectory: URL,
        postProcessor: PostProcessor,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing,
        watchPollIntervalNanoseconds: UInt64,
        sleep: @escaping SleepFunction
    ) async -> CLIResult {
        let watchDirectoryURL = makeAbsoluteURL(path: watchDirectoryPath, currentDirectory: currentDirectory)
        var isDirectory = ObjCBool(false)
        guard
            FileManager.default.fileExists(atPath: watchDirectoryURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return errorResult(
                exitCode: 66,
                kind: .inputError,
                message: "Watch directory not found at path: \(watchDirectoryURL.path)",
                format: parsed.errorFormat
            )
        }

        let settingsLog = parsed.logLevel == .quiet ? "" : settingsLog(for: parsed.configuration)
        let startTime = Date()
        var totalCount = 0
        var wroteCount = 0
        var skippedCount = 0
        var failedCount = 0
        var infoLogs: [String] = []
        var errorLogs: [String] = []
        var seenFingerprints: [String: String] = [:]

        if parsed.logLevel != .quiet {
            infoLogs.append("Watching directory: \(watchDirectoryURL.path)")
        }

        while true {
            if Task.isCancelled {
                break
            }

            do {
                let supportedFiles = try supportedInputFiles(in: watchDirectoryURL, recursive: parsed.recursive)
                let currentPaths = Set(supportedFiles.map(\.path))
                seenFingerprints = seenFingerprints.filter { currentPaths.contains($0.key) }

                let changedFiles = try supportedFiles.filter { fileURL in
                    let fingerprint = try inputFingerprint(for: fileURL)
                    if seenFingerprints[fileURL.path] != fingerprint {
                        seenFingerprints[fileURL.path] = fingerprint
                        return true
                    }
                    return false
                }

                if !changedFiles.isEmpty {
                    let watchParsed = parsed.replacingForWatch(inputPaths: changedFiles.map(\.path))
                    let resolution = resolveInputs(parsed: watchParsed, currentDirectory: currentDirectory)
                    let batchResult = await processResolution(
                        resolution: resolution,
                        parsed: watchParsed,
                        outputDirectory: outputDirectory,
                        postProcessor: postProcessor,
                        recognizerFactory: recognizerFactory
                    )
                    cleanupTemporaryDirectories(resolution.temporaryDirectories)

                    totalCount += resolution.jobs.count
                    wroteCount += batchResult.wroteCount
                    skippedCount += batchResult.skippedCount
                    failedCount += batchResult.failedCount
                    infoLogs.append(contentsOf: batchResult.infoLogs)
                    errorLogs.append(contentsOf: batchResult.errorLogs)
                }
            } catch {
                errorLogs.append("Watch scan failed for directory: \(watchDirectoryURL.path)\nReason: \(error.localizedDescription)")
                failedCount += 1
            }

            do {
                try await sleep(watchPollIntervalNanoseconds)
            } catch is CancellationError {
                break
            } catch {
                errorLogs.append("Watch loop failed while waiting for changes.\nReason: \(error.localizedDescription)")
                failedCount += 1
                break
            }
        }

        var stdout = ""
        if parsed.logLevel != .quiet {
            let summary = summaryLog(
                totalCount: totalCount,
                wroteCount: wroteCount,
                skippedCount: skippedCount,
                failedCount: failedCount,
                startTime: startTime
            )
            stdout = settingsLog
                + (infoLogs.isEmpty ? "" : infoLogs.joined(separator: "\n") + "\n")
                + summary + "\n"
        }
        let formattedStderr = errorLogs.isEmpty ? "" : renderErrorText(
            exitCode: errorLogs.isEmpty ? 0 : 1,
            kind: .processingError,
            message: errorLogs.count == 1 ? errorLogs[0] : "\(errorLogs.count) error(s) occurred during watch processing.",
            format: parsed.errorFormat,
            errors: errorLogs
        )
        let exitCode: Int32 = errorLogs.isEmpty ? 0 : 1
        return CLIResult(exitCode: exitCode, stdout: stdout, stderr: formattedStderr)
    }

    private static func processResolution(
        resolution: InputResolution,
        parsed: ParsedArguments,
        outputDirectory: URL,
        postProcessor: PostProcessor,
        recognizerFactory: @escaping (OCREngine) -> any TextRecognizing
    ) async -> BatchProcessingResult {
        var processedOutputs: [ProcessedOutput] = []
        var infoLogs: [String] = []
        var errorLogs = resolution.failures.map(\.message)
        var wroteCount = 0
        var skippedCount = 0
        var failedCount = resolution.failures.count
        var executableJobs: [PlannedJob] = []

        for (index, job) in resolution.jobs.enumerated() {
            let outputURL = parsed.outputMode == .stdout ? nil : OutputWriter.outputURL(
                forInput: job.outputInputURL,
                outputDirectory: outputDirectory,
                relativeOutputPath: job.relativeOutputPath,
                format: parsed.outputFormat
            )

            if let outputURL {
                switch parsed.overwritePolicy {
                case .skipExisting:
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        skippedCount += 1
                        if parsed.logLevel != .quiet {
                            infoLogs.append("Skipped existing output: \(outputURL.path)")
                        }
                        continue
                    }
                case .failOnExisting:
                    if FileManager.default.fileExists(atPath: outputURL.path) {
                        failedCount += 1
                        errorLogs.append("Output already exists: \(outputURL.path)")
                        continue
                    }
                case .overwrite:
                    break
                }
            }

            executableJobs.append(PlannedJob(index: index, job: job, outputURL: outputURL))
        }

        let executionResults = await executeJobs(
            executableJobs,
            parsed: parsed,
            postProcessor: postProcessor,
            recognizerFactory: recognizerFactory
        )
        let sortedResults = executionResults.sorted { $0.index < $1.index }

        for result in sortedResults {
            switch result.outcome {
            case .success(let processedOutput, let outputURL):
                processedOutputs.append(processedOutput)
                wroteCount += 1
                if let outputURL, parsed.logLevel != .quiet {
                    infoLogs.append("Wrote OCR text to: \(outputURL.path)")
                }
            case .failure(let message):
                failedCount += 1
                errorLogs.append(message)
            }
        }

        return BatchProcessingResult(
            processedOutputs: processedOutputs,
            infoLogs: infoLogs,
            errorLogs: errorLogs,
            wroteCount: wroteCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
    }

    private static func makeLanguagesOutput(
        parsed: ParsedArguments,
        languageProvider: @escaping LanguageProvider
    ) throws -> String {
        let engines: [OCREngine] = parsed.engineWasExplicitlySet ? [parsed.configuration.engine] : OCREngine.allCases
        var lines: [String] = []

        for (index, engine) in engines.enumerated() {
            if index > 0 {
                lines.append("")
            }
            lines.append("Supported languages for \(engine.rawValue):")
            for language in try languageProvider(engine) {
                lines.append("- \(language)")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func usageText() -> String {
        """
        Usage:
          apple-local-ocr [options] <image-or-directory-path> [<image-or-directory-path> ...]
          apple-local-ocr inspect [options] <image-or-directory-path> [<image-or-directory-path> ...]
          apple-local-ocr languages [--engine vision|liveText]
          apple-local-ocr --version
          --engine vision|liveText   OCR backend (default: liveText)
          --lang code1,code2         Comma-separated language codes (example: zh-Hans,en-US)
          --no-correction            Disable language correction (Vision engine only)
          --error-format text|json   Error output format (default: text)
          --output PATH              Write files under PATH (default: output/)
          --stdout                   Print OCR output to stdout instead of writing files
          --watch PATH               Watch a directory for new or changed OCR inputs
          --recursive                Recursively scan directory inputs
          --overwrite                Overwrite existing outputs
          --skip                     Skip existing outputs (default)
          --fail-on-existing         Fail items whose outputs already exist
          --format txt|json|md       Output format (default: txt)
          --preserve-structure       Keep directory structure under the output directory
          --pdf-mode combined|per-page
                                     PDF output mode (default: combined)
          --page-range LIST          PDF pages to OCR (example: 1-3,5)
          --page-separator TEXT      Separator inserted between combined PDF pages
          --jobs N                   Maximum concurrent OCR jobs (default: 1)
          --normalize-whitespace     Collapse internal whitespace runs within each line
          --trim-empty-lines         Remove empty lines from OCR output
          --smart-quotes on|off      Convert straight or curly quotes during cleanup
          --find TEXT                Replace matching OCR text
          --replace TEXT             Replacement text used with --find
          --dictionary PATH          Replacement rules file (tab-separated find/replace)
          --quiet                    Suppress success logs
          --verbose                  Enable detailed success logs
          --version                  Print the CLI version and exit
        """
        + "\n"
    }

    private static func parse(arguments: [String]) throws -> ParsedArguments {
        guard !arguments.isEmpty else {
            throw UsageError(message: "Missing image path.")
        }

        var commandMode: CommandMode = .run
        var startIndex = 0
        if arguments.first == "inspect" {
            commandMode = .inspect
            startIndex = 1
        } else if arguments.first == "languages" {
            commandMode = .languages
            startIndex = 1
        }

        var engine: OCREngine = .liveText
        var engineWasExplicitlySet = false
        var languages: [String] = ["zh-Hans", "en-US"]
        var usesLanguageCorrection = true
        var errorFormat: ErrorFormat = .text
        var inputPaths: [String] = []
        var outputDirectoryPath: String?
        var outputMode: OutputMode = .files
        var watchDirectoryPath: String?
        var recursive = false
        var overwritePolicy: OverwritePolicy = .skipExisting
        var logLevel: LogLevel = .normal
        var outputFormat: OutputFormat = .txt
        var preserveStructure = false
        var pdfMode: PDFMode = .combined
        var pageSelection: PageSelection?
        var pageSeparator = "\n\n"
        var maxJobs = 1
        var normalizeWhitespace = false
        var trimEmptyLines = false
        var smartQuotesMode: SmartQuotesMode?
        var findText: String?
        var replaceText: String?
        var dictionaryPath: String?

        var index = startIndex
        while index < arguments.count {
            let arg = arguments[index]

            if arg == "--no-correction" {
                usesLanguageCorrection = false
                index += 1
                continue
            }

            if arg.hasPrefix("--error-format=") {
                let raw = String(arg.dropFirst("--error-format=".count))
                errorFormat = try parseErrorFormat(raw)
                index += 1
                continue
            }

            if arg == "--error-format" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--error-format")
                errorFormat = try parseErrorFormat(raw)
                index += 2
                continue
            }

            if arg.hasPrefix("--engine=") {
                let value = String(arg.dropFirst("--engine=".count))
                engine = try parseEngine(value)
                engineWasExplicitlySet = true
                index += 1
                continue
            }

            if arg == "--engine" {
                let value = try valueAfterFlag(arguments: arguments, index: index, flag: "--engine")
                engine = try parseEngine(value)
                engineWasExplicitlySet = true
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

            if arg.hasPrefix("--output=") {
                outputDirectoryPath = String(arg.dropFirst("--output=".count))
                index += 1
                continue
            }

            if arg == "--output" {
                outputDirectoryPath = try valueAfterFlag(arguments: arguments, index: index, flag: "--output")
                index += 2
                continue
            }

            if arg == "--stdout" {
                outputMode = .stdout
                index += 1
                continue
            }

            if arg.hasPrefix("--watch=") {
                watchDirectoryPath = String(arg.dropFirst("--watch=".count))
                index += 1
                continue
            }

            if arg == "--watch" {
                watchDirectoryPath = try valueAfterFlag(arguments: arguments, index: index, flag: "--watch")
                index += 2
                continue
            }

            if arg == "--recursive" {
                recursive = true
                index += 1
                continue
            }

            if arg == "--overwrite" {
                overwritePolicy = .overwrite
                index += 1
                continue
            }

            if arg == "--skip" {
                overwritePolicy = .skipExisting
                index += 1
                continue
            }

            if arg == "--fail-on-existing" {
                overwritePolicy = .failOnExisting
                index += 1
                continue
            }

            if arg.hasPrefix("--format=") {
                let raw = String(arg.dropFirst("--format=".count))
                outputFormat = try parseFormat(raw)
                index += 1
                continue
            }

            if arg == "--format" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--format")
                outputFormat = try parseFormat(raw)
                index += 2
                continue
            }

            if arg == "--preserve-structure" {
                preserveStructure = true
                index += 1
                continue
            }

            if arg.hasPrefix("--pdf-mode=") {
                let raw = String(arg.dropFirst("--pdf-mode=".count))
                pdfMode = try parsePDFMode(raw)
                index += 1
                continue
            }

            if arg == "--pdf-mode" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--pdf-mode")
                pdfMode = try parsePDFMode(raw)
                index += 2
                continue
            }

            if arg.hasPrefix("--page-range=") {
                let raw = String(arg.dropFirst("--page-range=".count))
                pageSelection = try parsePageSelection(raw)
                index += 1
                continue
            }

            if arg == "--page-range" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--page-range")
                pageSelection = try parsePageSelection(raw)
                index += 2
                continue
            }

            if arg.hasPrefix("--page-separator=") {
                pageSeparator = String(arg.dropFirst("--page-separator=".count))
                index += 1
                continue
            }

            if arg == "--page-separator" {
                pageSeparator = try valueAfterFlag(arguments: arguments, index: index, flag: "--page-separator")
                index += 2
                continue
            }

            if arg.hasPrefix("--jobs=") {
                let raw = String(arg.dropFirst("--jobs=".count))
                maxJobs = try parseJobs(raw)
                index += 1
                continue
            }

            if arg == "--jobs" {
                let raw = try valueAfterFlag(arguments: arguments, index: index, flag: "--jobs")
                maxJobs = try parseJobs(raw)
                index += 2
                continue
            }

            if arg == "--normalize-whitespace" {
                normalizeWhitespace = true
                index += 1
                continue
            }

            if arg == "--trim-empty-lines" {
                trimEmptyLines = true
                index += 1
                continue
            }

            if arg.hasPrefix("--smart-quotes=") {
                smartQuotesMode = try parseSmartQuotesMode(String(arg.dropFirst("--smart-quotes=".count)))
                index += 1
                continue
            }

            if arg == "--smart-quotes" {
                smartQuotesMode = try parseSmartQuotesMode(
                    valueAfterFlag(arguments: arguments, index: index, flag: "--smart-quotes")
                )
                index += 2
                continue
            }

            if arg.hasPrefix("--find=") {
                findText = String(arg.dropFirst("--find=".count))
                index += 1
                continue
            }

            if arg == "--find" {
                findText = try valueAfterFlag(arguments: arguments, index: index, flag: "--find")
                index += 2
                continue
            }

            if arg.hasPrefix("--replace=") {
                replaceText = String(arg.dropFirst("--replace=".count))
                index += 1
                continue
            }

            if arg == "--replace" {
                replaceText = try valueAfterFlag(arguments: arguments, index: index, flag: "--replace")
                index += 2
                continue
            }

            if arg.hasPrefix("--dictionary=") {
                dictionaryPath = String(arg.dropFirst("--dictionary=".count))
                index += 1
                continue
            }

            if arg == "--dictionary" {
                dictionaryPath = try valueAfterFlag(arguments: arguments, index: index, flag: "--dictionary")
                index += 2
                continue
            }

            if arg == "--quiet" {
                logLevel = .quiet
                index += 1
                continue
            }

            if arg == "--verbose" {
                logLevel = .verbose
                index += 1
                continue
            }

            if arg.hasPrefix("-") {
                throw UsageError(message: "Unknown option: \(arg)")
            }

            inputPaths.append(arg)
            index += 1
        }

        if (findText == nil) != (replaceText == nil) {
            throw UsageError(message: "Use --find and --replace together.")
        }

        if let findText, findText.isEmpty {
            throw UsageError(message: "--find cannot be empty.")
        }

        if commandMode == .languages {
            guard watchDirectoryPath == nil else {
                throw UsageError(message: "'languages' cannot be combined with --watch.")
            }
            guard inputPaths.isEmpty else {
                throw UsageError(message: "'languages' does not accept input paths.")
            }
        } else if commandMode == .inspect, watchDirectoryPath != nil {
            throw UsageError(message: "--watch can only be used in normal run mode.")
        } else if let watchDirectoryPath {
            if !inputPaths.isEmpty {
                throw UsageError(message: "--watch cannot be combined with input paths.")
            }
            if outputMode == .stdout {
                throw UsageError(message: "--watch cannot be used with --stdout.")
            }
            inputPaths = [watchDirectoryPath]
        }

        guard commandMode == .languages || !inputPaths.isEmpty else {
            throw UsageError(message: "Missing image path.")
        }

        return ParsedArguments(
            commandMode: commandMode,
            inputPaths: inputPaths,
            watchDirectoryPath: watchDirectoryPath,
            errorFormat: errorFormat,
            configuration: OCRConfiguration(
                engine: engine,
                recognitionLanguages: languages,
                usesLanguageCorrection: usesLanguageCorrection
            ),
            engineWasExplicitlySet: engineWasExplicitlySet,
            outputDirectoryPath: outputDirectoryPath,
            outputMode: outputMode,
            recursive: recursive,
            overwritePolicy: overwritePolicy,
            logLevel: logLevel,
            outputFormat: outputFormat,
            preserveStructure: preserveStructure,
            pdfMode: pdfMode,
            pageSelection: pageSelection,
            pageSeparator: pageSeparator,
            maxJobs: maxJobs,
            normalizeWhitespace: normalizeWhitespace,
            trimEmptyLines: trimEmptyLines,
            smartQuotesMode: smartQuotesMode,
            findText: findText,
            replaceText: replaceText,
            dictionaryPath: dictionaryPath
        )
    }

    private static func parseRequestedErrorFormat(arguments: [String]) throws -> ErrorFormat {
        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            if arg.hasPrefix("--error-format=") {
                return try parseErrorFormat(String(arg.dropFirst("--error-format=".count)))
            }
            if arg == "--error-format" {
                return try parseErrorFormat(valueAfterFlag(arguments: arguments, index: index, flag: "--error-format"))
            }
            index += 1
        }
        return .text
    }

    private static func parseEngine(_ rawValue: String) throws -> OCREngine {
        guard let engine = OCREngine(rawValue: rawValue) else {
            throw UsageError(message: "Invalid engine '\(rawValue)'. Use 'vision' or 'liveText'.")
        }
        return engine
    }

    private static func parseFormat(_ rawValue: String) throws -> OutputFormat {
        guard let format = OutputFormat(rawValue: rawValue) else {
            throw UsageError(message: "Invalid format '\(rawValue)'. Use 'txt', 'json', or 'md'.")
        }
        return format
    }

    private static func parseErrorFormat(_ rawValue: String) throws -> ErrorFormat {
        guard let format = ErrorFormat(rawValue: rawValue) else {
            throw UsageError(message: "Invalid error format '\(rawValue)'. Use 'text' or 'json'.")
        }
        return format
    }

    private static func parsePDFMode(_ rawValue: String) throws -> PDFMode {
        guard let mode = PDFMode(rawValue: rawValue) else {
            throw UsageError(message: "Invalid PDF mode '\(rawValue)'. Use 'combined' or 'per-page'.")
        }
        return mode
    }

    private static func parsePageSelection(_ rawValue: String) throws -> PageSelection {
        do {
            return try PageSelection.parse(rawValue)
        } catch {
            throw UsageError(message: "Invalid page range '\(rawValue)'. Use values like '1-3,5'.")
        }
    }

    private static func parseJobs(_ rawValue: String) throws -> Int {
        guard let value = Int(rawValue), value > 0 else {
            throw UsageError(message: "Invalid jobs value '\(rawValue)'. Use a positive integer.")
        }
        return value
    }

    private static func parseSmartQuotesMode(_ rawValue: String) throws -> SmartQuotesMode {
        guard let mode = SmartQuotesMode(rawValue: rawValue) else {
            throw UsageError(message: "Invalid smart quotes mode '\(rawValue)'. Use 'on' or 'off'.")
        }
        return mode
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

    private static func settingsLog(for configuration: OCRConfiguration) -> String {
        "OCR settings -> engine: \(configuration.engine.rawValue), languages: \(formatLanguages(configuration.recognitionLanguages))\n"
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

    private static func resolveInputs(parsed: ParsedArguments, currentDirectory: URL) -> InputResolution {
        var jobs: [ResolvedOCRJob] = []
        var failures: [InputFailure] = []
        var temporaryDirectories: [URL] = []

        for rawPath in parsed.inputPaths {
            let inputURL = makeAbsoluteURL(path: rawPath, currentDirectory: currentDirectory)

            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
                failures.append(
                    InputFailure(
                        message: "Input not found at path: \(inputURL.path)",
                        exitCode: parsed.inputPaths.count == 1 ? 66 : 1
                    )
                )
                continue
            }

            if isDirectory.boolValue {
                do {
                    let inputFiles = try supportedInputFiles(in: inputURL, recursive: parsed.recursive)
                    if inputFiles.isEmpty {
                        failures.append(
                            InputFailure(
                                message: "No supported image or PDF files found in directory: \(inputURL.path)",
                                exitCode: parsed.inputPaths.count == 1 ? 65 : 1
                            )
                        )
                        continue
                    }

                    for fileURL in inputFiles {
                        appendResolvedJobs(
                            for: fileURL,
                            rootInputURL: inputURL,
                            parsed: parsed,
                            jobs: &jobs,
                            failures: &failures,
                            temporaryDirectories: &temporaryDirectories
                        )
                    }
                } catch {
                    failures.append(
                        InputFailure(
                            message: "Could not read input directory at path: \(inputURL.path)",
                            exitCode: parsed.inputPaths.count == 1 ? 66 : 1
                        )
                    )
                }
                continue
            }

            appendResolvedJobs(
                for: inputURL,
                rootInputURL: nil,
                parsed: parsed,
                jobs: &jobs,
                failures: &failures,
                temporaryDirectories: &temporaryDirectories
            )
        }

        jobs.sort { lhs, rhs in
            lhs.outputInputURL.path.localizedStandardCompare(rhs.outputInputURL.path) == .orderedAscending
        }
        return InputResolution(jobs: jobs, failures: failures, temporaryDirectories: temporaryDirectories)
    }

    private static func appendResolvedJobs(
        for fileURL: URL,
        rootInputURL: URL?,
        parsed: ParsedArguments,
        jobs: inout [ResolvedOCRJob],
        failures: inout [InputFailure],
        temporaryDirectories: inout [URL]
    ) {
        let ext = fileURL.pathExtension.lowercased()
        let failureExitCode: Int32 = parsed.inputPaths.count == 1 ? 65 : 1

        if supportedImageExtensions.contains(ext) {
            jobs.append(
                ResolvedOCRJob(
                    inputPath: fileURL.path,
                    outputInputURL: fileURL,
                    relativeOutputPath: outputRelativePath(
                        for: fileURL,
                        rootInputURL: rootInputURL,
                        preserveStructure: parsed.preserveStructure,
                        format: parsed.outputFormat,
                        pageNumber: nil
                    ),
                    units: [OCRUnit(imageURL: fileURL, pageNumber: nil)],
                    kind: .image,
                    pageSeparator: parsed.pageSeparator
                )
            )
            return
        }

        if supportedPDFExtensions.contains(ext) {
            do {
                let renderedDocument = try PDFRenderer().renderDocument(
                    at: fileURL,
                    selectedPages: parsed.pageSelection
                )
                temporaryDirectories.append(renderedDocument.temporaryDirectory)

                guard !renderedDocument.pages.isEmpty else {
                    failures.append(
                        InputFailure(
                            message: "No PDF pages selected for input: \(fileURL.path)",
                            exitCode: failureExitCode
                        )
                    )
                    return
                }

                switch parsed.pdfMode {
                case .combined:
                    jobs.append(
                        ResolvedOCRJob(
                            inputPath: fileURL.path,
                            outputInputURL: fileURL,
                            relativeOutputPath: outputRelativePath(
                                for: fileURL,
                                rootInputURL: rootInputURL,
                                preserveStructure: parsed.preserveStructure,
                                format: parsed.outputFormat,
                                pageNumber: nil
                            ),
                            units: renderedDocument.pages.map {
                                OCRUnit(imageURL: $0.imageURL, pageNumber: $0.pageNumber)
                            },
                            kind: .pdfCombined,
                            pageSeparator: parsed.pageSeparator
                        )
                    )
                case .perPage:
                    for page in renderedDocument.pages {
                        jobs.append(
                            ResolvedOCRJob(
                                inputPath: fileURL.path,
                                outputInputURL: fileURL,
                                relativeOutputPath: outputRelativePath(
                                    for: fileURL,
                                    rootInputURL: rootInputURL,
                                    preserveStructure: parsed.preserveStructure,
                                    format: parsed.outputFormat,
                                    pageNumber: page.pageNumber
                                ),
                                units: [OCRUnit(imageURL: page.imageURL, pageNumber: page.pageNumber)],
                                kind: .pdfPage(page.pageNumber),
                                pageSeparator: parsed.pageSeparator
                            )
                        )
                    }
                }
            } catch {
                failures.append(
                    InputFailure(
                        message: "Could not process PDF input at path: \(fileURL.path)\nReason: \(error.localizedDescription)",
                        exitCode: failureExitCode
                    )
                )
            }
            return
        }

        failures.append(
            InputFailure(
                message: "Input must be an image file or PDF.",
                exitCode: failureExitCode
            )
        )
    }

    private static func outputRelativePath(
        for sourceURL: URL,
        rootInputURL: URL?,
        preserveStructure: Bool,
        format: OutputFormat,
        pageNumber: Int?
    ) -> String? {
        let basePath: String
        if preserveStructure, let rootInputURL {
            let relativeBasePath = (relativePath(from: rootInputURL, to: sourceURL) as NSString).deletingPathExtension
            basePath = [rootInputURL.lastPathComponent, relativeBasePath]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        } else {
            basePath = sourceURL.deletingPathExtension().lastPathComponent
        }

        if !preserveStructure && pageNumber == nil {
            return nil
        }

        let pageSuffix = pageNumber.map { "-page-\($0)" } ?? ""
        return "\(basePath)\(pageSuffix).\(format.fileExtension)"
    }

    private static func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if filePath.hasPrefix(prefix) {
            return String(filePath.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private static func supportedInputFiles(in directoryURL: URL, recursive: Bool) throws -> [URL] {
        if recursive {
            guard let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }

            var results: [URL] = []
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else {
                    continue
                }

                let ext = fileURL.pathExtension.lowercased()
                if supportedImageExtensions.contains(ext) || supportedPDFExtensions.contains(ext) {
                    results.append(fileURL)
                }
            }

            return results.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        return fileURLs
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard supportedImageExtensions.contains(ext) || supportedPDFExtensions.contains(ext) else {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile == true
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func cleanupTemporaryDirectories(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func inputFingerprint(for fileURL: URL) throws -> String {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values.fileSize ?? 0
        return "\(fileSize)-\(modifiedAt)"
    }

    private static func makePostProcessor(
        parsed: ParsedArguments,
        currentDirectory: URL
    ) throws -> PostProcessor {
        var replacementRules: [ReplacementRule] = []

        if let dictionaryPath = parsed.dictionaryPath {
            let dictionaryURL = makeAbsoluteURL(path: dictionaryPath, currentDirectory: currentDirectory)
            guard FileManager.default.fileExists(atPath: dictionaryURL.path) else {
                throw PostProcessingError(
                    message: "Dictionary file not found at path: \(dictionaryURL.path)",
                    exitCode: 66
                )
            }

            let contents: String
            do {
                contents = try String(contentsOf: dictionaryURL, encoding: .utf8)
            } catch {
                throw PostProcessingError(
                    message: "Could not read dictionary file at path: \(dictionaryURL.path)",
                    exitCode: 66
                )
            }

            for (lineNumber, rawLine) in contents.components(separatedBy: .newlines).enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else {
                    continue
                }

                if let rule = parseDictionaryRule(line) {
                    replacementRules.append(rule)
                    continue
                }

                throw PostProcessingError(
                    message: "Invalid dictionary rule at line \(lineNumber + 1). Use 'find<TAB>replace' or 'find => replace'.",
                    exitCode: 64
                )
            }
        }

        let explicitReplacement = parsed.findText.map { ReplacementRule(find: $0, replace: parsed.replaceText ?? "") }
        return PostProcessor(
            normalizeWhitespace: parsed.normalizeWhitespace,
            trimEmptyLines: parsed.trimEmptyLines,
            smartQuotesMode: parsed.smartQuotesMode,
            replacementRules: replacementRules,
            explicitReplacement: explicitReplacement
        )
    }

    private static func parseDictionaryRule(_ line: String) -> ReplacementRule? {
        if let tabRange = line.range(of: "\t") {
            let find = String(line[..<tabRange.lowerBound])
            let replace = String(line[tabRange.upperBound...])
            guard !find.isEmpty else {
                return nil
            }
            return ReplacementRule(find: find, replace: replace)
        }

        if let arrowRange = line.range(of: "=>") {
            let find = String(line[..<arrowRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let replace = String(line[arrowRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !find.isEmpty else {
                return nil
            }
            return ReplacementRule(find: find, replace: replace)
        }

        return nil
    }

    fileprivate static func normalizeWhitespace(in text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    fileprivate static func trimEmptyLines(in text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
    }

    fileprivate static func smartQuotesOff(in text: String) -> String {
        text
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")
    }

    fileprivate static func smartQuotesOn(in text: String) -> String {
        let characters = Array(text)
        var output = ""
        var nextDoubleIsOpening = true
        var nextSingleIsOpening = true

        for (index, character) in characters.enumerated() {
            switch character {
            case "\"":
                output.append(nextDoubleIsOpening ? "“" : "”")
                nextDoubleIsOpening.toggle()
            case "'":
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let isApostrophe = isWordCharacter(previous) && isWordCharacter(next)
                if isApostrophe {
                    output.append("’")
                } else {
                    output.append(nextSingleIsOpening ? "‘" : "’")
                    nextSingleIsOpening.toggle()
                }
            default:
                output.append(character)
            }
        }

        return output
    }

    fileprivate static func isWordCharacter(_ character: Character?) -> Bool {
        guard let character else {
            return false
        }
        return character.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }

    private static func makeProcessedOutput(
        job: ResolvedOCRJob,
        unitResults: [RecognizedUnitResult],
        outputPath: String?
    ) -> ProcessedOutput {
        switch job.kind {
        case .image:
            return ProcessedOutput(
                inputPath: job.inputPath,
                text: unitResults.first?.text ?? "",
                outputPath: outputPath,
                pageNumber: nil,
                pages: nil
            )
        case .pdfCombined:
            let pageResults = unitResults.compactMap { unitResult -> ProcessedPageResult? in
                guard let pageNumber = unitResult.pageNumber else {
                    return nil
                }
                return ProcessedPageResult(pageNumber: pageNumber, text: unitResult.text)
            }
            return ProcessedOutput(
                inputPath: job.inputPath,
                text: pageResults.map(\.text).joined(separator: job.pageSeparator),
                outputPath: outputPath,
                pageNumber: nil,
                pages: pageResults
            )
        case .pdfPage(let pageNumber):
            return ProcessedOutput(
                inputPath: job.inputPath,
                text: unitResults.first?.text ?? "",
                outputPath: outputPath,
                pageNumber: pageNumber,
                pages: nil
            )
        }
    }

    private static func renderOutput(
        for output: ProcessedOutput,
        format: OutputFormat,
        configuration: OCRConfiguration
    ) throws -> String {
        switch format {
        case .txt:
            return output.text
        case .md:
            if let pages = output.pages, !pages.isEmpty {
                let pageSections = pages.map { page in
                    "## Page \(page.pageNumber)\n\n\(page.text)"
                }
                return """
                # OCR Result

                Source: \(output.inputPath)

                \(pageSections.joined(separator: "\n\n"))
                """
            }

            let pagePrefix = output.pageNumber.map { "Page: \($0)\n\n" } ?? ""
            return """
            # OCR Result

            Source: \(output.inputPath)

            \(pagePrefix)\(output.text)
            """
        case .json:
            let payload = JSONOutputPayload(
                schemaVersion: outputSchemaVersion,
                toolVersion: toolVersion,
                inputPath: output.inputPath,
                outputPath: output.outputPath,
                engine: configuration.engine.rawValue,
                languages: configuration.recognitionLanguages,
                format: format.rawValue,
                text: output.text,
                pageNumber: output.pageNumber,
                pages: output.pages
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            return String(decoding: data, as: UTF8.self)
        }
    }

    private static func makeStdout(
        parsed: ParsedArguments,
        settingsLog: String,
        infoLogs: [String],
        summary: String,
        includeSummary: Bool,
        processedOutputs: [ProcessedOutput]
    ) throws -> String {
        if parsed.outputMode == .stdout {
            return try stdoutPayload(for: processedOutputs, format: parsed.outputFormat, configuration: parsed.configuration)
        }

        guard parsed.logLevel != .quiet else {
            return ""
        }

        let body = infoLogs.isEmpty ? "" : infoLogs.joined(separator: "\n") + "\n"
        let summaryText = includeSummary ? summary + "\n" : ""
        return settingsLog + body + summaryText
    }

    private static func stdoutPayload(
        for outputs: [ProcessedOutput],
        format: OutputFormat,
        configuration: OCRConfiguration
    ) throws -> String {
        switch format {
        case .json:
            let payloads = outputs.map {
                JSONOutputPayload(
                    schemaVersion: outputSchemaVersion,
                    toolVersion: toolVersion,
                    inputPath: $0.inputPath,
                    outputPath: $0.outputPath,
                    engine: configuration.engine.rawValue,
                    languages: configuration.recognitionLanguages,
                    format: format.rawValue,
                    text: $0.text,
                    pageNumber: $0.pageNumber,
                    pages: $0.pages
                )
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            let data: Data
            if payloads.count == 1, let payload = payloads.first {
                data = try encoder.encode(payload)
            } else {
                data = try encoder.encode(payloads)
            }
            return String(decoding: data, as: UTF8.self) + "\n"
        case .txt, .md:
            if outputs.count == 1, let output = outputs.first {
                return try renderOutput(for: output, format: format, configuration: configuration) + "\n"
            }

            return try outputs.map {
                let rendered = try renderOutput(for: $0, format: format, configuration: configuration)
                return ">>> \($0.inputPath)\n\(rendered)"
            }
            .joined(separator: "\n\n") + "\n"
        }
    }

    private static func makeInspectOutput(
        jobs: [ResolvedOCRJob],
        outputDirectory: URL,
        outputMode: OutputMode,
        format: OutputFormat
    ) -> String {
        var lines = ["Inspect -> total jobs: \(jobs.count)"]
        for job in jobs {
            let outputDescription: String
            if outputMode == .stdout {
                outputDescription = "stdout"
            } else {
                let outputURL = OutputWriter.outputURL(
                    forInput: job.outputInputURL,
                    outputDirectory: outputDirectory,
                    relativeOutputPath: job.relativeOutputPath,
                    format: format
                )
                outputDescription = outputURL.path
            }

            switch job.kind {
            case .image:
                lines.append("- image: \(job.inputPath) -> \(outputDescription)")
            case .pdfCombined:
                let pageList = job.units.compactMap(\.pageNumber).map(String.init).joined(separator: ",")
                lines.append("- pdf: \(job.inputPath) pages [\(pageList)] -> \(outputDescription)")
            case .pdfPage(let pageNumber):
                lines.append("- pdf page \(pageNumber): \(job.inputPath) -> \(outputDescription)")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func errorResult(
        exitCode: Int32,
        kind: CLIErrorKind,
        message: String,
        format: ErrorFormat,
        includeUsage: Bool = false,
        errors: [String] = []
    ) -> CLIResult {
        CLIResult(
            exitCode: exitCode,
            stdout: "",
            stderr: renderErrorText(
                exitCode: exitCode,
                kind: kind,
                message: message,
                format: format,
                includeUsage: includeUsage,
                errors: errors
            )
        )
    }

    private static func renderErrorText(
        exitCode: Int32,
        kind: CLIErrorKind,
        message: String,
        format: ErrorFormat,
        includeUsage: Bool = false,
        errors: [String] = []
    ) -> String {
        switch format {
        case .text:
            let body: String
            if includeUsage {
                body = "\(message)\n\(usageText())"
            } else if !errors.isEmpty {
                body = errors.joined(separator: "\n") + "\n"
            } else {
                body = message + "\n"
            }
            return body
        case .json:
            let payload = CLIErrorPayload(
                schemaVersion: outputSchemaVersion,
                toolVersion: toolVersion,
                kind: kind.rawValue,
                message: message,
                exitCode: Int(exitCode),
                errors: errors.isEmpty ? nil : errors
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(payload) else {
                return """
                {"schemaVersion":"\(outputSchemaVersion)","toolVersion":"\(toolVersion)","kind":"internal_error","message":"Failed to encode JSON error output.","exitCode":70}
                """ + "\n"
            }
            return String(decoding: data, as: UTF8.self) + "\n"
        }
    }

    private static func summaryLog(
        totalCount: Int,
        wroteCount: Int,
        skippedCount: Int,
        failedCount: Int,
        startTime: Date
    ) -> String {
        let elapsed = Date().timeIntervalSince(startTime)
        return String(
            format: "Summary -> total files: %d, wrote: %d, skipped: %d, failed: %d, elapsed: %.2fs",
            totalCount,
            wroteCount,
            skippedCount,
            failedCount,
            elapsed
        )
    }
}

private struct ParsedArguments {
    let commandMode: CommandMode
    let inputPaths: [String]
    let watchDirectoryPath: String?
    let errorFormat: ErrorFormat
    let configuration: OCRConfiguration
    let engineWasExplicitlySet: Bool
    let outputDirectoryPath: String?
    let outputMode: OutputMode
    let recursive: Bool
    let overwritePolicy: OverwritePolicy
    let logLevel: LogLevel
    let outputFormat: OutputFormat
    let preserveStructure: Bool
    let pdfMode: PDFMode
    let pageSelection: PageSelection?
    let pageSeparator: String
    let maxJobs: Int
    let normalizeWhitespace: Bool
    let trimEmptyLines: Bool
    let smartQuotesMode: SmartQuotesMode?
    let findText: String?
    let replaceText: String?
    let dictionaryPath: String?

    func replacingForWatch(inputPaths: [String]) -> ParsedArguments {
        ParsedArguments(
            commandMode: .run,
            inputPaths: inputPaths,
            watchDirectoryPath: watchDirectoryPath,
            errorFormat: errorFormat,
            configuration: configuration,
            engineWasExplicitlySet: engineWasExplicitlySet,
            outputDirectoryPath: outputDirectoryPath,
            outputMode: outputMode,
            recursive: recursive,
            overwritePolicy: overwritePolicy,
            logLevel: logLevel,
            outputFormat: outputFormat,
            preserveStructure: preserveStructure,
            pdfMode: pdfMode,
            pageSelection: pageSelection,
            pageSeparator: pageSeparator,
            maxJobs: maxJobs,
            normalizeWhitespace: normalizeWhitespace,
            trimEmptyLines: trimEmptyLines,
            smartQuotesMode: smartQuotesMode,
            findText: findText,
            replaceText: replaceText,
            dictionaryPath: dictionaryPath
        )
    }
}

private enum CommandMode: Equatable {
    case run
    case inspect
    case languages
}

private enum OutputMode: Equatable {
    case files
    case stdout
}

private enum ErrorFormat: String, Equatable {
    case text
    case json
}

private enum OverwritePolicy: Equatable {
    case overwrite
    case skipExisting
    case failOnExisting
}

private enum LogLevel: Equatable {
    case quiet
    case normal
    case verbose
}

private enum PDFMode: String, Equatable {
    case combined
    case perPage = "per-page"
}

private enum SmartQuotesMode: String, Equatable {
    case on
    case off
}

private struct UsageError: Error {
    let message: String
}

private struct PostProcessingError: Error {
    let message: String
    let exitCode: Int32
}

private enum OCRJobKind: Equatable {
    case image
    case pdfCombined
    case pdfPage(Int)
}

private struct OCRUnit {
    let imageURL: URL
    let pageNumber: Int?
}

private struct ResolvedOCRJob {
    let inputPath: String
    let outputInputURL: URL
    let relativeOutputPath: String?
    let units: [OCRUnit]
    let kind: OCRJobKind
    let pageSeparator: String
}

private struct InputResolution {
    let jobs: [ResolvedOCRJob]
    let failures: [InputFailure]
    let temporaryDirectories: [URL]
}

private struct InputFailure {
    let message: String
    let exitCode: Int32
}

private struct ProcessedOutput {
    let inputPath: String
    let text: String
    let outputPath: String?
    let pageNumber: Int?
    let pages: [ProcessedPageResult]?
}

private struct ProcessedPageResult: Encodable, Equatable {
    let pageNumber: Int
    let text: String
}

private struct RecognizedUnitResult {
    let pageNumber: Int?
    let text: String
}

private struct JSONOutputPayload: Encodable {
    let schemaVersion: String
    let toolVersion: String
    let inputPath: String
    let outputPath: String?
    let engine: String
    let languages: [String]
    let format: String
    let text: String
    let pageNumber: Int?
    let pages: [ProcessedPageResult]?
}

private struct CLIErrorPayload: Encodable {
    let schemaVersion: String
    let toolVersion: String
    let kind: String
    let message: String
    let exitCode: Int
    let errors: [String]?
}

private enum CLIErrorKind: String {
    case usageError = "usage_error"
    case configurationError = "configuration_error"
    case inputError = "input_error"
    case processingError = "processing_error"
    case internalError = "internal_error"
}

private struct ReplacementRule: Equatable {
    let find: String
    let replace: String
}

private struct PostProcessor {
    let normalizeWhitespace: Bool
    let trimEmptyLines: Bool
    let smartQuotesMode: SmartQuotesMode?
    let replacementRules: [ReplacementRule]
    let explicitReplacement: ReplacementRule?

    func apply(to text: String) -> String {
        var result = text

        if normalizeWhitespace {
            result = CLI.normalizeWhitespace(in: result)
        }

        if trimEmptyLines {
            result = CLI.trimEmptyLines(in: result)
        }

        for rule in replacementRules {
            result = result.replacingOccurrences(of: rule.find, with: rule.replace)
        }

        if let explicitReplacement {
            result = result.replacingOccurrences(of: explicitReplacement.find, with: explicitReplacement.replace)
        }

        if let smartQuotesMode {
            switch smartQuotesMode {
            case .off:
                result = CLI.smartQuotesOff(in: result)
            case .on:
                result = CLI.smartQuotesOn(in: result)
            }
        }

        return result
    }
}

private struct PlannedJob {
    let index: Int
    let job: ResolvedOCRJob
    let outputURL: URL?
}

private struct ExecutionResult {
    let index: Int
    let outcome: ExecutionOutcome
}

private struct BatchProcessingResult {
    let processedOutputs: [ProcessedOutput]
    let infoLogs: [String]
    let errorLogs: [String]
    let wroteCount: Int
    let skippedCount: Int
    let failedCount: Int
}

private enum ExecutionOutcome {
    case success(ProcessedOutput, URL?)
    case failure(String)
}
