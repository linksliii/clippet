import AppKit
import Combine
import SwiftUI

final class AppController: NSObject, NSWindowDelegate {
    private let repository: Repository
    private let monitor: ClipboardMonitor
    private let stack = PasteStack()
    private let hotKeys = HotKeyCenter()
    private let viewModel: ClipboardViewModel

    private var panel: ClipboardPanel?
    private var previewPopover: NSPopover?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var lastSyncedSelectionID: Int64?

    private var syncGeneration = 0

    private var isAnimatingIn = false
    private var isAnimatingOut = false
    private var isFittingPanel = false
    private var showGeneration = 0
    private var idleCleanup: DispatchWorkItem?

    private var visibleSince: Date?

    private var targetApp: NSRunningApplication?

    private let settings = AppSettings.shared
    private var settingsWindow: NSWindow?

    init(repository: Repository) {
        self.repository = repository
        self.monitor = ClipboardMonitor()
        self.viewModel = ClipboardViewModel(repo: repository)
        super.init()
    }

#if DEBUG
    private func rssMB() -> Double {
        var i = mach_task_basic_info()
        var c = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let k = withUnsafeMutablePointer(to: &i) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c)) {
            task_info(mach_self, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &c) } }
        return k == KERN_SUCCESS ? Double(i.resident_size) / 1048576 : 0
    }
    private var mach_self: mach_port_t { mach_task_self_ }
#endif

    func start() {
#if DEBUG
        NSLog("RSS start=%.0f", rssMB())
        defer { NSLog("RSS end=%.0f", rssMB()) }
        for d in [0.05, 0.15, 0.3, 0.5, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { [weak self] in
                guard let self = self else { return }
                NSLog("RSS +%.0fs=%.0f active=%d menu=%d", d, self.rssMB(),
                      NSApp.isActive ? 1 : 0, NSApp.mainMenu == nil ? 0 : 1)
            }
        }
#endif

        ImageStore.dataProvider = { [weak self] id in
            self?.repository.imageData(id: id)
        }
        PasteboardWriter.textProvider = { [weak self] id in
            self?.repository.fullText(id: id)
        }

        bindSettings()
        setupStatusItem()
        setupHotKeys()
        wireViewModel()
        wireMonitor()

        applyRetention()
        viewModel.reloadBoards()
        viewModel.reload(resetSelection: true)

        _ = ensurePanel(width: panelPlacement().screen.frame.width)

        // Prewarm: the panel's real cost is ~1 MB of physical footprint, so
        // building it up front is worth the instant first show.
        _ = ensurePanel()

        installKeyMonitor()
        installClickMonitor()
        bindSelectionSync()
        bindPreview()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidResignActive),
            name: NSApplication.didResignActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(ensureMainMenu),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        monitor.start()

        if !PasteboardWriter.canSendKeystrokes {
            NSLog("Clippet: accessibility permission not granted; pasting will not work until enabled")
        }

#if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--show-after"),
           i + 1 < CommandLine.arguments.count,
           let seconds = Double(CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.showPanel()
            }
        }

        if CommandLine.arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showSettingsWindow()
            }
        }

        if let i = CommandLine.arguments.firstIndex(of: "--cycle"),
           i + 1 < CommandLine.arguments.count,
           let cycles = Int(CommandLine.arguments[i + 1]) {
            runCycleProbe(cycles: cycles)
        }

        if let i = CommandLine.arguments.firstIndex(of: "--hide-after"),
           i + 1 < CommandLine.arguments.count,
           let seconds = Double(CommandLine.arguments[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.hidePanel()
            }
        }

        if CommandLine.arguments.contains("--show-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showPanel()
                if CommandLine.arguments.contains("--show-filters") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.viewModel.filtersOpen = true
                    }
                }
                if let i = CommandLine.arguments.firstIndex(of: "--search-demo"),
                   i + 1 < CommandLine.arguments.count {
                    let q = CommandLine.arguments[i + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        self?.viewModel.beginSearch()
                        self?.viewModel.query = q
                    }
                }
                if CommandLine.arguments.contains("--preview-demo") {
                    let index: Int
                    if let i = CommandLine.arguments.firstIndex(of: "--preview-index"),
                       i + 1 < CommandLine.arguments.count,
                       let n = Int(CommandLine.arguments[i + 1]) {
                        index = n
                    } else {
                        index = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                        guard let self = self, index < self.viewModel.items.count else { return }
                        self.viewModel.selection = index
                        self.viewModel.previewItem = self.viewModel.items[index]
                    }
                }
                if CommandLine.arguments.contains("--multi-demo") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                        guard let self = self else { return }
                        for item in self.viewModel.items.prefix(3) {
                            self.viewModel.selectedIDs.insert(item.id)
                        }
                    }
                }
                if CommandLine.arguments.contains("--filter-demo") {
                    self?.viewModel.kindFilter = .text
                    self?.viewModel.dateFilter = .today
                }
            }
        }
