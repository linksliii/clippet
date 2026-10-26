import AppKit

final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int

    private var ignoredCounts: Set<Int> = []
    private var lastForeignApp: NSRunningApplication?

    var onChange: ((PasteboardSnapshot, NSRunningApplication?) -> Void)?

    var isPaused: Bool = false

    init(interval: TimeInterval = 0.2) {
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
    }

    private let interval: TimeInterval
    private let captureQueue = DispatchQueue(label: "clippet.pasteboard", qos: .userInitiated)

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        t.tolerance = interval * 0.5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func suppressCurrentState() {
        let cc = pasteboard.changeCount
        ignoredCounts.insert(cc)
        lastChangeCount = cc
    }

    private func tick() {

        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastForeignApp = app
        }

        guard !isPaused else { return }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if ignoredCounts.contains(changeCount) {
            ignoredCounts.remove(changeCount)
            return
        }

        // Reading a large payload from the pasteboard costs ~190 ms for a
        // 144 MP image because it goes through the pasteboard server. Capture
        // off the main thread so the UI never stalls.
        let app = lastForeignApp
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            guard let snapshot = PasteboardSnapshot.capture(self.pasteboard) else { return }
            self.onChange?(snapshot, app)
        }
    }
}
