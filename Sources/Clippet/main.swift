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

let arguments = CommandLine.arguments
#if DEBUG
if let i = arguments.firstIndex(of: "--settings-panes"), i + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshot.settingsPanes(outputDirectory: arguments[i + 1]) }
} else if arguments.contains("--memprobe") {
    MemProbe.run()
} else if arguments.contains("--probe-keys") {
    KeyProbe.run()
} else if arguments.contains("--bench-throughput") {
    Bench.runThroughput()
} else if arguments.contains("--bench-json") {
    Bench.runJSON()
} else if arguments.contains("--bench-large") {
    Bench.runLarge()
} else if arguments.contains("--bench") {
    Bench.run()
} else if arguments.contains("--selftest") {
    SelfTest.run()
} else if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    MainActor.assumeIsolated { Snapshot.run(outputPath: arguments[index + 1]) }
} else {
    runApp()
}
#else
runApp()
#endif

func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
