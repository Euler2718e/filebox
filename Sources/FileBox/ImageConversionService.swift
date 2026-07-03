import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ConversionFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case heic
    case tiff
    case gif
    case bmp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .png: return UTType.png.identifier
        case .jpeg: return UTType.jpeg.identifier
        case .heic: return UTType.heic.identifier
        case .tiff: return UTType.tiff.identifier
        case .gif: return UTType.gif.identifier
        case .bmp: return "com.microsoft.bmp"
        }
    }

    static func matching(typeIdentifier: String) -> ConversionFormat? {
        allCases.first { $0.typeIdentifier == typeIdentifier }
    }

    static func matching(filenameExtension: String) -> ConversionFormat? {
        switch filenameExtension.lowercased() {
        case "png": return .png
        case "jpg", "jpeg", "jpe": return .jpeg
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "gif": return .gif
        case "bmp": return .bmp
        default: return nil
        }
    }
}

enum ImageConversionError: Error, LocalizedError {
    case unsupportedInput
    case unsupportedOutput
    case cannotCreateOutputDirectory
    case cannotCreateDestination
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedInput:
            return "Unsupported image"
        case .unsupportedOutput:
            return "Unsupported output format"
        case .cannotCreateOutputDirectory:
            return "Could not prepare conversion folder"
        case .cannotCreateDestination:
            return "Could not create converted file"
        case .conversionFailed:
            return "Could not convert image"
        }
    }
}

final class ImageConversionService {
    private let fileManager: FileManager
    private let outputDirectory: URL

    init(
        outputDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBoxConversions", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.outputDirectory = outputDirectory
        self.fileManager = fileManager
    }

    var writableFormats: [ConversionFormat] {
        let writableIdentifiers = Set((CGImageDestinationCopyTypeIdentifiers() as! [String]))
        return ConversionFormat.allCases.filter { writableIdentifiers.contains($0.typeIdentifier) }
    }

    private var readableIdentifiers: Set<String> {
        Set(CGImageSourceCopyTypeIdentifiers() as! [String])
    }

    func canReadImage(at url: URL) -> Bool {
        guard url.isFileURL, !isDirectory(url) else { return false }
        guard let source = imageSource(for: url),
              CGImageSourceGetCount(source) > 0,
              let typeIdentifier = CGImageSourceGetType(source) as String?
        else { return false }
        return readableIdentifiers.contains(typeIdentifier)
    }

    func currentFormat(for url: URL) -> ConversionFormat? {
        if let typeIdentifier = typeIdentifier(for: url),
           let format = ConversionFormat.matching(typeIdentifier: typeIdentifier) {
            return format
        }
        return ConversionFormat.matching(filenameExtension: url.pathExtension)
    }

    func currentFormatLabel(for url: URL) -> String {
        if let format = currentFormat(for: url) {
            return format.displayName
        }

        if let typeIdentifier = typeIdentifier(for: url),
           let type = UTType(typeIdentifier),
           let extensionLabel = type.preferredFilenameExtension?.uppercased() {
            return extensionLabel
        }

        let extensionLabel = url.pathExtension.uppercased()
        return extensionLabel.isEmpty ? "Unknown" : extensionLabel
    }

    func supportedOutputFormats(for url: URL) -> [ConversionFormat] {
        guard canReadImage(at: url) else { return [] }
        let current = currentFormat(for: url)
        return writableFormats.filter { $0 != current }
    }

    func convert(_ sourceURL: URL, to format: ConversionFormat) throws -> URL {
        guard canReadImage(at: sourceURL), let source = imageSource(for: sourceURL) else {
            throw ImageConversionError.unsupportedInput
        }

        guard writableFormats.contains(format) else {
            throw ImageConversionError.unsupportedOutput
        }

        try prepareOutputDirectory()
        let destinationURL = uniqueDestinationURL(for: sourceURL, format: format)

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            format.typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.cannotCreateDestination
        }

        let options = destinationOptions(for: format)
        CGImageDestinationAddImageFromSource(destination, source, 0, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            try? fileManager.removeItem(at: destinationURL)
            throw ImageConversionError.conversionFailed
        }

        return destinationURL
    }

    private func imageSource(for url: URL) -> CGImageSource? {
        CGImageSourceCreateWithURL(url as CFURL, nil)
    }

    private func typeIdentifier(for url: URL) -> String? {
        guard let source = imageSource(for: url) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func prepareOutputDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ImageConversionError.cannotCreateOutputDirectory
        }
    }

    private func uniqueDestinationURL(for sourceURL: URL, format: ConversionFormat) -> URL {
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = outputDirectory.appendingPathComponent(basename)
            .appendingPathExtension(format.fileExtension)
        var index = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = outputDirectory.appendingPathComponent("\(basename) \(index)")
                .appendingPathExtension(format.fileExtension)
            index += 1
        }

        return candidate
    }

    private func destinationOptions(for format: ConversionFormat) -> [CFString: Any] {
        switch format {
        case .jpeg, .heic:
            return [kCGImageDestinationLossyCompressionQuality: 0.92]
        case .png, .tiff, .gif, .bmp:
            return [:]
        }
    }
}
