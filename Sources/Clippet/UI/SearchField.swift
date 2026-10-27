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
    var focusOnAppear: Bool = false
    var debounce: TimeInterval = 0.12

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator {
        var parent: SearchField
        var lastModelText: String
        var lastCommitted: String?
        var work: DispatchWorkItem?

        init(_ parent: SearchField) {
            self.parent = parent
            self.lastModelText = parent.text
        }

        func schedule(_ value: String) {
            work?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lastCommitted = value
                self.parent.text = value
            }
            work = item
            DispatchQueue.main.asyncAfter(deadline: .now() + parent.debounce, execute: item)
        }

        func cancel() {
            work?.cancel()
            work = nil
        }
    }

    func makeNSView(context: Context) -> KeyCommandTextField {
        let field = KeyCommandTextField()
        field.setText(text)
        field.onTextChange = { newValue in
            if !newValue.isEmpty { onTextAppear?() }
            context.coordinator.schedule(newValue)
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
        let coordinator = context.coordinator
        coordinator.parent = self
        nsView.onMove = onMove
        nsView.onCommit = onCommit
        nsView.onCancel = onCancel
        nsView.onSelectAllCards = onSelectAllCards
        nsView.onSelectAllText = onSelectAllText

        // Only push the model's text into the field when the model changed on
        // its own (Esc/clear/demo). The debounced commit echoing the user's
        // own typing must not overwrite newer characters.
        if text != coordinator.lastModelText {
            coordinator.lastModelText = text
            if text != coordinator.lastCommitted {
                coordinator.cancel()
                nsView.setText(text)
            }
        }
    }
}
