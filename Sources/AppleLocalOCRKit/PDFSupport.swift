#if os(macOS)
import AppKit
import Foundation
import PDFKit

struct PageSelection: Equatable {
    let ranges: [ClosedRange<Int>]

    func contains(_ pageNumber: Int) -> Bool {
        ranges.contains { $0.contains(pageNumber) }
    }

    static func parse(_ raw: String) throws -> PageSelection {
        let components = raw
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !components.isEmpty else {
            throw NSError(
                domain: "AppleLocalOCR",
                code: 2101,
                userInfo: [NSLocalizedDescriptionKey: "Page range cannot be empty."]
            )
        }

        let ranges = try components.map { component -> ClosedRange<Int> in
            if let value = Int(component), value > 0 {
                return value...value
            }

            let parts = component.split(separator: "-", maxSplits: 1).map(String.init)
            guard
                parts.count == 2,
                let start = Int(parts[0]),
                let end = Int(parts[1]),
                start > 0,
                end >= start
            else {
                throw NSError(
                    domain: "AppleLocalOCR",
                    code: 2102,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid page range component: \(component)"]
                )
            }

            return start...end
        }

        return PageSelection(ranges: ranges)
    }
}

struct RenderedPDFPage {
    let pageNumber: Int
    let imageURL: URL
}

struct RenderedPDFDocument {
    let pages: [RenderedPDFPage]
    let temporaryDirectory: URL
}

struct PDFRenderer {
    func renderDocument(at pdfURL: URL, selectedPages: PageSelection?) throws -> RenderedPDFDocument {
        guard let document = PDFDocument(url: pdfURL) else {
            throw NSError(
                domain: "AppleLocalOCR",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "Could not open PDF document."]
            )
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apple-local-ocr-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        var renderedPages: [RenderedPDFPage] = []
        for pageIndex in 0..<document.pageCount {
            let pageNumber = pageIndex + 1
            if let selectedPages, !selectedPages.contains(pageNumber) {
                continue
            }

            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let renderedImage = pageImage(for: page)
            let outputURL = temporaryDirectory.appendingPathComponent(
                String(format: "page-%04d.png", pageNumber),
                isDirectory: false
            )
            try writePNG(image: renderedImage, to: outputURL)
            renderedPages.append(RenderedPDFPage(pageNumber: pageNumber, imageURL: outputURL))
        }

        return RenderedPDFDocument(pages: renderedPages, temporaryDirectory: temporaryDirectory)
    }

    private func pageImage(for page: PDFPage) -> NSImage {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = NSSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
        return page.thumbnail(of: size, for: .mediaBox)
    }

    private func writePNG(image: NSImage, to url: URL) throws {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw NSError(
                domain: "AppleLocalOCR",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: "Could not render PDF page as PNG."]
            )
        }

        try png.write(to: url)
    }
}
#endif
