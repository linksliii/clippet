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
    private var previewPanel: ClipboardPanel?
    private var statusItem: NSStatusItem?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private var lastSyncedSelectionID: Int64?

    private var syncGeneration = 0

    private var isAnimatingOut = false

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

    func start() {

        ImageStore.dataProvider = { [weak self] id in
            self?.repository.imageData(id: id)
        }
        PasteboardWriter.textProvider = { [weak self] id in
            self?.repository.fullText(id: id)
        }

        bindSettings()
        setupStatusItem()
        setupMainMenu()
        setupHotKeys()
        wireViewModel()
        wireMonitor()

        applyRetention()
        viewModel.reloadBoards()
        viewModel.reload(resetSelection: true)

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

    private func ensurePanel() -> ClipboardPanel {
        if let existing = panel { return existing }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let width = screen.frame.width
        let rect = NSRect(x: screen.frame.minX, y: 0,
                          width: width, height: Design.panelHeight)

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

    private func screenFrame() -> NSRect {
        screenForMouse().visibleFrame
    }

    private func targetFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        var y = visible.midY - size.height / 2

        if let saved = PanelFrameStore.savedFrame(), PanelFrameStore.isUsable(saved, on: screen) {

            let clamped = min(max(saved.origin.y, visible.minY),
                              visible.maxY - size.height)
            y = clamped
        }
        return NSRect(x: screen.frame.minX, y: y, width: size.width, height: size.height)
    }

    private func offscreenFrame(for target: NSRect, in visible: NSRect) -> NSRect {
        NSRect(x: target.origin.x,
               y: visible.minY - target.height - 8,
               width: target.width, height: target.height)
    }

    func showFromUser() { showPanel() }

    private func showPanel() {

        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = frontmost
        }

        let p = ensurePanel()
        let screen = screenForMouse()
        let visible = screen.visibleFrame
        let target = targetFrame(for: p.frame.size, on: screen)
        let start = offscreenFrame(for: target, in: visible)

        lastSyncedSelectionID = nil

        viewModel.reloadBoards()
        viewModel.reload(resetSelection: true)
        viewModel.clearMultiSelection()

        visibleSince = Date()
        p.setFrame(start, display: false)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKey()

        DispatchQueue.main.async { [weak p] in
            NSApp.activate(ignoringOtherApps: true)
            p?.makeKey()
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.38
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.08, 0.30, 1.0)
            ctx.allowsImplicitAnimation = true
            p.animator().setFrame(target, display: true)
            p.animator().alphaValue = 1.0
        }
        NSLog("Clippet: panel visible=\(p.isVisible) key=\(p.isKeyWindow) appActive=\(NSApp.isActive) frame=\(p.frame)")

        DispatchQueue.main.async { [weak self] in self?.focusSearchField() }
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

        PanelFrameStore.save(p.frame)
        isAnimatingOut = true

        let visible = screenFrame()
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
        })
    }

    func windowDidMove(_ notification: Notification) {

        guard !isAnimatingOut else { return }
        guard let p = panel, p.isVisible else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self = self, let p = self.panel, p.isVisible else { return }
            PanelFrameStore.save(p.frame)
        }
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
        guard let parent = panel, parent.isVisible else { return }

        let size = NSSize(width: 860, height: 520)
        let p = previewPanel ?? {
            let w = ClipboardPanel.transparent(size: size)
            w.level = .floating

            w.contentView = NSHostingView(rootView: PreviewHost(model: viewModel))
            previewPanel = w
            return w
        }()

        p.setContentSize(size)

        let origin = NSPoint(x: parent.frame.midX - size.width / 2,
                             y: parent.frame.midY - size.height / 2)
        p.setFrameOrigin(origin)
        p.alphaValue = 0
        if p.parent == nil { parent.addChildWindow(p, ordered: .above) }
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            p.animator().alphaValue = 1
        }
    }

    private func hidePreview() {
        guard let p = previewPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
        })
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
                  window === self.panel || window === self.previewPanel else { return event }
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
