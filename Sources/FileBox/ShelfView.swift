import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ShelfView: View {
    @ObservedObject var shelf: ShelfViewModel
    @State private var isDragTargeted = false

    private let bg = Color(red: 0.10, green: 0.10, blue: 0.12, opacity: 0.94)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(bg)
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isDragTargeted ? Color.white.opacity(0.40) : Color.white.opacity(0.10),
                    lineWidth: 1
                )

            VStack(alignment: .leading, spacing: 0) {
                header
                if shelf.files.isEmpty {
                    emptyHint
                } else {
                    fileList
                }
            }
        }
        .onDrop(of: [.fileURL, .image, .tiff, .png, .jpeg, .url], isTargeted: $isDragTargeted, perform: handleDrop)
        .animation(.spring(response: 0.26, dampingFraction: 0.80), value: isDragTargeted)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub-views

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("FileBox")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !shelf.files.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if shelf.selectedIDs.count == shelf.files.count {
                            shelf.clearSelection()
                        } else {
                            shelf.selectAll()
                        }
                    }
                } label: {
                    Image(systemName: shelf.selectedIDs.count == shelf.files.count ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(shelf.selectedIDs.count == shelf.files.count ? "Deselect all" : "Select all")

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { shelf.clear() }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, shelf.files.isEmpty ? 8 : 6)
        .background(WindowMoveHandle())   // drag this strip to reposition the panel
    }

    private var emptyHint: some View {
        Text(isDragTargeted ? "Release to add" : "Drop here  ·  ⌥G for Finder selection")
            .font(.system(size: 10))
            .foregroundStyle(isDragTargeted ? Color.white.opacity(0.55) : Color.white.opacity(0.25))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
    }

    private var fileList: some View {
        VStack(spacing: 2) {
            ForEach(shelf.files) { file in
                FileRowView(
                    file: file,
                    isSelected: shelf.selectedIDs.contains(file.id),
                    dragFiles: shelf.filesForDrag(startingWith: file),
                    onToggleSelection: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            shelf.toggleSelection(file)
                        }
                    },
                    onRemove: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        shelf.remove(file)
                    }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
        .padding(.bottom, 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: shelf.files.map(\.id))
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var urlProviders: [(NSItemProvider, String)] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                urlProviders.append((provider, UTType.fileURL.identifier))
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                loadImage(from: provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                urlProviders.append((provider, UTType.url.identifier))
            }
        }
        loadURLs(from: urlProviders)
        return true
    }

    private func loadURLs(from providers: [(NSItemProvider, String)]) {
        guard !providers.isEmpty else { return }
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for (provider, typeIdentifier) in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let url = url(from: item) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            var seen = Set<String>()
            let uniqueURLs = urls.filter { url in
                let key = ShelfFile.duplicateKey(for: url)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
            guard !uniqueURLs.isEmpty else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                    shelf.addFiles(uniqueURLs)
                }
            }
        }
    }

    private func loadImage(from provider: NSItemProvider) {
        provider.loadObject(ofClass: NSImage.self) { reading, _ in
            guard let image = reading as? NSImage else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { shelf.addImage(image) }
            }
        }
    }

    private func url(from item: NSSecureCoding?) -> URL? {
        if let u = item as? URL { return u }
        if let d = item as? Data { return URL(dataRepresentation: d, relativeTo: nil, isAbsolute: true) }
        if let s = item as? String { return URL(string: s) ?? URL(fileURLWithPath: s) }
        if let s = item as? NSString { return URL(string: s as String) ?? URL(fileURLWithPath: s as String) }
        return nil
    }
}

// MARK: - Window drag handle
//
// Applied only to the header strip. isMovableByWindowBackground is false on the panel,
// so ONLY views that return mouseDownCanMoveWindow = true can move it. File rows do not
// get this, so dragging a file out never accidentally drags the window.

struct WindowMoveHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ nsView: HandleView, context: Context) {}

    class HandleView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - File row

struct FileRowView: View {
    let file: ShelfFile
    let isSelected: Bool
    let dragFiles: [ShelfFile]
    let onToggleSelection: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Deselect" : "Select")

            ZStack {
                HStack(spacing: 9) {
                    Image(nsImage: file.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: file.isTemp ? 4 : 0))

                    Text(file.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                MultiFileDragSource(files: dragFiles)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white.opacity(0.45), Color.white.opacity(0.12))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isSelected ? 0.10 : (isHovered ? 0.06 : 0)))
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

struct MultiFileDragSource: NSViewRepresentable {
    let files: [ShelfFile]

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.files = files
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        nsView.files = files
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var files: [ShelfFile] = []
        private var mouseDownEvent: NSEvent?

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            super.mouseDown(with: event)
        }

        override func mouseDragged(with event: NSEvent) {
            guard !files.isEmpty, let mouseDownEvent else { return }
            let distance = hypot(event.locationInWindow.x - mouseDownEvent.locationInWindow.x,
                                 event.locationInWindow.y - mouseDownEvent.locationInWindow.y)
            guard distance >= 3 else { return }

            let draggingItems = files.map { file -> NSDraggingItem in
                let item = NSDraggingItem(pasteboardWriter: file.url as NSURL)
                let icon = file.icon
                let size = NSSize(width: 32, height: 32)
                let origin = NSPoint(
                    x: mouseDownEvent.locationInWindow.x - size.width / 2,
                    y: mouseDownEvent.locationInWindow.y - size.height / 2
                )
                item.setDraggingFrame(NSRect(origin: origin, size: size), contents: icon)
                return item
            }
            beginDraggingSession(with: draggingItems, event: mouseDownEvent, source: self)
            self.mouseDownEvent = nil
        }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .move] : .copy
        }
    }
}
