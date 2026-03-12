import Foundation

enum OutputWriter {
    static func defaultOutputURL(forInput input: URL, workingDirectory: URL) -> URL {
        let outputDirectory = workingDirectory.appendingPathComponent("output", isDirectory: true)
        let inputName = input.deletingPathExtension().lastPathComponent
        return outputDirectory.appendingPathComponent("\(inputName).txt")
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
