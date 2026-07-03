import AppKit
import Combine
import UniformTypeIdentifiers

private enum ShelfDefaults {
    static let defaultConversionFormat = "FileBoxDefaultConversionFormat"
}

struct ShelfFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let icon: NSImage
    let isTemp: Bool
    let isImage: Bool
    let duplicateKey: String
    let duplicateKeys: Set<String>

    init(url: URL, isTemp: Bool = false) {
        self.url = url
        self.isTemp = isTemp
        self.isImage = isTemp || Self.isImageFile(url)
        self.duplicateKeys = Self.duplicateKeys(for: url)
        self.duplicateKey = duplicateKeys.sorted().first ?? Self.normalizedURLString(url)
        if url.scheme == "http" || url.scheme == "https" {
            self.name = url.host ?? url.absoluteString
            self.icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        } else if isImage, let img = NSImage(contentsOf: url) {
            self.name = url.lastPathComponent
            self.icon = img
        } else {
            self.name = url.lastPathComponent
            self.icon = Self.icon(for: url)
        }
    }

    static func == (lhs: ShelfFile, rhs: ShelfFile) -> Bool { lhs.id == rhs.id }

    static func duplicateKey(for url: URL) -> String {
        duplicateKeys(for: url).sorted().first ?? normalizedURLString(url)
    }

    static func duplicateKeys(for url: URL) -> Set<String> {
        if url.isFileURL {
            var keys = Set<String>()
            let standardized = url.standardizedFileURL
            let resolved = standardized.resolvingSymlinksInPath()
            keys.insert("path:\(normalizedPath(resolved.path(percentEncoded: false)))")

            if let fileID = resourceValue(.fileResourceIdentifierKey, for: resolved) {
                keys.insert("resource:\(fileID)")
            }

            if let contentKey = contentSignature(for: resolved) {
                keys.insert(contentKey)
            }

            let providerCleanPath = providerCleanedPath(resolved)
            if providerCleanPath != normalizedPath(resolved.path(percentEncoded: false)) {
                keys.insert("provider-path:\(providerCleanPath)")
            }

            return keys
        }
        return [normalizedURLString(url)]
    }

    private static func normalizedURLString(_ url: URL) -> String {
        "url:\(url.standardized.absoluteString.precomposedStringWithCanonicalMapping.lowercased())"
    }

    private static func normalizedPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func resourceValue(_ key: URLResourceKey, for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [key]),
              let value = values.allValues[key] else { return nil }
        return String(describing: value)
    }

    private static func contentSignature(for url: URL) -> String? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .localizedNameKey, .nameKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              let size = values.fileSize else { return nil }

        let name = (values.localizedName ?? values.name ?? url.lastPathComponent)
            .precomposedStringWithCanonicalMapping
            .lowercased()
        let modified = values.contentModificationDate?.timeIntervalSince1970.rounded() ?? -1
        return "content:\(name):\(size):\(Int(modified))"
    }

    private static func providerCleanedPath(_ url: URL) -> String {
        let cleaned = url.standardizedFileURL
            .resolvingSymlinksInPath()
            .pathComponents
            .filter { component in
                let lower = component.lowercased()
                if lower.contains("fileprovider") || lower.contains("file provider") { return false }
                if lower.contains("temporaryitems") || lower.contains("tmp") { return false }
                if isRandomIdentifier(lower) { return false }
                return true
            }
            .joined(separator: "/")
        return normalizedPath(cleaned)
    }

    private static func isRandomIdentifier(_ text: String) -> Bool {
        let parts = text.split(separator: "-")
        guard text.count >= 8, parts.count >= 1 else { return false }
        return parts.allSatisfy { part in
            part.count >= 4 && part.allSatisfy { char in
                char.isNumber || ("a"..."f").contains(String(char))
            }
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        guard url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    private static var iconCache: [String: NSImage] = [:]

    private static func icon(for url: URL) -> NSImage {
        let key = url.hasDirectoryPath ? "__folder" : url.pathExtension.lowercased()
        if let cached = iconCache[key] { return cached }
        let type = url.hasDirectoryPath ? UTType.folder : (UTType(filenameExtension: url.pathExtension) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        iconCache[key] = icon
        return icon
    }
}

class ShelfViewModel: ObservableObject {
    @Published var files: [ShelfFile] = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var usesCustomPosition = false
    @Published var activeFileID: UUID?
    @Published private(set) var convertingFileIDs: Set<UUID> = []
    @Published var conversionMessage: String?
    @Published var defaultConversionFormat: ConversionFormat? {
        didSet { persistDefaultConversionFormat() }
    }

    private let conversionService: ImageConversionService
    private let userDefaults: UserDefaults
    private let conversionQueue = DispatchQueue(label: "com.jakob.filebox.image-conversion", qos: .userInitiated)
    private var tempURLs: [URL] = []

    init(
        conversionService: ImageConversionService = ImageConversionService(),
        userDefaults: UserDefaults = .standard
    ) {
        self.conversionService = conversionService
        self.userDefaults = userDefaults
        if let rawValue = userDefaults.string(forKey: ShelfDefaults.defaultConversionFormat) {
            self.defaultConversionFormat = ConversionFormat(rawValue: rawValue)
        } else {
            self.defaultConversionFormat = nil
        }
    }

    var activeFile: ShelfFile? {
        guard !files.isEmpty else { return nil }
        if let activeFileID, let active = files.first(where: { $0.id == activeFileID }) {
            return active
        }
        return files.last
    }

    var availableDefaultConversionFormats: [ConversionFormat] {
        conversionService.writableFormats
    }

    func addFile(_ url: URL) {
        addFiles([url])
    }

    @discardableResult
    func addFiles(_ urls: [URL]) -> [ShelfFile] {
        var seen = Set(files.flatMap(\.duplicateKeys))
        let newFiles = urls.compactMap { url -> ShelfFile? in
            let file = ShelfFile(url: url)
            guard seen.isDisjoint(with: file.duplicateKeys) else { return nil }
            seen.formUnion(file.duplicateKeys)
            return file
        }
        guard !newFiles.isEmpty else { return [] }
        files.append(contentsOf: newFiles)
        activeFileID = newFiles.last?.id
        applyDefaultConversion(to: newFiles)
        return newFiles
    }

    func addImage(_ image: NSImage) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBox_\(UUID().uuidString).png")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return }
        tempURLs.append(url)
        let file = ShelfFile(url: url, isTemp: true)
        files.append(file)
        activeFileID = file.id
        applyDefaultConversion(to: [file])
    }

    func addURL(_ url: URL) {
        addFiles([url])
    }

    func remove(_ file: ShelfFile) {
        files.removeAll { $0.id == file.id }
        selectedIDs.remove(file.id)
        convertingFileIDs.remove(file.id)
        if activeFileID == file.id {
            activeFileID = files.last?.id
        }
    }

    func clear() {
        files.removeAll()
        selectedIDs.removeAll()
        activeFileID = nil
        convertingFileIDs.removeAll()
        conversionMessage = nil
    }

    func toggleSelection(_ file: ShelfFile) {
        activeFileID = file.id
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    func selectAll() {
        selectedIDs = Set(files.map(\.id))
        activeFileID = files.last?.id
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func filesForDrag(startingWith file: ShelfFile) -> [ShelfFile] {
        if selectedIDs.contains(file.id) {
            let selected = files.filter { selectedIDs.contains($0.id) }
            return selected.isEmpty ? [file] : selected
        }
        return [file]
    }

    func activate(_ file: ShelfFile) {
        activeFileID = file.id
    }

    func currentFormatLabel(for file: ShelfFile) -> String {
        conversionService.currentFormatLabel(for: file.url)
    }

    func conversionOptions(for file: ShelfFile) -> [ConversionFormat] {
        conversionService.supportedOutputFormats(for: file.url)
    }

    func isConverting(_ file: ShelfFile) -> Bool {
        convertingFileIDs.contains(file.id)
    }

    func convert(fileID: UUID, to format: ConversionFormat) {
        guard let sourceFile = files.first(where: { $0.id == fileID }),
              !convertingFileIDs.contains(fileID) else { return }

        guard conversionOptions(for: sourceFile).contains(format) else {
            conversionMessage = "No \(format.displayName) copy available"
            return
        }

        activeFileID = fileID
        conversionMessage = nil
        convertingFileIDs.insert(fileID)

        conversionQueue.async { [weak self] in
            guard let self else { return }

            do {
                let convertedURL = try self.conversionService.convert(sourceFile.url, to: format)
                DispatchQueue.main.async {
                    self.finishConversion(convertedURL, after: fileID)
                }
            } catch {
                DispatchQueue.main.async {
                    self.convertingFileIDs.remove(fileID)
                    self.conversionMessage = "Could not convert to \(format.displayName)"
                }
            }
        }
    }

    func insertConvertedFile(_ url: URL, after sourceID: UUID) {
        finishConversion(url, after: sourceID)
    }

    func cleanup() {
        tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    private func finishConversion(_ url: URL, after sourceID: UUID) {
        convertingFileIDs.remove(sourceID)
        tempURLs.append(url)

        let converted = ShelfFile(url: url, isTemp: true)
        if let sourceIndex = files.firstIndex(where: { $0.id == sourceID }) {
            files.insert(converted, at: min(sourceIndex + 1, files.endIndex))
        } else {
            files.append(converted)
        }

        activeFileID = converted.id
        conversionMessage = "Created \(converted.name)"
    }

    private func applyDefaultConversion(to newFiles: [ShelfFile]) {
        guard let defaultConversionFormat else { return }
        for file in newFiles where conversionOptions(for: file).contains(defaultConversionFormat) {
            convert(fileID: file.id, to: defaultConversionFormat)
        }
    }

    private func persistDefaultConversionFormat() {
        if let defaultConversionFormat {
            userDefaults.set(defaultConversionFormat.rawValue, forKey: ShelfDefaults.defaultConversionFormat)
        } else {
            userDefaults.removeObject(forKey: ShelfDefaults.defaultConversionFormat)
        }
    }
}
