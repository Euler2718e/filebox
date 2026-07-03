import AppKit
import XCTest
@testable import FileBox

final class ImageConversionTests: XCTestCase {
    private var tempDirectory: URL!
    private var conversionDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBoxTests-\(UUID().uuidString)", isDirectory: true)
        conversionDirectory = tempDirectory
            .appendingPathComponent("Converted", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    func testSupportedOutputFilteringExcludesCurrentFormat() throws {
        let pngURL = try writeImage(named: "File123.png", as: .png)
        let service = makeService()

        let formats = service.supportedOutputFormats(for: pngURL)

        XCTAssertFalse(formats.contains(.png))
        XCTAssertTrue(formats.contains(.jpeg))
    }

    func testConvertsPNGToJPEGWithOriginalBaseName() throws {
        let pngURL = try writeImage(named: "File123.png", as: .png)
        let service = makeService()

        let convertedURL = try service.convert(pngURL, to: .jpeg)

        XCTAssertEqual(convertedURL.lastPathComponent, "File123.jpg")
        XCTAssertEqual(service.currentFormat(for: convertedURL), .jpeg)
    }

    func testConvertsJPEGToPNG() throws {
        let jpegURL = try writeImage(named: "File123.jpg", as: .jpeg)
        let service = makeService()

        let convertedURL = try service.convert(jpegURL, to: .png)

        XCTAssertEqual(convertedURL.lastPathComponent, "File123.png")
        XCTAssertEqual(service.currentFormat(for: convertedURL), .png)
    }

    func testDefaultConversionSkipsSameFormat() throws {
        let pngURL = try writeImage(named: "Source.png", as: .png)
        let shelf = makeShelf()
        shelf.defaultConversionFormat = .png

        let inserted = shelf.addFiles([pngURL])

        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(shelf.files.map(\.name), ["Source.png"])
        XCTAssertTrue(shelf.convertingFileIDs.isEmpty)
    }

    func testDefaultConversionCreatesCopyBelowSource() throws {
        let jpegURL = try writeImage(named: "Source.jpg", as: .jpeg)
        let shelf = makeShelf()
        shelf.defaultConversionFormat = .png

        _ = shelf.addFiles([jpegURL])

        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in shelf.files.count == 2 },
            object: nil
        )
        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(shelf.files.map(\.name), ["Source.jpg", "Source.png"])
    }

    func testUnsupportedFileHasNoConversionOptions() throws {
        let textURL = tempDirectory.appendingPathComponent("notes.txt")
        try "plain text".write(to: textURL, atomically: true, encoding: .utf8)
        let service = makeService()

        XCTAssertEqual(service.supportedOutputFormats(for: textURL), [])
    }

    func testConvertedItemInsertsAfterSourceFile() throws {
        let firstURL = try writeImage(named: "First.png", as: .png)
        let secondURL = try writeImage(named: "Second.png", as: .png)
        let convertedURL = try writeImage(named: "First.jpg", as: .jpeg)
        let shelf = makeShelf()

        let inserted = shelf.addFiles([firstURL, secondURL])
        shelf.insertConvertedFile(convertedURL, after: try XCTUnwrap(inserted.first?.id))

        XCTAssertEqual(shelf.files.map(\.name), ["First.png", "First.jpg", "Second.png"])
    }

    private func makeService() -> ImageConversionService {
        ImageConversionService(outputDirectory: conversionDirectory)
    }

    private func makeShelf() -> ShelfViewModel {
        let suiteName = "FileBoxTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ShelfViewModel(conversionService: makeService(), userDefaults: defaults)
    }

    private func writeImage(named name: String, as fileType: NSBitmapImageRep.FileType) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        let image = NSImage(size: NSSize(width: 10, height: 10))

        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()

        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let data = try XCTUnwrap(bitmap.representation(using: fileType, properties: [:]))
        try data.write(to: url)
        return url
    }
}
