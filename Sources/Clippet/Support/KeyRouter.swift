import AppKit

enum KeyAction: Equatable {
    case beginSearch

    case closePreview
    case selectAllText
    case selectAllCards
    case closeFilters
    case preview
    case switchBoard(Int)
    case quickPaste(Int)
    case passThrough
}

struct KeyContext: Equatable {
    var searchActive: Bool = false
    var previewOpen: Bool = false
    var filtersOpen: Bool = false
    var queryEmpty: Bool = true
    var boardCount: Int = 1
}

enum SpaceRouter {
    static func shouldPreview(isComposing: Bool,
                              previewOpen: Bool,
                              filtersOpen: Bool,
                              queryEmpty: Bool,
                              isNavigating: Bool,
                              hasSelection: Bool) -> Bool {
        guard !isComposing else { return false }
        guard !previewOpen, !filtersOpen, hasSelection else { return false }
        return queryEmpty || isNavigating
    }
}

enum KeyRouter {

    static func resolve(keyCode: UInt16,
                        modifiers: NSEvent.ModifierFlags,
                        characters: String?,
                        context: KeyContext) -> KeyAction {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)

        if flags == .command, keyCode == 3 { return .beginSearch }

        if context.previewOpen {
            if keyCode == 53 || keyCode == 49 { return .closePreview }
            return .passThrough
        }

        if context.filtersOpen, keyCode == 53 { return .closeFilters }

        if flags == .command, keyCode == 0 {
            return context.queryEmpty ? .selectAllCards : .selectAllText
        }
        if flags == .control, keyCode == 0 { return .selectAllText }

        if flags == .command, keyCode == 16 { return .preview }

        if flags == .command, keyCode == 123 || keyCode == 124, context.boardCount > 1 {
            return .switchBoard(keyCode == 123 ? -1 : 1)
        }

        if flags == .command,
           let chars = characters, let n = Int(chars), n >= 1, n <= 9 {
            return .quickPaste(n)
        }

        return .passThrough
    }
}
