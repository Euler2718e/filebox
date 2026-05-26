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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { shelf.clear() }
                } label: {
                    Text("Clear")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
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
                FileRowView(file: file) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                        shelf.remove(file)
                    }
                }
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
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                loadFileURL(from: provider)
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                loadImage(from: provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                loadURL(from: provider)
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let url = url(from: item) else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { shelf.addFile(url) }
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

    private func loadURL(from provider: NSItemProvider) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
            guard let u = url(from: item) else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { shelf.addURL(u) }
            }
        }
    }

    private func url(from item: NSSecureCoding?) -> URL? {
        if let u = item as? URL { return u }
        if let d = item as? Data { return URL(dataRepresentation: d, relativeTo: nil, isAbsolute: true) }
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
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
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
                .fill(Color.white.opacity(isHovered ? 0.06 : 0))
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .onDrag { NSItemProvider(object: file.url as NSURL) }
    }
}