#endif

    }

    func stop() {
        monitor.stop()
        hotKeys.unregisterAll()
        if let monitorRef = keyMonitor {
            NSEvent.removeMonitor(monitorRef)
            keyMonitor = nil
        }
        if let mouseRef = mouseMonitor {
            NSEvent.removeMonitor(mouseRef)
            mouseMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func wireViewModel() {
        viewModel.onPaste = { [weak self] item in
            self?.pasteSingle(item)
        }
        viewModel.onClose = { [weak self] in
            self?.hidePanel()
        }
        viewModel.stackEnabled = stack.isEnabled
        stack.onChange = { [weak self] in
            guard let self = self else { return }
            self.viewModel.stackCount = self.stack.count
        }
    }

    private func wireMonitor() {

        monitor.onChange = { [weak self] snapshot, app in
            guard let self = self else { return }
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            guard !self.settings.isAppIgnored(bundleID) else { return }

            let tint = AppTint.tint(forBundleID: bundleID)
            let board = self.repository.defaultBoard()
            guard let content = ContentClassifier.classify(snapshot) else { return }
            if self.settings.ignoreConfidential, content.tags.contains("secret") { return }
            self.repository.insert(content,
                                   sourceApp: bundleID,
                                   sourceName: name,
                                   sourceTint: tint,
                                   boardID: board.id)
            DispatchQueue.main.async {
                if self.settings.playSound { NSSound(named: "Tink")?.play() }
                self.applyRetention()
                if self.isPanelVisible { self.viewModel.reload() }
            }
        }
    }

    private func setupHotKeys() {
        hotKeys.register(.default) { [weak self] in
            self?.togglePanel()
        }
        hotKeys.register(.stackPaste) { [weak self] in
            self?.pasteStack()
        }
    }

    private var isPanelVisible: Bool {
        panel?.isVisible ?? false
    }

    private func ensurePanel(width: CGFloat = 0) -> ClipboardPanel {
        if let existing = panel { return existing }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panelWidth = width > 1 ? width : screen.frame.width
        let rect = NSRect(x: screen.frame.minX, y: 0,
                          width: panelWidth, height: Design.panelHeight)

        let p = ClipboardPanel.transparent(size: rect.size)
        p.setFrame(rect, display: false)

        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let usesGlass = LiquidGlass.isAvailable
        let container = NSView(frame: rect)
        container.autoresizingMask = [.width, .height]

        if let glass = LiquidGlass.makeBackground(cornerRadius: 18) {
            glass.frame = container.bounds
            glass.autoresizingMask = [.width, .height]
            container.addSubview(glass)
        } else {
            let material = MaterialBackgroundView(frame: container.bounds)
            material.autoresizingMask = [.width, .height]
            container.addSubview(material)
        }

        let hosting = NSHostingView(rootView: HistoryView(model: viewModel,
                                                          usesSystemGlass: usesGlass))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)

        p.contentView = container
        NSLog("Clippet: panel backing = \(usesGlass ? "Liquid Glass" : "vibrancy fallback")")
        panel = p
        return p
    }

    private func togglePanel() {
        if isPanelVisible { hidePanel() } else { showPanel() }
    }

    private func screenForMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    /// The panel opens on the display under the pointer, at the vertical spot
    /// the user last dragged it to. The bottom offset is shared by all displays,
    /// so switching screens keeps the same place.
    private func panelPlacement() -> (screen: NSScreen, y: CGFloat) {
        let screen = screenForMouse()
        let visible = screen.visibleFrame
        let height = Design.panelHeight

        var y = visible.midY - height / 2
        if let bottom = PanelFrameStore.savedBottomOffset() {
            y = min(max(visible.minY + bottom, visible.minY), visible.maxY - height)
        }
        return (screen, y)
    }

    private func panelFrame(on screen: NSScreen, y: CGFloat) -> NSRect {
        NSRect(x: screen.frame.minX, y: y,
               width: screen.frame.width, height: Design.panelHeight)
    }

    /// `NSWindow.screen` can still report the previous display right after a
    /// move, so work out the display from the frame itself.
    private func screen(containing frame: NSRect) -> NSScreen? {
        var best: (screen: NSScreen, area: CGFloat)?
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (screen, area) }
        }
        return best?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The panel is a full-width bar. When it is dragged onto another display
    /// (or that display changes size), stretch it to the new width instead of
    /// carrying the old display's width across.
    private func fitPanelToScreen(_ p: ClipboardPanel, screen: NSScreen) {
        let x = screen.frame.minX
        let width = screen.frame.width
        guard abs(p.frame.minX - x) > 0.5 || abs(p.frame.width - width) > 0.5 else { return }

        var frame = p.frame
        frame.origin.x = x
        frame.size.width = width
        isFittingPanel = true
        p.setFrame(frame, display: true)
        isFittingPanel = false
    }

    private func offscreenFrame(for target: NSRect, in visible: NSRect) -> NSRect {
        NSRect(x: target.origin.x,
               y: visible.minY - target.height - 8,
               width: target.width, height: target.height)
    }

    func showFromUser() { showPanel() }

    private func showPanel() {
        guard !isPanelVisible else { return }

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = frontmost
        }

        ensureMainMenu()
        NSApp.activate(ignoringOtherApps: true)

        let placement = panelPlacement()
        let target = panelFrame(on: placement.screen, y: placement.y)
        let start = offscreenFrame(for: target, in: placement.screen.visibleFrame)
        let p = ensurePanel(width: target.width)

        lastSyncedSelectionID = nil

        viewModel.reloadBoards()
        viewModel.reload(resetSelection: true)
        viewModel.clearMultiSelection()

        idleCleanup?.cancel()
        idleCleanup = nil
        visibleSince = Date()
        showGeneration += 1
        let generation = showGeneration

        p.alphaValue = 0
        p.setFrame(start, display: false)
        // Lay the SwiftUI tree out while the window is invisible, so the first
        // animation frames are not spent sizing cards and the glass.
        p.contentView?.layoutSubtreeIfNeeded()
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        p.makeKey()
        p.displayIfNeeded()

        // Activating the app makes the window server hold frame animations for
        // a beat; a slide started in the same turn skips its first frames and
        // lands as a jump. Start the slide once activation has settled.
        DispatchQueue.main.async { [weak self, weak p] in
            guard let self = self, let p = p, p.isVisible,
                  !self.isAnimatingOut,
                  generation == self.showGeneration else { return }
            p.makeKey()
            self.focusSearchField()
            self.isAnimatingIn = true
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.30
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.08, 0.30, 1.0)
                ctx.allowsImplicitAnimation = true
                p.animator().setFrame(target, display: true)
                p.animator().alphaValue = 1.0
            }, completionHandler: { [weak self] in
                guard let self = self, generation == self.showGeneration else { return }
                self.isAnimatingIn = false
            })
        }
        NSLog("Clippet: panel visible=\(p.isVisible) key=\(p.isKeyWindow) appActive=\(NSApp.isActive) target=\(target)")
