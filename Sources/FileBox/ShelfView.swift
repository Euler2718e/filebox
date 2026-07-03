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

            content
        }
        .onDrop(of: [.fileURL, .image, .tiff, .png, .jpeg, .url], isTargeted: $isDragTargeted, perform: handleDrop)
        .animation(.spring(response: 0.26, dampingFraction: 0.80), value: isDragTargeted)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub-views

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if shelf.files.isEmpty {
                emptyHint
            } else {
                HStack(alignment: .top, spacing: 0) {
                    fileList
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    Divider()
                        .background(Color.white.opacity(0.10))
                        .padding(.vertical, 4)

                    inspector
                        .frame(width: 128, alignment: .topLeading)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("FileBox")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            defaultFormatMenu

            PositionDragHandle(isActive: shelf.usesCustomPosition)
                .frame(width: 18, height: 18)
                .help("Hold and drag to set FileBox position")

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
    }

    private var defaultFormatMenu: some View {
        Menu {
            Button {
                shelf.defaultConversionFormat = nil
            } label: {
                Label("Original", systemImage: shelf.defaultConversionFormat == nil ? "checkmark" : "circle")
            }

            Divider()

            ForEach(shelf.availableDefaultConversionFormats) { format in
                Button {
                    shelf.defaultConversionFormat = format
                } label: {
                    Label(format.displayName, systemImage: shelf.defaultConversionFormat == format ? "checkmark" : "circle")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text(shelf.defaultConversionFormat?.displayName ?? "Original")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Default conversion format")
    }

    private var emptyHint: some View {
        Text(isDragTargeted ? "Release to add" : "Drop here  ·  ⌘⌥G for Finder selection")
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
                    isActive: shelf.activeFile?.id == file.id,
                    dragFiles: shelf.filesForDrag(startingWith: file),
                    onToggleSelection: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            shelf.toggleSelection(file)
                        }
                    },
                    onActivate: {
                        shelf.activate(file)
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

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let file = shelf.activeFile {
                Text("Current")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                HStack(spacing: 5) {
                    Image(nsImage: file.icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: file.isImage ? 3 : 0))

                    Text(shelf.currentFormatLabel(for: file))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if shelf.isConverting(file) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                        Text("Converting")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    convertMenu(for: file)
                }

                if let message = shelf.conversionMessage {
                    Text(message)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func convertMenu(for file: ShelfFile) -> some View {
        let formats = shelf.conversionOptions(for: file)

        return Group {
            if formats.isEmpty {
                Text("No conversion")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Menu {
                    ForEach(formats) { format in
                        Button(format.displayName) {
                            shelf.convert(fileID: file.id, to: format)
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Convert to")
                            .font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                    _ = shelf.addFiles(uniqueURLs)
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

// MARK: - Position drag handle

struct PositionDragHandle: NSViewRepresentable {
    let isActive: Bool

    func makeNSView(context: Context) -> HandleView {
        let view = HandleView()
        view.isActive = isActive
        return view
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.isActive = isActive
    }

    final class HandleView: NSView {
        var isActive = false {
            didSet { needsDisplay = true }
        }
        private var mouseDownScreenPoint: NSPoint?
        private var initialWindowFrame: NSRect?

        override var acceptsFirstResponder: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            let image = NSImage(
                systemSymbolName: isActive ? "mappin.circle.fill" : "mappin.circle",
                accessibilityDescription: "Set FileBox position"
            )
            image?.isTemplate = true
            let color = isActive ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.35)
            color.set()
            image?.draw(
                in: bounds.insetBy(dx: 1, dy: 1),
                from: .zero,
                operation: .sourceAtop,
                fraction: 1
            )
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            mouseDownScreenPoint = window.convertPoint(toScreen: event.locationInWindow)
            initialWindowFrame = window.frame
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            NotificationCenter.default.post(name: .fileBoxCustomPositionDragBegan, object: nil)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window,
                  let start = mouseDownScreenPoint,
                  let initial = initialWindowFrame
            else { return }
            let current = window.convertPoint(toScreen: event.locationInWindow)
            let delta = NSPoint(x: current.x - start.x, y: current.y - start.y)
            window.setFrameOrigin(NSPoint(x: initial.origin.x + delta.x, y: initial.origin.y + delta.y))
        }

        override func mouseUp(with event: NSEvent) {
            guard let window else { return }
            NotificationCenter.default.post(
                name: .fileBoxCustomPositionDidChange,
                object: NSValue(rect: window.frame)
            )
            mouseDownScreenPoint = nil
            initialWindowFrame = nil
        }
    }
}

private extension Notification.Name {
    static let fileBoxCustomPositionDragBegan = Notification.Name("FileBoxCustomPositionDragBegan")
    static let fileBoxCustomPositionDidChange = Notification.Name("FileBoxCustomPositionDidChange")
}

// MARK: - File row

struct FileRowView: View {
    let file: ShelfFile
    let isSelected: Bool
    let isActive: Bool
    let dragFiles: [ShelfFile]
    let onToggleSelection: () -> Void
    let onActivate: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            Button {
                onActivate()
                onToggleSelection()
            } label: {
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
                        .clipShape(RoundedRectangle(cornerRadius: file.isImage ? 4 : 0))

                    Text(file.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onActivate)
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
                .fill(rowBackground)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.10) }
        if isActive { return Color.accentColor.opacity(0.13) }
        if isHovered { return Color.white.opacity(0.06) }
        return Color.clear
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
