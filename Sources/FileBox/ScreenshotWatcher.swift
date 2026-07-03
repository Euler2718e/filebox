import AppKit
import Foundation

/// Watches for new screenshots via Spotlight metadata and reports their file URLs.
///
/// Uses an `NSMetadataQuery` filtered on `kMDItemIsScreenCapture`, the flag macOS sets on
/// any screenshot saved to a file. Matching on that flag is robust against localized
/// filenames and a custom screenshot-save location — unlike matching a filename prefix.
final class ScreenshotWatcher {
    /// Called on the main queue with the URL of each newly captured screenshot.
    var onScreenshot: ((URL) -> Void)?

    private var query: NSMetadataQuery?
    private var startDate = Date()
    private var seenPaths = Set<String>()

    func start() {
        guard query == nil else { return }
        startDate = Date()
        seenPaths.removeAll()

        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = Self.searchScopes()
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: true)]

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(initialGatherFinished(_:)),
                           name: .NSMetadataQueryDidFinishGathering, object: query)
        center.addObserver(self, selector: #selector(queryUpdated(_:)),
                           name: .NSMetadataQueryDidUpdate, object: query)

        self.query = query
        query.start()
    }

    func stop() {
        guard let query else { return }
        query.stop()
        let center = NotificationCenter.default
        center.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        center.removeObserver(self, name: .NSMetadataQueryDidUpdate, object: query)
        self.query = nil
    }

    deinit { stop() }

    // The first gathering pass returns every pre-existing screenshot in scope. Record
    // them as already-seen so only screenshots taken after start() ever get imported.
    @objc private func initialGatherFinished(_ note: Notification) {
        guard let query else { return }
        query.disableUpdates()
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                seenPaths.insert(path)
            }
        }
        query.enableUpdates()
    }

    @objc private func queryUpdated(_ note: Notification) {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        for item in added {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  seenPaths.insert(path).inserted else { continue }
            let created = item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date ?? Date()
            guard created >= startDate else { continue }
            let url = URL(fileURLWithPath: path)
            DispatchQueue.main.async { [weak self] in self?.onScreenshot?(url) }
        }
    }

    private static func searchScopes() -> [Any] {
        if let dir = screenshotDirectory() { return [dir] }
        return [NSMetadataQueryUserHomeScope]
    }

    /// The folder macOS saves screenshots to: the `com.apple.screencapture` `location`
    /// preference when it points at a real directory, otherwise the Desktop.
    static func screenshotDirectory() -> URL? {
        if let value = CFPreferencesCopyAppValue("location" as CFString,
                                                 "com.apple.screencapture" as CFString) as? String {
            let expanded = (value as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
    }
}
