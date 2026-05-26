import AppKit
import Combine

struct ShelfFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let icon: NSImage
    let isTemp: Bool

    init(url: URL, isTemp: Bool = false) {
        self.url = url
        self.isTemp = isTemp
        if url.scheme == "http" || url.scheme == "https" {
            self.name = url.host ?? url.absoluteString
            self.icon = NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage()
        } else if isTemp, let img = NSImage(contentsOf: url) {
            self.name = url.lastPathComponent
            self.icon = img
        } else {
            self.name = url.lastPathComponent
            self.icon = NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    static func == (lhs: ShelfFile, rhs: ShelfFile) -> Bool { lhs.id == rhs.id }
}

class ShelfViewModel: ObservableObject {
    @Published var files: [ShelfFile] = []
    private var tempURLs: [URL] = []

    func addFile(_ url: URL) {
        guard !files.contains(where: { $0.url == url }) else { return }
        files.append(ShelfFile(url: url))
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
        guard !files.contains(where: { $0.url == url }) else { return }
        files.append(ShelfFile(url: url))
    }

    func remove(_ file: ShelfFile) {
        files.removeAll { $0.id == file.id }
    }

    func clear() {
        files.removeAll()
    }

    func cleanup() {
        tempURLs.forEach { try? FileManager.default.removeItem(at: $0) }
    }
}
