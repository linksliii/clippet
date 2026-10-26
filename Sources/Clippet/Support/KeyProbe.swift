#if DEBUG
import AppKit

enum KeyProbe {

    static func run() {
        _ = NSApplication.shared

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 120),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        let field = KeyCommandTextField()
        field.frame = NSRect(x: 10, y: 40, width: 400, height: 24)
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        field.selectText(nil)

        guard let editor = field.currentEditor() as? NSTextView else {
            print("probe: no field editor — cannot test")
            exit(1)
        }
        print("probe: field editor acquired")

        field.onAnyCommand = { sel in
            print("    dispatch -> \(NSStringFromSelector(sel))")
        }
        field.onMove = { print("    handler: onMove(\($0))") }
        field.onCommit = { print("    handler: onCommit") }
        field.onCancel = { print("    handler: onCancel") }
        field.onSelectAllCards = { print("    handler: onSelectAllCards"); return true }

        let cases: [(String, UInt16, NSEvent.ModifierFlags, String)] = [
            ("ctrl+A", 0, .control, "a"),
            ("cmd+A", 0, .command, "a"),
            ("ctrl+E", 14, .control, "e"),
            ("ctrl+K", 40, .control, "k"),
            ("up", 126, [], "\u{F700}"),
            ("down", 125, [], "\u{F701}"),
            ("left", 123, [], "\u{F702}"),
            ("right", 124, [], "\u{F703}"),
            ("return", 36, [], "\r"),
            ("esc", 53, [], "\u{1B}")
        ]

        for (label, code, mods, chars) in cases {
            print("\n  [\(label)]")
            field.stringValue = "笔记本abc"
            let event = NSEvent.keyEvent(with: .keyDown,
                                         location: .zero,
                                         modifierFlags: mods,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber,
                                         context: nil,
                                         characters: chars,
                                         charactersIgnoringModifiers: chars,
                                         isARepeat: false,
                                         keyCode: code)
            guard let event = event else { print("    event build failed"); continue }
            editor.interpretKeyEvents([event])
            let sel = editor.selectedRange()
            print("    selection -> loc=\(sel.location) len=\(sel.length) (text len \((editor.string as NSString).length))")
        }
        print("\nprobe done")
        exit(0)
    }
}

#endif
