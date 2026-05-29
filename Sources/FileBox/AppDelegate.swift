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

    // Collision avoidance & multi-monitor
    private var homeAnchor = CGPoint.zero   // fixed top-right corner of panel's intended position
    private var isDodging = false
    private var collisionTimer: Timer?
    private var collisionCheckInFlight = false   // prevents stacking background scans
    private var workspaceObserver: Any?
    private var dodgeHoldUntil = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupPanel()
        setupMenuBar()
        setupDragMonitors()
        setupHotKey()
        observeShelf()
        setupWorkspaceObserver()
        collisionTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            self?.followActiveScreen(preferMouse: self?.isDragging == true)
            self?.checkAndDodge()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shelf.cleanup()
        collisionTimer?.invalidate()
        if let obs = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Panel setup

    private func setupPanel() {
        panel = FloatingPanel(shelf: shelf)
        if let screen = activeContextScreen(preferMouse: false) ?? NSScreen.main {
            setHome(on: screen)
        }
        homeAnchor = CGPoint(x: panel.frame.maxX, y: panel.frame.maxY)
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
        // Once dragging is active, also track screen crossings in real time.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isDragging {
                    self.followActiveScreen(preferMouse: true)
                    return
                }
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
        // Snap to the active context so the shelf appears on the monitor being used.
        if let screen = activeContextScreen(preferMouse: true) {
            moveToScreen(screen, animated: false)
        }
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

    @objc private func showPanel() {
        if let screen = activeContextScreen(preferMouse: false) {
            moveToScreen(screen, animated: false)
        }
        panel.showAnimated()
    }
    @objc private func clearAll() { shelf.clear() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func grabFinderSelection() {
        grabFinderFiles()
        if let screen = activeContextScreen(preferMouse: false) {
            moveToScreen(screen, animated: false)
        }
        panel.showAnimated()
    }

    // MARK: - Global hot key (⌥G)

    private func setupHotKey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option,
                  event.keyCode == 5 else { return }
            DispatchQueue.main.async {
                self?.grabFinderFiles()
                if let screen = self?.activeContextScreen(preferMouse: false) {
                    self?.moveToScreen(screen, animated: false)
                }
                self?.panel.showAnimated()
            }
        }
    }

    // MARK: - Stay-on-top & multi-monitor following

    private func setupWorkspaceObserver() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.panel.isVisible else { return }
            self.followActiveScreen(preferMouse: false)
            self.panel.orderFrontRegardless()
        }
    }

    /// Moves the panel to the screen that currently contains the user's active work.
    /// No-ops instantly when already on the right screen.
    private func followActiveScreen(preferMouse: Bool) {
        guard let target = activeContextScreen(preferMouse: preferMouse) else { return }
        moveToScreen(target, animated: panel.isVisible)
    }

    private func activeContextScreen(preferMouse: Bool) -> NSScreen? {
        let mouseScreen = screenContaining(NSEvent.mouseLocation)
        if preferMouse { return mouseScreen ?? screenForFrontmostWindow() }
        return screenForFrontmostWindow() ?? mouseScreen
    }

    private func screenContaining(_ point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func screenForFrontmostWindow() -> NSScreen? {
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              frontmostPID != ProcessInfo.processInfo.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let windows = list.compactMap { info -> NSRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == frontmostPID,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0 else { return nil }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds),
                  bounds.width > 80, bounds.height > 80
            else { return nil }

            return Self.nsRect(fromCGWindowBounds: bounds, screens: NSScreen.screens)
        }

        guard let window = windows.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return nil
        }
        let midpoint = NSPoint(x: window.midX, y: window.midY)
        return screenContaining(midpoint) ?? NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(window).visibleArea < rhs.frame.intersection(window).visibleArea
        }
    }

    // MARK: - Multi-monitor

    /// Moves the panel's home position to the top-right of `screen`.
    /// Animates when the panel is already visible; silent reposition otherwise.
    private func moveToScreen(_ screen: NSScreen, animated: Bool) {
        let newFrame = frameForHome(on: screen)
        homeAnchor = CGPoint(x: newFrame.maxX, y: newFrame.maxY)
        if let cur = panel.screen, cur.frame == screen.frame {
            if isDodging { return }
            let curFrame = panel.frame
            if abs(curFrame.origin.x - newFrame.origin.x) < 1,
               abs(curFrame.origin.y - newFrame.origin.y) < 1,
               abs(curFrame.width - newFrame.width) < 1,
               abs(curFrame.height - newFrame.height) < 1 {
                return
            }
        }
        isDodging = false

        if animated && panel.isVisible {
            animateToFrame(newFrame)
        } else {
            panel.setFrame(newFrame, display: false)
        }
    }

    private func setHome(on screen: NSScreen) {
        let frame = frameForHome(on: screen)
        panel.setFrame(frame, display: false)
        homeAnchor = CGPoint(x: frame.maxX, y: frame.maxY)
    }

    private func frameForHome(on screen: NSScreen) -> NSRect {
        let w = panel.frame.width
        let h = panel.frame.height
        let newX    = screen.visibleFrame.maxX - w - 16
        let newMaxY = screen.visibleFrame.maxY - 8
        return NSRect(x: newX, y: newMaxY - h, width: w, height: h)
    }

    // MARK: - Collision avoidance

    // Returns the panel's intended home rect based on the fixed top-right anchor and current size.
    private func homeFrame() -> NSRect {
        let s = panel.frame.size
        return NSRect(x: homeAnchor.x - s.width, y: homeAnchor.y - s.height, width: s.width, height: s.height)
    }

    private func checkAndDodge() {
        guard panel.isVisible, !collisionCheckInFlight else {
            if !panel.isVisible { isDodging = false }
            return
        }

        // Capture everything we need from the main thread before going to background.
        let home         = homeFrame()
        guard let screen = panel.screen ?? screenContaining(NSPoint(x: home.midX, y: home.midY)) else { return }
        let screenFrame = screen.frame
        let ourPID       = Int(ProcessInfo.processInfo.processIdentifier)

        collisionCheckInFlight = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let blockerCG = AppDelegate.scanForBlocker(
                over: home,
                on: screenFrame,
                ourPID: ourPID
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.collisionCheckInFlight = false
                guard self.panel.isVisible else { return }

                if let blocker = blockerCG {
                    if !self.isDodging { self.isDodging = true }
                    self.dodgeHoldUntil = Date().addingTimeInterval(0.9)
                    let dodge = self.dodgePosition(avoiding: blocker)
                    let cur = self.panel.frame
                    if abs(cur.origin.x - dodge.origin.x) > 4 || abs(cur.origin.y - dodge.origin.y) > 4 {
                        self.animateToFrame(dodge)
                    }
                } else if self.isDodging {
                    guard Date() >= self.dodgeHoldUntil else { return }
                    self.isDodging = false
                    self.animateToFrame(self.homeFrame())
                }
            }
        }
    }

    // Pure function — safe to call from any thread.
    // Returns the CG-coordinate bounds of the first on-screen window from another process
    // at floating level or above that overlaps `nsFrame`, or nil if the coast is clear.
    private static func scanForBlocker(over nsFrame: NSRect,
                                       on screenFrame: NSRect,
                                       ourPID: Int) -> NSRect? {
        let target = nsFrame.insetBy(dx: -10, dy: -10)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for info in list {
            guard let pid   = info[kCGWindowOwnerPID as String] as? Int, pid != ourPID,
                  let layer = info[kCGWindowLayer as String]    as? Int, layer > 0
            else { continue }

            var bounds = CGRect.zero
            if let nsDict = info[kCGWindowBounds as String] as? NSDictionary {
                CGRectMakeWithDictionaryRepresentation(nsDict, &bounds)
            }
            guard bounds.width > 36, bounds.height > 28 else { continue }
            let nsBounds = nsRect(fromCGWindowBounds: bounds, screens: NSScreen.screens)
            guard nsBounds.intersects(screenFrame),
                  nsBounds.width < screenFrame.width * 0.92,
                  nsBounds.height < screenFrame.height * 0.80
            else { continue }
            if nsBounds.intersects(target) { return nsBounds }
        }
        return nil
    }

    // Computes a dodge rect (same size as the panel) that avoids `blockerCG`.
    // Tries: below the blocker → left of the blocker → top-left corner fallback.
    private func dodgePosition(avoiding blocker: NSRect) -> NSRect {
        guard let screen = panel.screen ?? NSScreen.main else { return homeFrame() }
        let vis     = screen.visibleFrame
        let size    = panel.frame.size

        let homeX = homeAnchor.x - size.width

        // Slide below the blocker, keeping same horizontal position.
        let belowY = blocker.minY - size.height - 8
        if belowY >= vis.minY {
            return NSRect(x: homeX, y: belowY, width: size.width, height: size.height)
        }

        // Move left of the blocker, keeping same vertical position.
        let leftX = blocker.minX - size.width - 8
        if leftX >= vis.minX {
            return NSRect(x: leftX, y: homeAnchor.y - size.height, width: size.width, height: size.height)
        }

        // Last resort: top-left corner.
        return NSRect(x: vis.minX + 16, y: vis.maxY - size.height - 8, width: size.width, height: size.height)
    }

    private func animateToFrame(_ frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private static func nsRect(fromCGWindowBounds bounds: CGRect, screens: [NSScreen]) -> NSRect {
        guard let screen = screen(forCGWindowBounds: bounds, screens: screens),
              let cgScreen = cgBounds(for: screen)
        else {
            let global = screens.reduce(NSRect.null) { $0.union($1.frame) }
            return NSRect(x: bounds.minX, y: global.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
        }

        let xInScreen = bounds.minX - cgScreen.minX
        let yFromTop = bounds.minY - cgScreen.minY
        return NSRect(
            x: screen.frame.minX + xInScreen,
            y: screen.frame.maxY - yFromTop - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func screen(forCGWindowBounds bounds: CGRect, screens: [NSScreen]) -> NSScreen? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return screens.first { screen in
            guard let cg = cgBounds(for: screen) else { return false }
            return cg.contains(center)
        } ?? screens.max { lhs, rhs in
            let lhsArea = cgBounds(for: lhs)?.intersection(bounds).area ?? 0
            let rhsArea = cgBounds(for: rhs)?.intersection(bounds).area ?? 0
            return lhsArea < rhsArea
        }
    }

    private static func cgBounds(for screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
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

private extension NSRect {
    var visibleArea: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}
