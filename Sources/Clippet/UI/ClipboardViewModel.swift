import AppKit
import Combine

struct AppUsage: Identifiable, Hashable {
    var bundleID: String
    var name: String
    var count: Int64
    var id: String { bundleID }
}

final class ClipboardViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var boards: [Board] = []
    @Published var selectedBoardID: Int64 = 0
    @Published var query: String = "" {
        didSet {

            if query != oldValue {
                isNavigating = false
                scheduleNavigationMode()
            }
            if !suppressReload { reload(resetSelection: true) }
        }
    }

    var isNavigating: Bool = false

    private var navigationTimer: DispatchWorkItem?

    private func scheduleNavigationMode() {
        navigationTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.isNavigating = true
        }
        navigationTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    deinit { navigationTimer?.cancel() }
    @Published var kindFilter: ClipKind? { didSet { reload(resetSelection: true) } }
    @Published var appFilter: String? { didSet { reload(resetSelection: true) } }
    @Published var dateFilter: DateFilter? { didSet { reload(resetSelection: true) } }

    @Published var searchActive: Bool = false

    @Published var filtersOpen: Bool = false { didSet { if filtersOpen { refreshApps() } } }

    @Published var previewItem: ClipItem?

    @Published var renameTarget: Board?
    @Published var renameText: String = ""

    @Published var selectedIDs: Set<Int64> = []
    @Published var selection: Int = 0
    @Published var apps: [AppUsage] = []
    @Published var stackEnabled: Bool = false
    @Published var stackCount: Int = 0
    @Published var totalCount: Int64 = 0

    var onPaste: ((ClipItem) -> Void)?
    var onClose: (() -> Void)?

    var cardFrames: [Int: CGRect] = [:]
    var onCardFramesChange: (() -> Void)?

    private let repo: Repository
    private var suppressReload = false

    init(repo: Repository) {
        self.repo = repo
        reloadBoards()
        reload(resetSelection: true)
    }

    func refreshApps() {
        apps = repo.apps().map { AppUsage(bundleID: $0.bundleID, name: $0.name, count: $0.count) }
    }

    func reloadBoards() {
        boards = repo.boards()
        if selectedBoardID == 0 {
            selectedBoardID = repo.defaultBoard().id
        }
        if !boards.contains(where: { $0.id == selectedBoardID }) {
            selectedBoardID = repo.defaultBoard().id
        }
    }

    func switchBoard(by delta: Int) {
        guard boards.count > 1,
              let index = boards.firstIndex(where: { $0.id == selectedBoardID }) else { return }
        let next = (index + delta + boards.count) % boards.count
        selectBoard(boards[next].id)
    }

    func selectBoard(_ id: Int64) {
        guard selectedBoardID != id else { return }
        selectedBoardID = id
        selection = 0
        reload(resetSelection: true)
    }

    func createBoard() {
        let index = boards.count
        let name = "Pinboard \(index)"
        let id = repo.createBoard(name: name)
        reloadBoards()
        if id != 0 { selectBoard(id) }
    }

    func beginRename(_ board: Board) {
        renameTarget = board
        renameText = board.name
    }

    func commitRename() {
        defer { renameTarget = nil }
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        repo.renameBoard(target.id, name: trimmed)
        reloadBoards()
    }

    func deleteBoard(_ id: Int64) {
        repo.deleteBoard(id)
        if selectedBoardID == id { selectedBoardID = repo.defaultBoard().id }
        reloadBoards()
        reload(resetSelection: true)
    }

    var filterCount: Int {
        [kindFilter != nil, appFilter != nil, dateFilter != nil].filter { $0 }.count
    }

    var hasFilters: Bool { filterCount > 0 }

    func clearFilters() {
        kindFilter = nil
        appFilter = nil
        dateFilter = nil
    }

    func appName(for bundleID: String) -> String {
        apps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    var currentBoard: Board? {
        boards.first { $0.id == selectedBoardID }
    }

    func board(for item: ClipItem) -> Board? {
        boards.first { $0.id == item.boardID }
    }

    func reload(resetSelection: Bool = false) {
        var filter = HistoryFilter(query: query)
        filter.kind = kindFilter

        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        filter.boardID = isSearching ? nil : selectedBoardID
        filter.sourceApp = appFilter
        filter.since = dateFilter?.since
        filter.limit = 300

        items = repo.fetch(filter)

        if filtersOpen {
            refreshApps()
            totalCount = repo.count()
        }

        if resetSelection { selection = 0 }
        if items.isEmpty { selection = 0 }
        if selection >= items.count { selection = max(0, items.count - 1) }
    }

    func beginSearch() {
        searchActive = true
    }

    func endSearch() {
        searchActive = false
        query = ""
    }

    func handleEscape() {
        if filtersOpen { filtersOpen = false; return }
        if !query.isEmpty { clearQuery(); return }
        if searchActive { endSearch(); return }
        onClose?()
    }

    func clearQuery() {
        query = ""
    }

    func cardIndex(at point: CGPoint) -> Int? {
        for (index, frame) in cardFrames where frame.contains(point) {
            return index
        }
        return nil
    }

    func handleClick(index: Int, clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        guard index >= 0, index < items.count else { return }
        isNavigating = true
        if clickCount >= 2 {
            selection = index
            commitSelection()
            return
        }
        if modifiers.contains(.command) {
            selection = index
            toggleSelection(items[index])
        } else if modifiers.contains(.shift) {
            selectRange(to: index)
        } else {
            if hasMultiSelection { clearMultiSelection() }
            selection = index
        }
    }

    var hasMultiSelection: Bool { !selectedIDs.isEmpty }

    var selectedItems: [ClipItem] { items.filter { selectedIDs.contains($0.id) } }

    func clearMultiSelection() {
        if !selectedIDs.isEmpty { selectedIDs.removeAll() }
    }

    func toggleSelection(_ item: ClipItem) {
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
        else { selectedIDs.insert(item.id) }
    }

    func selectRange(to index: Int) {
        guard !items.isEmpty else { return }
        let lower = min(selection, index)
        let upper = max(selection, index)
        guard lower >= 0, upper < items.count else { return }
        for i in lower...upper { selectedIDs.insert(items[i].id) }
        selection = index
    }

    func selectAllVisible() {
        selectedIDs = Set(items.map(\.id))
    }

    func deleteSelected() {
        let ids = selectedIDs
        selectedIDs.removeAll()
        for id in ids { repo.delete(id: id) }
        reload()
    }

    func setPinnedForSelection(_ pinned: Bool) {
        for item in selectedItems { repo.setPinned(item.id, pinned) }
        reload()
    }

    func copySelectedToPasteboard() {
        let texts = selectedItems.compactMap { item -> String? in
            if let text = item.text { return text }
            return item.paths.isEmpty ? nil : item.paths.joined(separator: "\n")
        }
        guard !texts.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(texts.joined(separator: "\n"), forType: .string)
    }

    var isWheelScrolling = false
    private var wheelHadPreview = false

    func beginWheelScrolling() {
        guard !isWheelScrolling else { return }
        wheelHadPreview = previewItem != nil
        isWheelScrolling = true
        // Repositioning and re-decoding the preview for every wheel step is
        // what makes a fast spin stutter; it comes back when the wheel stops.
        if wheelHadPreview { previewItem = nil }
    }

    func finishWheelScrolling() {
        isWheelScrolling = false
        if wheelHadPreview {
            wheelHadPreview = false
            previewItem = selectedItem
        }
    }

    func cancelWheelScrolling() {
        isWheelScrolling = false
        wheelHadPreview = false
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        isNavigating = true
        selection = min(max(0, selection + delta), items.count - 1)
        if previewItem != nil, !isWheelScrolling { previewItem = items[selection] }
    }

    func jump(to index: Int) {
        guard index >= 0, index < items.count else { return }
        selection = index
    }

    var selectedItem: ClipItem? {
        guard selection >= 0, selection < items.count else { return nil }
        return items[selection]
    }

    func commitSelection() {
        guard let item = selectedItem else { return }
        onPaste?(item)
    }

    func togglePin(_ item: ClipItem) {
        repo.setPinned(item.id, !item.isPinned)
        reload()
    }

    func delete(_ item: ClipItem) {
        repo.delete(id: item.id)
        reload()
    }

    func moveToBoard(_ item: ClipItem, boardID: Int64) {
        repo.moveToBoard(item.id, boardID: boardID)
        reloadBoards()
        reload()
    }

    func clearHistory() {
        repo.clearHistory()
        reload(resetSelection: true)
    }
}
