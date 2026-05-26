import AppKit
import Combine

// Drag-pasteboard types that indicate something worth shelving is being dragged.
private let shelvableTypes: [NSPasteboard.PasteboardType] = [
    .init("public.file-url"),
    .init("com.apple.pasteboard.promised-file-url"),
    .init("public.image"),
    .init("public.tiff"),
    .init("public.png"),
    .init("public.jpeg"),
    .init("public.url"),
]

class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel!
    private let shelf = ShelfViewModel()
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    // Drag-show state
    private var mouseDownMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var hideTimer: Timer?
    private var isDragging = false

    // Accumulated cursor travel since the last mouse-down.
    // The panel only surfaces once this exceeds the threshold — filtering out
    // sloppy clicks where the mouse moves a pixel or two before release.
    private var travelSinceDown: CGFloat = 0
    private let activationTravel: CGFloat = 8   // logical points

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupMenuBar()
        setupDragMonitors()
        setupHotKey()
        observeShelf()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shelf.cleanup()
    }

    // MARK: - Panel setup

    private func setupPanel() {
        panel = FloatingPanel(shelf: shelf)
        // Place at top-right once; position is never re-derived after this.
        if let screen = NSScreen.main {
            let w: CGFloat = 240
            let x = screen.visibleFrame.maxX - w - 16
            let y = screen.visibleFrame.maxY - 60 - 8
            panel.setFrame(NSRect(x: x, y: y, width: w, height: 60), display: false)
        }
        // Hidden until a drag is detected.
    }

    // Resize panel height while keeping its top edge pinned in place.
    private func animateHeight(to newHeight: CGFloat) {
        var frame = panel.frame
        frame.origin.y = frame.maxY - newHeight   // keep top edge fixed
        frame.size.height = newHeight
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.26
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func idealHeight(for count: Int) -> CGFloat {
        count == 0 ? 60 : min(CGFloat(40 + count * 36), 340)
    }

    private func observeShelf() {
        shelf.$files
            .receive(on: RunLoop.main)
            .sink { [weak self] files in
                guard let self else { return }
                self.animateHeight(to: self.idealHeight(for: files.count))
                if !files.isEmpty {
                    // Keep panel visible whenever it holds files.
                    self.hideTimer?.invalidate()
                    if !self.panel.isVisible { self.panel.showAnimated() }
                } else if !self.isDragging {
                    self.panel.hideAnimated()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Drag detection
    //
    // NSEvent global monitors fire on a private queue; dispatch back to main.
    // Input Monitoring permission is needed; macOS prompts automatically on first use.

    private func setupDragMonitors() {
        // Reset travel counter on every fresh press.
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.travelSinceDown = 0 }
        }

        // Accumulate distance; show only after the cursor has genuinely moved.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            DispatchQueue.main.async {
                guard let self, !self.isDragging else { return }
                self.travelSinceDown += sqrt(event.deltaX * event.deltaX + event.deltaY * event.deltaY)
                guard self.travelSinceDown >= self.activationTravel else { return }
                self.handleDragEvent()
            }
        }

        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            DispatchQueue.main.async { self?.handleMouseUp() }
        }
    }

    private func handleDragEvent() {
        // Only surface the panel for drags that carry files, images, or URLs.
        let dragBoard = NSPasteboard(name: .drag)
        guard let types = dragBoard.types,
              types.contains(where: { shelvableTypes.contains($0) }) else { return }

        isDragging = true
        hideTimer?.invalidate()
        panel.showAnimated()
    }

    private func handleMouseUp() {
        isDragging = false
        travelSinceDown = 0
        // Give the user a moment to see the panel, then hide if nothing was dropped.
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            guard let self, self.shelf.files.isEmpty else { return }
            self.panel.hideAnimated()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray.2.fill", accessibilityDescription: "FileBox")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Grab Finder Selection  ⌥G", action: #selector(grabFinderSelection), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Panel", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear All", action: #selector(clearAll), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit FileBox", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func showPanel() { panel.showAnimated() }
    @objc private func clearAll() { shelf.clear() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func grabFinderSelection() {
        grabFinderFiles()
        panel.showAnimated()
    }

    // MARK: - Global hot key (⌥G)

    private func setupHotKey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
                  event.keyCode == 5 else { return }
            DispatchQueue.main.async {
                self?.grabFinderFiles()
                self?.panel.showAnimated()
            }
        }
    }

    // MARK: - Finder integration

    private func grabFinderFiles() {
        let src = """
        tell application "Finder"
            set sel to selection as alias list
            set out to {}
            repeat with f in sel
                set end of out to POSIX path of f
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let result = NSAppleScript(source: src)?.executeAndReturnError(&err),
              err == nil, result.numberOfItems > 0 else { return }
        for i in 1...result.numberOfItems {
            if let path = result.atIndex(i)?.stringValue {
                shelf.addFile(URL(fileURLWithPath: path))
            }
        }
    }
}