#if DEBUG
        if CommandLine.arguments.contains("--probe-key") {
            for delay in [0.05, 0.15, 0.35, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak p] in
                    NSLog("Clippet: probe +\(delay)s key=\(p?.isKeyWindow ?? false) active=\(NSApp.isActive) frameY=\(p?.frame.origin.y ?? 0)")
                }
            }
        }
#endif
    }

    private func hidePanel() {
        if viewModel.previewItem != nil { viewModel.previewItem = nil }
        guard let p = panel, p.isVisible else { return }

        showGeneration += 1
        isAnimatingIn = false
        isAnimatingOut = true

        let visible = (screen(containing: p.frame) ?? screenForMouse()).visibleFrame
        let off = offscreenFrame(for: p.frame, in: visible)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(off, display: true)
            p.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            p.orderOut(nil)
            p.alphaValue = 1.0
            self?.isAnimatingOut = false
            self?.scheduleIdleCleanup()
        })
    }

    /// Keep the panel and its SwiftUI tree warm between uses: rebuilding them
    /// after an idle pause costs ~50 ms on the next show, while holding them
    /// costs a few MB of physical footprint. Only the transient preview and the
    /// raw image bytes are released after a grace period.
    private func scheduleIdleCleanup() {
        idleCleanup?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let p = self.panel, !p.isVisible else { return }
            self.previewPopover?.close()
            self.previewPopover = nil
            ImageStore.purgeFullSize()
        }
        idleCleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    func windowDidMove(_ notification: Notification) {
        // Programmatic moves (the slide-in and slide-out animations) pass
        // through here too; only a move the user made while the panel is at
        // rest is a position worth remembering.
        guard !isAnimatingIn, !isAnimatingOut, !isFittingPanel else { return }
        guard let p = panel, p.isVisible, let screen = screen(containing: p.frame) else { return }
        if viewModel.previewItem != nil { viewModel.previewItem = nil }
        fitPanelToScreen(p, screen: screen)
        PanelFrameStore.save(p.frame, on: screen)
    }

    @objc private func screenParametersDidChange() {
        guard !isAnimatingIn, !isAnimatingOut, !isFittingPanel else { return }
        guard let p = panel, p.isVisible, let screen = screen(containing: p.frame) else { return }
        fitPanelToScreen(p, screen: screen)
    }

    @objc private func appDidResignActive() {
        hidePanel()
    }

