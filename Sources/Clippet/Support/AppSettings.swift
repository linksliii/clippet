import AppKit
import Combine
import ServiceManagement

final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private enum Key {
        static let retentionDays = "settings.retentionDays"
        static let maxItems = "settings.maxItems"
        static let pasteToActiveApp = "settings.pasteToActiveApp"
        static let alwaysPlainText = "settings.alwaysPlainText"
        static let ignoreTransient = "settings.ignoreTransient"
        static let ignoreConfidential = "settings.ignoreConfidential"
        static let ignoredApps = "settings.ignoredApps"
        static let playSound = "settings.playSound"
        static let showMenuBarIcon = "settings.showMenuBarIcon"
        static let openAtLogin = "settings.openAtLogin"
    }

    private let defaults = UserDefaults.standard

    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Key.retentionDays) }
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }

    @Published var pasteToActiveApp: Bool {
        didSet { defaults.set(pasteToActiveApp, forKey: Key.pasteToActiveApp) }
    }
    @Published var alwaysPlainText: Bool {
        didSet { defaults.set(alwaysPlainText, forKey: Key.alwaysPlainText) }
    }

    @Published var ignoreTransient: Bool {
        didSet { defaults.set(ignoreTransient, forKey: Key.ignoreTransient) }
    }

    @Published var ignoreConfidential: Bool {
        didSet { defaults.set(ignoreConfidential, forKey: Key.ignoreConfidential) }
    }

    @Published var ignoredApps: Set<String> {
        didSet { defaults.set(Array(ignoredApps), forKey: Key.ignoredApps) }
    }

    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }
    @Published var openAtLogin: Bool {
        didSet {
            defaults.set(openAtLogin, forKey: Key.openAtLogin)
            applyOpenAtLogin()
        }
    }

    private init() {
        retentionDays = defaults.object(forKey: Key.retentionDays) as? Int ?? 0
        maxItems = defaults.object(forKey: Key.maxItems) as? Int ?? 5000
        pasteToActiveApp = defaults.object(forKey: Key.pasteToActiveApp) as? Bool ?? true
        alwaysPlainText = defaults.object(forKey: Key.alwaysPlainText) as? Bool ?? false
        ignoreTransient = defaults.object(forKey: Key.ignoreTransient) as? Bool ?? true
        ignoreConfidential = defaults.object(forKey: Key.ignoreConfidential) as? Bool ?? false
        ignoredApps = Set(defaults.stringArray(forKey: Key.ignoredApps) ?? [])
        playSound = defaults.object(forKey: Key.playSound) as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
        openAtLogin = defaults.object(forKey: Key.openAtLogin) as? Bool ?? false
    }

    var retentionCutoff: Date? {
        guard retentionDays > 0 else { return nil }
        return Date().addingTimeInterval(-Double(retentionDays) * 86_400)
    }

    func isAppIgnored(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID else { return false }
        return ignoredApps.contains(bundleID)
    }

    func setAppIgnored(_ bundleID: String, _ ignored: Bool) {
        if ignored { ignoredApps.insert(bundleID) } else { ignoredApps.remove(bundleID) }
    }

    private func applyOpenAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if openAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Clippet: launch-at-login failed: \(error)")
        }
    }
}
