import AppKit

final class PasteStack {
    private(set) var items: [ClipItem] = []

    var isEnabled: Bool = false

    var onChange: (() -> Void)?

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    func push(_ item: ClipItem) {

        if items.last?.hash == item.hash { return }
        items.append(item)
        onChange?()
    }

    func removeLast() {
        guard !items.isEmpty else { return }
        items.removeLast()
        onChange?()
    }

    func clear() {
        guard !items.isEmpty else { return }
        items.removeAll()
        onChange?()
    }
}