#if DEBUG

    private func runCycleProbe(cycles: Int) {
        let start = Date()
        func resident() -> Double {
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            guard kr == KERN_SUCCESS else { return 0 }
            return Double(info.resident_size) / 1024 / 1024
        }

        NSLog("Clippet: cycle probe start rss=%.1f MB", resident())
        for cycle in 1...cycles {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(cycle) * 0.35) { [weak self] in
                guard let self = self else { return }
                self.showPanel()
                self.viewModel.query = "lorem \(cycle)"
                self.viewModel.reload()
                if let item = self.viewModel.selectedItem {
                    self.viewModel.previewItem = item
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    self.viewModel.previewItem = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.hidePanel()
                    if cycle % 10 == 1 || cycle == cycles {
                        NSLog("Clippet: cycle %d/%d rss=%.1f MB (%.1fs)",
                              cycle, cycles, resident(),
                              Date().timeIntervalSince(start))
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(cycles) * 0.35 + 0.5) {
            NSLog("Clippet: cycle probe done rss=%.1f MB", resident())
        }
    }

#endif

    private func installClickMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self = self,
                  self.isPanelVisible,
                  self.viewModel.previewItem == nil,
                  let panel = self.panel,
                  event.window === panel else { return event }

            let height = panel.contentView?.bounds.height ?? panel.frame.height

            let point = CGPoint(x: event.locationInWindow.x,
                                y: height - event.locationInWindow.y)
            guard let index = self.viewModel.cardIndex(at: point) else { return event }

            self.viewModel.handleClick(index: index,
                                       clickCount: event.clickCount,
                                       modifiers: event.modifierFlags)
            return nil
        }
    }

    private func bindSelectionSync() {
        viewModel.$items
            .combineLatest(viewModel.$selection)
            .debounce(for: .milliseconds(25), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.syncSelectionToPasteboard()
            }
            .store(in: &cancellables)
    }

    private func bindPreview() {
        viewModel.$previewItem
            .receive(on: RunLoop.main)
            .sink { [weak self] item in
                guard let self = self else { return }
                if let item = item { self.showPreview(item) } else { self.hidePreview() }
            }
            .store(in: &cancellables)
    }

    private func showPreview(_ item: ClipItem) {
        guard let parent = panel, parent.isVisible,
              let container = parent.contentView else { return }

        let popover = previewPopover ?? {
            let p = NSPopover()
            p.behavior = .applicationDefined
            p.animates = true
            p.appearance = NSAppearance(named: .darkAqua)
            p.contentSize = NSSize(width: 860, height: 520)
            p.contentViewController = NSHostingController(rootView: PreviewHost(model: viewModel))
            previewPopover = p
            return p
        }()

        let anchor = previewAnchor(for: item, in: container)
        if popover.isShown { popover.close() }
        popover.show(relativeTo: anchor, of: container, preferredEdge: .maxY)
    }

    /// The selected card's rect in the panel content view, so the popover arrow
    /// lands on the item. Falls back to the panel's top edge before the first
    /// layout pass has reported card frames.
    private func previewAnchor(for item: ClipItem, in container: NSView) -> NSRect {
        let index = viewModel.items.firstIndex { $0.id == item.id } ?? viewModel.selection
        if let card = viewModel.cardFrames[index], card.width > 1, card.height > 1 {
            return NSRect(x: card.minX,
                          y: container.bounds.height - card.maxY,
                          width: card.width,
                          height: card.height)
        }
        return NSRect(x: container.bounds.midX - 40,
                      y: container.bounds.height - 8,
                      width: 80,
                      height: 8)
    }

    private func hidePreview() {
        previewPopover?.close()
    }

    private func syncSelectionToPasteboard() {
        guard isPanelVisible, let item = viewModel.selectedItem else { return }
        guard item.id != lastSyncedSelectionID else { return }
        lastSyncedSelectionID = item.id
        syncGeneration += 1
        let generation = syncGeneration

        if item.kind == .image, item.data == nil {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let data = ImageStore.fullData(forID: item.id)
                DispatchQueue.main.async {
                    guard let self = self, generation == self.syncGeneration else { return }
                    var resolved = item
                    resolved.data = data
                    self.writePasteboard(resolved)
                }
            }
        } else {
            writePasteboard(item)
        }
    }

    private func writePasteboard(_ item: ClipItem) {
        monitor.suppressCurrentState()
        do {
            try PasteboardWriter.write(item)
        } catch {
            NSLog("Clippet: selection sync failed: \(error)")
        }
        monitor.suppressCurrentState()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isPanelVisible else { return event }

            guard let window = event.window,
                  window === self.panel
                    || window === self.previewPopover?.contentViewController?.view.window else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private var isComposingText: Bool {
        searchFieldEditor?.hasMarkedText() ?? false
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let context = KeyContext(previewOpen: viewModel.previewItem != nil,
                                 filtersOpen: viewModel.filtersOpen,
                                 queryEmpty: viewModel.query.isEmpty,
                                 boardCount: viewModel.boards.count)

        if event.keyCode == 49,
           SpaceRouter.shouldPreview(isComposing: isComposingText,
                                     previewOpen: viewModel.previewItem != nil,
                                     filtersOpen: viewModel.filtersOpen,
                                     queryEmpty: viewModel.query.isEmpty,
                                     isNavigating: viewModel.isNavigating,
                                     hasSelection: viewModel.selectedItem != nil),
           let item = viewModel.selectedItem {
            viewModel.previewItem = item
            return true
        }

        let action = KeyRouter.resolve(keyCode: event.keyCode,
                                       modifiers: event.modifierFlags,
                                       characters: event.charactersIgnoringModifiers,
                                       context: context)

        switch action {
        case .passThrough:
            return false

        case .beginSearch:
            viewModel.beginSearch()
            focusSearchField()
            return true

        case .selectAllText:
            if let editor = searchFieldEditor {
                editor.selectAll(nil)
            } else {

                focusSearchField()
                withSearchField { _, editor in editor?.selectAll(nil) }
            }
            return true

        case .selectAllCards:
            viewModel.selectAllVisible()
            return true

        case .closePreview:
            viewModel.previewItem = nil
            return true

        case .closeFilters:
            viewModel.filtersOpen = false
            return true

        case .preview:
            guard let item = viewModel.selectedItem else { return false }
            viewModel.previewItem = item
            return true

        case .switchBoard(let delta):
            viewModel.switchBoard(by: delta)
            return true

        case .quickPaste(let index):
            guard index - 1 < viewModel.items.count else { return true }
            viewModel.jump(to: index - 1)
            viewModel.commitSelection()
            return true
        }
    }

    private func searchTextField() -> KeyCommandTextField? {
        guard let content = panel?.contentView else { return nil }
        func find(_ view: NSView) -> KeyCommandTextField? {
            if let field = view as? KeyCommandTextField { return field }
            for sub in view.subviews {
                if let match = find(sub) { return match }
            }
            return nil
        }
        return find(content)
    }

    private var searchFieldEditor: NSTextView? {
        searchTextField()?.currentEditor() as? NSTextView
    }

    private func focusSearchField() {
        guard let field = searchTextField() else {
            NSLog("Clippet: search field not found in hierarchy")
            return
        }
        let ok = panel?.makeFirstResponder(field) ?? false
        NSLog("Clippet: focus search field ok=\(ok) responder=\(String(describing: panel?.firstResponder.map { type(of: $0) }))")
    }

    private func withSearchField(_ body: @escaping (KeyCommandTextField, NSTextView?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let field = self.searchTextField() else { return }
            body(field, field.currentEditor() as? NSTextView)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let icon = MenuBarIcon.make()
            icon.isTemplate = true
            button.image = icon
            button.toolTip = "Clippet"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "显示剪贴板历史",
                     action: #selector(menuToggle), keyEquivalent: "").target = self
        menu.addItem(withTitle: "预览选中内容",
                     action: #selector(menuPreview), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "粘贴堆栈",
                     action: #selector(menuPasteStack), keyEquivalent: "").target = self
        menu.addItem(withTitle: "开关堆栈模式",
                     action: #selector(menuToggleStack), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…",
                     action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Clippet",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self

        item.menu = menu
        statusItem = item
        statusItem?.isVisible = settings.showMenuBarIcon
        NSLog("Clippet: status item created image=%@ visible=%d", String(describing: buttonImageDescription(item)), item.isVisible ? 1 : 0)
    }

    private func buttonImageDescription(_ item: NSStatusItem) -> String {
        guard let img = item.button?.image else { return "nil" }
        return "\(img.size.width)x\(img.size.height) template=\(img.isTemplate)"
    }

    /// Called once when the app first becomes active: constructing the menu
    /// pulls in ~25 MB of AppKit menu machinery that is useless while idle.
    @objc func ensureMainMenu() {
        guard NSApp.mainMenu == nil else { return }
        setupMainMenu()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Clippet",
                        action: #selector(menuAbout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…",
                        action: #selector(menuSettings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Clippet",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Clippet",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All",
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let historyItem = NSMenuItem()
        mainMenu.addItem(historyItem)
        let historyMenu = NSMenu(title: "History")
        historyItem.submenu = historyMenu
        historyMenu.addItem(withTitle: "Show History",
                            action: #selector(menuToggle), keyEquivalent: "").target = self
        historyMenu.addItem(withTitle: "Preview Selected Clip",
                            action: #selector(menuPreview), keyEquivalent: "").target = self
        historyMenu.addItem(.separator())
        historyMenu.addItem(withTitle: "Paste Stack",
                            action: #selector(menuPasteStack), keyEquivalent: "").target = self
        historyMenu.addItem(withTitle: "Toggle Stack Mode",
                            action: #selector(menuToggleStack), keyEquivalent: "").target = self
        historyMenu.addItem(.separator())
        historyMenu.addItem(withTitle: "Next Pinboard",
                            action: #selector(menuNextBoard), keyEquivalent: "").target = self
        historyMenu.addItem(withTitle: "Previous Pinboard",
                            action: #selector(menuPreviousBoard), keyEquivalent: "").target = self
        historyMenu.addItem(.separator())
        historyMenu.addItem(withTitle: "Clear History…",
                            action: #selector(menuClear), keyEquivalent: "").target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close",
                           action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSLog("Clippet: main menu installed items=%@ active=%d policy=%d",
              mainMenu.items.map(\.title).description, NSApp.isActive ? 1 : 0,
              NSApp.activationPolicy().rawValue)
    }

    @objc private func menuAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Clippet"])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuPreview() {
        guard let item = viewModel.selectedItem else { return }
        viewModel.previewItem = item
    }

    @objc private func menuNextBoard() {
        viewModel.switchBoard(by: 1)
    }

    @objc private func menuPreviousBoard() {
        viewModel.switchBoard(by: -1)
    }

    private func applyRetention() {
        repository.trim(capacity: settings.maxItems)
        if let cutoff = settings.retentionCutoff {
            repository.deleteOlderThan(cutoff)
        }
    }

    private func bindSettings() {
        ContentClassifier.ignoreTransientContent = settings.ignoreTransient
        settings.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] visible in self?.statusItem?.isVisible = visible }
            .store(in: &cancellables)
        settings.$ignoreTransient
            .receive(on: RunLoop.main)
            .sink { ContentClassifier.ignoreTransientContent = $0 }
            .store(in: &cancellables)
        settings.$maxItems
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyRetention() }
            .store(in: &cancellables)
        settings.$retentionDays
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyRetention() }
            .store(in: &cancellables)
    }

    @objc private func menuSettings() {
        showSettingsWindow()
    }

    func showSettingsWindow() {
        let apps = repository.apps().map {
            AppUsage(bundleID: $0.bundleID, name: $0.name, count: $0.count)
        }

        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Clippet 设置"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        var initial: SettingsPane = .general
#if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "--settings-pane"),
           i + 1 < CommandLine.arguments.count,
           let pane = SettingsPane(rawValue: CommandLine.arguments[i + 1]) {
            initial = pane
        }
#endif
        settingsWindow?.contentView = NSHostingView(
            rootView: SettingsView(settings: settings, knownApps: apps, initialPane: initial))
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func pasteSingle(_ item: ClipItem) {

        let plainText = settings.alwaysPlainText || NSEvent.modifierFlags.contains(.option)
        hidePanel()
        monitor.suppressCurrentState()
        if settings.pasteToActiveApp {
            PasteboardWriter.paste(item, into: targetApp, plainTextOnly: plainText)
        } else {

            try? PasteboardWriter.write(item, plainTextOnly: plainText)
        }
    }

    private func pasteStack() {
        let queued = stack.items
        guard !queued.isEmpty else {
            NSSound.beep()
            return
        }
        hidePanel()
        pasteSequentially(queued, index: 0)
    }

    private func pasteSequentially(_ queued: [ClipItem], index: Int) {
        guard index < queued.count else {
            stack.clear()
            return
        }
        do {
            try PasteboardWriter.write(queued[index])
        } catch {
            NSLog("Clippet: stack write failed: \(error)")
            pasteSequentially(queued, index: index + 1)
            return
        }
        monitor.suppressCurrentState()
        PasteboardWriter.activate(targetApp)

        let settle: TimeInterval = index == 0 ? 0.12 : 0.16
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            PasteboardWriter.sendPaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                self?.pasteSequentially(queued, index: index + 1)
            }
        }
    }

    @objc private func menuToggle() { showPanel() }

    @objc private func menuPasteStack() { pasteStack() }

    @objc private func menuToggleStack() {
        stack.isEnabled.toggle()
        viewModel.stackEnabled = stack.isEnabled
        if !stack.isEnabled { stack.clear() }
    }

    @objc private func menuClear() {
        repository.clearHistory()
        ImageStore.purge()
        viewModel.reload(resetSelection: true)
    }

    @objc private func menuAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}

extension AppController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard let toggle = menu.item(withTitle: "Stack Mode") else { return }
        toggle.state = stack.isEnabled ? .on : .off
    }
}
