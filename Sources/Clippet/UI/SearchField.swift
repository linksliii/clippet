import AppKit
import SwiftUI

final class KeyCommandTextField: NSTextField, NSTextFieldDelegate {
    var onTextChange: ((String) -> Void)?
    var onMove: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    var onSelectAllCards: (() -> Bool)?

    var onSelectAllText: (() -> Void)?

    var onAnyCommand: ((Selector) -> Void)?

    private var isProgrammaticSet = false

    init() {
        super.init(frame: .zero)
        delegate = self
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 15)
        placeholderString = "搜索剪贴板…"
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
        cell?.wraps = false
        cell?.isScrollable = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setText(_ value: String) {
        guard stringValue != value else { return }
        isProgrammaticSet = true
        stringValue = value
        isProgrammaticSet = false
    }

    func controlTextDidChange(_ obj: Notification) {
        guard !isProgrammaticSet else { return }
        onTextChange?(stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        onAnyCommand?(selector)
        switch selector {
        case #selector(NSResponder.moveUp(_:)):
            onMove?(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            onMove?(1)
            return true
        case #selector(NSResponder.moveLeft(_:)):

            guard stringValue.isEmpty else { return false }
            onMove?(-1)
            return true
        case #selector(NSResponder.moveRight(_:)):
            guard stringValue.isEmpty else { return false }
            onMove?(1)
            return true
        case #selector(NSResponder.selectAll(_:)):

            if stringValue.isEmpty, onSelectAllCards?() == true { return true }
            return false
        case #selector(NSResponder.moveToBeginningOfParagraph(_:)),
             #selector(NSResponder.moveToBeginningOfLine(_:)):

            textView.selectAll(nil)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        case #selector(NSResponder.insertTab(_:)):
            onCommit?()
            return true
        default:
            return false
        }
    }
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var onMove: (Int) -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void
    var onSelectAllCards: (() -> Bool)?
    var onSelectAllText: (() -> Void)?

    var onAnyCommand: ((Selector) -> Void)?

    var onTextAppear: (() -> Void)?
    var focusOnAppear: Bool = true

    func makeNSView(context: Context) -> KeyCommandTextField {
        let field = KeyCommandTextField()
        field.onTextChange = { newValue in
            if !newValue.isEmpty { onTextAppear?() }
            if text != newValue { text = newValue }
        }
        field.onMove = onMove
        field.onCommit = onCommit
        field.onCancel = onCancel
        field.onSelectAllCards = onSelectAllCards
        field.onSelectAllText = onSelectAllText
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        if focusOnAppear {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
        return field
    }

    func updateNSView(_ nsView: KeyCommandTextField, context: Context) {
        nsView.setText(text)
        nsView.onMove = onMove
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.onSelectAllCards = onSelectAllCards
        nsView.onSelectAllText = onSelectAllText
    }
}
