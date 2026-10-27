import AppKit
import SwiftUI

private struct CardFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct HistoryView: View {
    @ObservedObject var model: ClipboardViewModel

    var usesSystemGlass: Bool = false
    @State private var hoverFooter = false

    @State private var lastTapIndex: Int = -1
    @State private var lastTapTime: CFAbsoluteTime = 0

    @State private var hoverTab: Int64?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            chipsRow
            cardRow
            footer
        }
        .frame(maxWidth: .infinity)
        .frame(height: Design.panelHeight)
        .background(panelBackground)

        .clipShape(RoundedRectangle(cornerRadius: usesSystemGlass ? 0 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(usesSystemGlass ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { hoverFooter = $0 }

        .alert("Rename Pinboard",
               isPresented: Binding(get: { model.renameTarget != nil },
                                    set: { if !$0 { model.renameTarget = nil } })) {
            TextField("Name", text: $model.renameText)
            Button("Cancel", role: .cancel) { model.renameTarget = nil }
            Button("Rename") { model.commitRename() }
        }
    }

    private var panelBackground: some View {
        ZStack {
            if usesSystemGlass {
                Color.clear
            } else {
                Rectangle().fill(.ultraThinMaterial)
                Color(hex: "#1B1E1E").opacity(0.62)
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack {

            HStack(spacing: 10) {
                searchButton
                tabCapsule
                addButton
            }
            .opacity(model.searchActive ? 0 : 1)
            .allowsHitTesting(!model.searchActive)

            HStack(spacing: 10) {
                searchField
                filterButton
                compactTabs
            }
            .opacity(model.searchActive ? 1 : 0)
            .allowsHitTesting(model.searchActive)

            HStack {
                Spacer()
                moreMenu
                    .padding(.trailing, Design.sidePadding)
            }
        }
        .frame(height: Design.topBarHeight)
    }

    private var searchButton: some View {
        Button {
            model.beginSearch()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("搜索（⌘F）")
    }

    private var filterButton: some View {
        Button {
            model.filtersOpen.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(model.hasFilters ? Design.accent : Color.white.opacity(0.75))
                    .frame(width: 26, height: 26)
                if model.filterCount > 0 {
                    Text("\(model.filterCount)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Design.accent))
                        .offset(x: 4, y: -2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("筛选")
        .popover(isPresented: $model.filtersOpen, arrowEdge: .bottom) {
            FilterBrowser(model: model, onDismiss: { model.filtersOpen = false })
        }
    }

    @ViewBuilder
    private var chipsRow: some View {
        if model.hasFilters {
            HStack(spacing: 6) {
                if let kind = model.kindFilter {
                    FilterChip(title: kind.displayName, tint: Design.accent) {
                        model.kindFilter = nil
                    }
                }
                if let app = model.appFilter {
                    FilterChip(title: model.appName(for: app), tint: Color(hex: "#34C759")) {
                        model.appFilter = nil
                    }
                }
                if let date = model.dateFilter {
                    FilterChip(title: date.title, tint: Color(hex: "#FF9500")) {
                        model.dateFilter = nil
                    }
                }
                Spacer()
                Button("清除") { model.clearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, Design.sidePadding)
            .frame(height: 26)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))

            SearchField(text: $model.query,
                        onMove: { model.moveSelection($0) },
                        onCommit: { model.commitSelection() },
                        onCancel: { model.handleEscape() },
                        onSelectAllCards: { model.selectAllVisible(); return true },
                        onSelectAllText: nil,
                        onTextAppear: { model.beginSearch() })

            if !model.query.isEmpty {
                Button {
                    model.clearQuery()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 460, height: 32)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Design.accent, lineWidth: 2)
        )
    }

    private var compactTabs: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            ForEach(model.boards.filter { !$0.isDefault }) { board in
                Circle()
                    .fill(Color(hex: board.tint))
                    .frame(width: 13, height: 13)
            }
        }
    }

    private var tabCapsule: some View {
        HStack(spacing: 2) {
            ForEach(model.boards) { board in
                tabButton(board)
            }
        }
        .padding(3)
        .background(
            Capsule().fill(Design.tabBarPill)
        )
    }

    private func tabButton(_ board: Board) -> some View {
        let isSelected = board.id == model.selectedBoardID
        return Button {
            model.selectBoard(board.id)
        } label: {
            HStack(spacing: 6) {
                if board.isDefault {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
                } else {
                    Circle()
                        .fill(Color(hex: board.tint))
                        .frame(width: 9, height: 9)
                }
                Text(board.name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Design.tabSelected : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoverTab = hovering ? board.id : nil }
        .contextMenu {
            if !board.isDefault {
                Button("重命名…") { model.beginRename(board) }
                Button("删除面板", role: .destructive) { model.deleteBoard(board.id) }
            }
        }
    }

    private var addButton: some View {
        Button {
            model.createBoard()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("新建面板")
    }

    private var moreMenu: some View {
        Menu {
            Button("清空历史…") { model.clearHistory() }
            Divider()
            Toggle("堆栈模式", isOn: Binding(get: { model.stackEnabled },
                                                set: { model.stackEnabled = $0 }))
            Divider()
            Button("关闭") { model.onClose?() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
    }

    private var queryTerms: [String] {
        Repository.searchTerms(model.query)
    }

    private var cardRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                if model.items.isEmpty {
                    emptyState
                        .frame(width: 520, height: Design.cardHeight)
                } else {
                    LazyHStack(spacing: Design.cardGap) {
                        ForEach(Array(model.items.enumerated()), id: \.element.id) { offset, item in
                            ClipCard(item: item,
                                     index: offset + 1,
                                     isSelected: offset == model.selection
                                                 || model.selectedIDs.contains(item.id),
                                     board: model.board(for: item),
                                     highlightTerms: queryTerms,
                                     isMultiSelecting: model.hasMultiSelection,
                                     isMultiSelected: model.selectedIDs.contains(item.id))
                                .id(item.id)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: CardFramesKey.self,
                                            value: [offset: geo.frame(in: .global)])
                                    }
                                )

                                .onTapGesture {
                                    handleTap(item: item, index: offset)
                                }
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .padding(.horizontal, Design.sidePadding)
                }
            }
            .onPreferenceChange(CardFramesKey.self) { frames in
                model.cardFrames = frames
                model.onCardFramesChange?()
                if CommandLine.arguments.contains("--log-frames") {
                    let ordered = frames.sorted { $0.key < $1.key }.map {
                        "[\($0.key)] x=\(Int($0.value.minX)) y=\(Int($0.value.minY)) w=\(Int($0.value.width)) h=\(Int($0.value.height))"
                    }
                    NSLog("Clippet: card frames %@", ordered.joined(separator: " | "))
                }
            }
            .onChange(of: model.selection) { _, newValue in
                guard newValue >= 0, newValue < model.items.count else { return }

                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.items[newValue].id)
                }
            }
        }
        .frame(height: Design.cardHeight + 12)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("粘贴") { model.onPaste?(item) }
        Button("预览") { model.previewItem = item }
        Button("Copy") {
            try? PasteboardWriter.write(item)
        }
        Divider()
        Button(item.isPinned ? "取消固定" : "固定") { model.togglePin(item) }
        if !model.boards.filter({ !$0.isDefault }).isEmpty {
            Menu("移动到面板") {
                ForEach(model.boards.filter { !$0.isDefault }) { board in
                    Button(board.name) { model.moveToBoard(item, boardID: board.id) }
                }
            }
        }
        Divider()
        Button("删除", role: .destructive) { model.delete(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.searchActive && !model.query.isEmpty
                  ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white.opacity(0.22))
            Text(model.searchActive && !model.query.isEmpty
                 ? "没有找到"
                 : (model.currentBoard?.isDefault == true ? "历史为空" : "面板为空"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleTap(item: ClipItem, index: Int) {
        let now = CFAbsoluteTimeGetCurrent()
        let isDoubleClick = lastTapIndex == index
            && (now - lastTapTime) < NSEvent.doubleClickInterval
        lastTapIndex = index
        lastTapTime = now

        if isDoubleClick {
            model.selection = index
            model.commitSelection()
            return
        }

        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            model.selection = index
            model.toggleSelection(item)
        } else if flags.contains(.shift) {
            model.selectRange(to: index)
        } else {
            if model.hasMultiSelection { model.clearMultiSelection() }
            model.selection = index
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.hasMultiSelection {
            selectionBar
        } else {
            statusBar
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("已选 \(model.selectedIDs.count) 项")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Button("复制") { model.copySelectedToPasteboard() }
            Button("固定") { model.setPinnedForSelection(true) }
            Button("删除") { model.deleteSelected() }
            Button("取消选择") { model.clearMultiSelection() }
        }
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, Design.sidePadding)
        .frame(height: Design.bottomBarHeight)
        .background(Design.accent.opacity(0.14))
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Text("\(model.items.count) 条")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            if model.stackEnabled && model.stackCount > 0 {
                Label("Stack \(model.stackCount)", systemImage: "square.stack.3d.up.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            if hoverFooter {
                Text("↵ 粘贴 · ⌥↵ 纯文本 · 空格 预览 · ⌘1–9 快速 · ⌘←→ 切换面板")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(.horizontal, Design.sidePadding)
        .frame(height: Design.bottomBarHeight)
    }
}
