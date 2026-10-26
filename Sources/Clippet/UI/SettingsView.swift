import AppKit
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, paste, history, privacy, shortcuts, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .paste: return "粘贴"
        case .history: return "历史"
        case .privacy: return "隐私"
        case .shortcuts: return "快捷键"
        case .about: return "关于"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .paste: return "doc.on.clipboard"
        case .history: return "clock.arrow.circlepath"
        case .privacy: return "hand.raised"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var knownApps: [AppUsage]

    @State private var pane: SettingsPane

    init(settings: AppSettings, knownApps: [AppUsage], initialPane: SettingsPane = .general) {
        self.settings = settings
        self.knownApps = knownApps
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    detail
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 760, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { item in
                Button {
                    pane = item
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12))
                            .frame(width: 16)
                        Text(item.title)
                            .font(.system(size: 12.5))
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(pane == item ? Color.accentColor.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 184)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general: generalPane
        case .paste: pastePane
        case .history: historyPane
        case .privacy: privacyPane
        case .shortcuts: shortcutsPane
        case .about: aboutPane
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("启动") {
                SettingsToggleRow(title: "在菜单栏显示图标",
                                  subtitle: "在菜单栏驻留一个入口，随时打开剪贴板历史。",
                                  isOn: $settings.showMenuBarIcon)
                SettingsDivider()
                SettingsToggleRow(title: "登录时启动",
                                  subtitle: "登录系统时自动启动 Clippet。",
                                  isOn: $settings.openAtLogin)
            }
            SettingsGroup("反馈") {
                SettingsToggleRow(title: "音效",
                                  subtitle: "捕获新的剪贴板内容时播放提示音。",
                                  isOn: $settings.playSound)
            }
        }
    }

    private var pastePane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("粘贴行为") {
                SettingsPickerRow(title: "粘贴目标",
                                  subtitle: "选中内容送达的位置。",
                                  selection: $settings.pasteToActiveApp) {
                    Text("到当前应用").tag(true)
                    Text("仅到剪贴板").tag(false)
                }
                SettingsDivider()
                SettingsToggleRow(title: "始终作为纯文本粘贴",
                                  subtitle: "丢弃富文本格式，只粘贴文字。",
                                  isOn: $settings.alwaysPlainText)
            }
        }
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("历史保留") {
                SettingsPickerRow(title: "保留时长",
                                  subtitle: "超过时长的内容会被自动清理。",
                                  selection: $settings.retentionDays) {
                    Text("永久").tag(0)
                    Text("1 天").tag(1)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
                SettingsDivider()
                SettingsPickerRow(title: "最大条数",
                                  subtitle: "存储条目的数量上限。",
                                  selection: $settings.maxItems) {
                    Text("500").tag(500)
                    Text("1,000").tag(1000)
                    Text("5,000").tag(5000)
                    Text("10,000").tag(10000)
                }
            }
        }
    }

    private var privacyPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("内容") {
                SettingsToggleRow(title: "忽略临时内容",
                                  subtitle: "跳过被其他应用标记为临时的数据。",
                                  isOn: $settings.ignoreTransient)
                SettingsDivider()
                SettingsToggleRow(title: "忽略敏感内容",
                                  subtitle: "跳过形似密码、密钥的敏感内容。",
                                  isOn: $settings.ignoreConfidential)
            }
            SettingsGroup("忽略的应用",
                          footnote: "从这些应用复制的内容不会被保存。") {
                if knownApps.isEmpty {
                    Text("还没有记录任何应用")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                } else {
                    ForEach(Array(knownApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 { SettingsDivider() }
                        SettingsToggleRow(title: app.name,
                                          subtitle: app.bundleID,
                                          isOn: Binding(
                                            get: { settings.ignoredApps.contains(app.bundleID) },
                                            set: { settings.setAppIgnored(app.bundleID, $0) }))
                    }
                }
            }
        }
    }

    private var shortcutsPane: some View {
        SettingsGroup("快捷键",
                      footnote: "与 Paste 默认键位一致，暂不支持自定义录制。") {
            ForEach(Array(ShortcutCatalog.all.enumerated()), id: \.offset) { index, entry in
                if index > 0 { SettingsDivider() }
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title)
                            .font(.system(size: 12.5))
                        Text(entry.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(entry.keys)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.07)))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "版本 \(version)（\(build)）"
    }

    private var aboutPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsGroup("Clippet") {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clippet")
                            .font(.system(size: 14, weight: .semibold))
                        Text(Self.versionLabel)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            SettingsGroup("存储") {
                SettingsRow(title: "历史数据库",
                            detail: "~/Library/Application Support/Clippet/clippet.db")
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    var footnote: String?
    @ViewBuilder var content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content }
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
            if let footnote = footnote {
                Text(footnote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider().opacity(0.4).padding(.leading, 12)
    }
}

private struct SettingsRow: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack {
            Text(title).font(.system(size: 12.5))
            Spacer()
            if let detail = detail {
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct SettingsPickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    var subtitle: String?
    @Binding var selection: Selection
    @ViewBuilder var options: () -> Options

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12.5))
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("", selection: $selection) { options() }
                .labelsHidden()
                .frame(width: 150)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

enum ShortcutCatalog {
    struct Entry {
        let title: String
        let detail: String
        let keys: String
    }

    static let all: [Entry] = [
        .init(title: "呼出面板",
              detail: "显示或隐藏剪贴板历史",
              keys: "⌘⇧V"),
        .init(title: "Paste Stack",
              detail: "按顺序粘贴队列中的内容",
              keys: "⌘⇧C"),
        .init(title: "下一个面板",
              detail: "切换到下一个标签页",
              keys: "⌘→"),
        .init(title: "上一个面板",
              detail: "切换到上一个标签页",
              keys: "⌘←"),
        .init(title: "快速粘贴",
              detail: "直接粘贴第 N 条内容",
              keys: "⌘1 – ⌘9"),
        .init(title: "纯文本模式",
              detail: "去掉格式后粘贴",
              keys: "⌥↵"),
        .init(title: "预览",
              detail: "打开全尺寸预览窗口",
              keys: "space / ⌘Y"),
        .init(title: "全选",
              detail: "选中查询文字，输入框为空时选中全部卡片",
              keys: "⌘A / ⌃A"),
        .init(title: "逐层关闭",
              detail: "浮层 → 搜索词 → 预览 → 面板",
              keys: "esc")
    ]
}
