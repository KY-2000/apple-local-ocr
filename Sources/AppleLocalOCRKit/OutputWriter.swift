import Foundation

enum OutputFormat: String, Equatable {
    case txt
    case json
    case md

    var fileExtension: String {
        rawValue
    }
}

enum OutputWriter {
    static func defaultOutputDirectory(workingDirectory: URL) -> URL {
        workingDirectory.appendingPathComponent("output", isDirectory: true)
    }

    static func defaultOutputURL(forInput input: URL, workingDirectory: URL) -> URL {
        outputURL(
            forInput: input,
            outputDirectory: defaultOutputDirectory(workingDirectory: workingDirectory),
            relativeOutputPath: nil,
            format: .txt
        )
    }

    static func outputURL(
        forInput input: URL,
        outputDirectory: URL,
        relativeOutputPath: String?,
        format: OutputFormat
    ) -> URL {
        if let relativeOutputPath {
            return outputDirectory.appendingPathComponent(relativeOutputPath, isDirectory: false)
        }

        let inputName = input.deletingPathExtension().lastPathComponent
        return outputDirectory.appendingPathComponent("\(inputName).\(format.fileExtension)")
    }

    static func write(text: String, to outputURL: URL) throws {
        let outputDirectory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        try text.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}
