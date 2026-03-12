import Foundation
import Vision
import VisionKit
import ImageIO

protocol TextRecognizing {
    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String
}

struct OCRService: TextRecognizing {
    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = configuration.usesLanguageCorrection
        if !configuration.recognitionLanguages.isEmpty {
            request.recognitionLanguages = configuration.recognitionLanguages
        }

        let handler = VNImageRequestHandler(url: imageURL)
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation in
            observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return lines
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum OCREngine: String, Equatable {
    case vision
    case liveText
}

struct OCRConfiguration: Equatable {
    let engine: OCREngine
    let recognitionLanguages: [String]
    let usesLanguageCorrection: Bool
}

struct LiveTextOCRService: TextRecognizing {
    func recognizeText(from imageURL: URL, configuration: OCRConfiguration) async throws -> String {
        guard
            let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(
                domain: "AppleLocalOCR",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Could not decode input image for Live Text OCR."]
            )
        }

        var analyzerConfiguration = ImageAnalyzer.Configuration([.text])
        if !configuration.recognitionLanguages.isEmpty {
            analyzerConfiguration.locales = configuration.recognitionLanguages
        }

        let analyzer = ImageAnalyzer()
        let analysis = try await analyzer.analyze(cgImage, orientation: .up, configuration: analyzerConfiguration)

        return analysis.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
