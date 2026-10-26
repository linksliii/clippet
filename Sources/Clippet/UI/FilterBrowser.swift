import SwiftUI

enum DateFilter: String, CaseIterable, Identifiable {
    case today
    case last7
    case last30

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今天"
        case .last7: return "最近 7 天"
        case .last30: return "最近 30 天"
        }
    }

    var since: Date {
        switch self {
        case .today:
            return Calendar.current.startOfDay(for: Date())
        case .last7:
            return Date().addingTimeInterval(-7 * 86_400)
        case .last30:
            return Date().addingTimeInterval(-30 * 86_400)
        }
    }
}

struct FilterBrowser: View {
    @ObservedObject var model: ClipboardViewModel
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.3)

            VStack(alignment: .leading, spacing: 0) {
                typeSection
                divider
                appSection
                divider
                pinboardSection
                divider
                dateSection
            }
            .padding(.vertical, 6)
        }
        .frame(width: 292)
        .background(Color(hex: "#1E1E1E"))
    }

    private var header: some View {
        HStack {
            Text("筛选")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            if model.hasFilters {
                Button("清除") { model.clearFilters() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Design.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var divider: some View {
        Divider().opacity(0.18).padding(.vertical, 4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 3)
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark" : "")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(selected ? Design.accent : .clear)
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? .white : .white.opacity(0.75))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var typeSection: some View {
        Group {
            sectionHeader("类型")
            row("任意类型", selected: model.kindFilter == nil) { model.kindFilter = nil }
            ForEach(ClipKind.allCases.filter { $0 != .code }, id: \.self) { kind in
                row(kind.displayName, selected: model.kindFilter == kind) {
                    model.kindFilter = kind
                }
            }
        }
    }

    private var appSection: some View {
        Group {
            sectionHeader("应用")
            row("任意应用", selected: model.appFilter == nil) { model.appFilter = nil }
            ForEach(model.apps.prefix(6)) { app in
                row(app.name, selected: model.appFilter == app.bundleID) {
                    model.appFilter = app.bundleID
                }
            }
        }
    }

    private var pinboardSection: some View {
        Group {
            sectionHeader("面板")
            ForEach(model.boards) { board in
                row(board.name, selected: model.selectedBoardID == board.id) {
                    model.selectBoard(board.id)
                }
            }
        }
    }

    private var dateSection: some View {
        Group {
            sectionHeader("日期")
            row("任意时间", selected: model.dateFilter == nil) { model.dateFilter = nil }
            ForEach(DateFilter.allCases) { filter in
                row(filter.title, selected: model.dateFilter == filter) {
                    model.dateFilter = filter
                }
            }
        }
    }
}

struct FilterChip: View {
    let title: String
    let tint: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.30)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 1))
    }
}
