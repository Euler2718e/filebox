import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let icon: NSImage
    let isTemp: Bool
    let duplicateKey: String
    let duplicateKeys: Set<String>

    init(url: URL, isTemp: Bool = false) {
        self.url = url
        self.isTemp = isTemp
        self.duplicateKeys = Self.duplicateKeys(for: url)
        self.duplicateKey = duplicateKeys.sorted().first ?? Self.normalizedURLString(url)
        if url.scheme == "http" || url.scheme == "https" {
            self.name = url.host ?? url.absoluteString
            self.icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        } else if isTemp, let img = NSImage(contentsOf: url) {
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
    private var tempURLs: [URL] = []

    func addFile(_ url: URL) {
        addFiles([url])
    }

    func addFiles(_ urls: [URL]) {
        var seen = Set(files.flatMap(\.duplicateKeys))
        let newFiles = urls.compactMap { url -> ShelfFile? in
            let file = ShelfFile(url: url)
            guard seen.isDisjoint(with: file.duplicateKeys) else { return nil }
            seen.formUnion(file.duplicateKeys)
            return file
        }
        guard !newFiles.isEmpty else { return }
        files.append(contentsOf: newFiles)
    }

    func addImage(_ image: NSImage) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileBox_\(UUID().uuidString).png")
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else { return }
        tempURLs.append(url)
        files.append(ShelfFile(url: url, isTemp: true))
    }

    func addURL(_ url: URL) {
        addFiles([url])
    }

    func remove(_ file: ShelfFile) {
        files.removeAll { $0.id == file.id }
        selectedIDs.remove(file.id)
    }

    func clear() {
        files.removeAll()
        selectedIDs.removeAll()
    }

    func toggleSelection(_ file: ShelfFile) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    func selectAll() {
        selectedIDs = Set(files.map(\.id))
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

    func cleanup() {
        tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
