import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Clippet", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        do {
            let db = try Database.open(at: support.appendingPathComponent("clippet.db"))
            let repo = Repository(db: db)
            let c = AppController(repository: repo)
            c.start()
            controller = c
        } catch {
            NSLog("Clippet: failed to open database: \(error)")
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        controller?.showFromUser()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

runApp()

func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
