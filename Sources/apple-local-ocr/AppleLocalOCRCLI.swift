import Foundation
import AppleLocalOCRKit

@main
struct AppleLocalOCRCLIApp {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let result = await CLI.run(arguments: arguments)

        if !result.stdout.isEmpty {
            FileHandle.standardOutput.write(Data(result.stdout.utf8))
        }
        if !result.stderr.isEmpty {
            FileHandle.standardError.write(Data(result.stderr.utf8))
        }

        exit(result.exitCode)
    }
}
