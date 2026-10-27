import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteboardWriter {
    /// Supplies the full text for a row; list rows only carry a 600-char slice.
    static var textProvider: ((Int64) -> String?)?

    /// Resolves the complete text for an item, loading it when truncated.
    static func fullText(_ item: ClipItem) -> String? {
        guard let text = item.text else { return textProvider?(item.id) }
        if item.byteSize > text.utf8.count, let full = textProvider?(item.id) { return full }
        return text
    }


    static func write(_ item: ClipItem,
                      to pasteboard: NSPasteboard = .general,
                      plainTextOnly: Bool = false) throws {
        pasteboard.clearContents()

        switch item.kind {
        case .image:

            guard let data = item.data ?? ImageStore.fullData(forID: item.id) else {
                throw PasteError.missingPayload
            }
            pasteboard.setData(data, forType: .png)
            if let rep = NSBitmapImageRep(data: data), let tiff = rep.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }

        case .file:
            if plainTextOnly {

                guard !item.paths.isEmpty else { throw PasteError.missingPayload }
                pasteboard.setString(item.paths.joined(separator: "\n"), forType: .string)
            } else {
                let urls = item.paths.map { URL(fileURLWithPath: $0) as NSURL }
                guard !urls.isEmpty else { throw PasteError.missingPayload }
                pasteboard.writeObjects(urls)
            }

        case .color:
            guard let text = fullText(item) else { throw PasteError.missingPayload }
            if let color = NSColor(hex: text) {
                pasteboard.writeObjects([color])
            } else {
                pasteboard.setString(text, forType: .string)
            }

        case .text, .link, .code:
            guard let text = fullText(item) else { throw PasteError.missingPayload }
            pasteboard.setString(text, forType: .string)
        }
    }

    static func activate(_ app: NSRunningApplication?) {
        guard let app = app, !app.isTerminated else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    static var canSendKeystrokes: Bool {
        AXIsProcessTrusted()
    }

    static func sendPaste() {
        guard canSendKeystrokes else {
            NSLog("Clippet: accessibility permission missing; cannot send ⌘V")
            requestAccessibility()
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    static func paste(_ item: ClipItem,
                      into app: NSRunningApplication?,
                      plainTextOnly: Bool = false,
                      completion: (() -> Void)? = nil) {
        do {
            try write(item, plainTextOnly: plainTextOnly)
        } catch {
            NSLog("Clippet: write failed: \(error)")
            completion?()
            return
        }
        guard let app = app, !app.isTerminated else {
            completion?()
            return
        }
        activate(app)
        waitUntilFrontmost(app, timeout: 0.5) {
            if app.isActive { sendPaste() }
            completion?()
        }
    }

    private static func waitUntilFrontmost(_ app: NSRunningApplication,
                                           timeout: TimeInterval,
                                           then: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if app.isActive
                || NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                || Date() >= deadline {
                then()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        poll()
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

extension NSColor {

    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 3 || s.count == 6 || s.count == 8 else { return nil }
        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        switch s.count {
        case 3:
            r = Double((value >> 8) & 0xF) / 15.0
            g = Double((value >> 4) & 0xF) / 15.0
            b = Double(value & 0xF) / 15.0
            a = 1
        case 6:
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
            a = 1
        default:
            r = Double((value >> 24) & 0xFF) / 255.0
            g = Double((value >> 16) & 0xFF) / 255.0
            b = Double((value >> 8) & 0xFF) / 255.0
            a = Double(value & 0xFF) / 255.0
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
