import AppKit
import SwiftUI

struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    let board: Board?

    var highlightTerms: [String] = []
    var isMultiSelecting: Bool = false
    var isMultiSelected: Bool = false

    @State private var isHovering = false

    private var tint: Color {
        if let boardTint = board?.tint, board?.isDefault == false {
            return Color(hex: boardTint)
        }
        if let sourceTint = item.sourceTint {
            return Color(hex: sourceTint)
        }
        return Color(hex: "#5E5CE6")
    }

    private var headerTitle: String {
        if let board = board, !board.isDefault { return board.name }
        return item.kind.displayName
    }

    private var bodyTextColor: Color { .white }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Design.cardBody)
            footer
        }
        .frame(width: Design.cardWidth, height: Design.cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? Design.accent : Design.cardHairline,
                              lineWidth: isSelected ? 2.5 : 1)
        )

        .shadow(color: isSelected ? Design.accent.opacity(0.55) : .clear,
                radius: isSelected ? 9 : 0)
        .scaleEffect(isHovering && !isSelected ? 1.006 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [tint.lightened(0.10), tint],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint.prefersDarkText ? Color.black.opacity(0.85) : .white)
                    .lineLimit(1)
                Text(item.createdAt.relativeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(tint.prefersDarkText
                                     ? Color.black.opacity(0.55) : Color.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(.leading, 12)
            .padding(.top, 9)

            HStack {
                Spacer()
                appIcon
            }
        }
        .frame(height: Design.headerHeight)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = AppTint.icon(forBundleID: item.sourceApp) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Design.headerIconSize, height: Design.headerIconSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.top, 3)
                .padding(.trailing, 5)
        } else if let board = board, !board.isDefault {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: Design.headerIconSize, height: Design.headerIconSize)
                .padding(.top, 3)
                .padding(.trailing, 5)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .code:
            textBody
        case .image:
            imageBody
        case .color:
            colorBody
        case .file:
            fileBody
        case .link:
            linkBody
        }
    }

    private var textBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if item.isSensitive {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.system(size: 8))
                    Text("敏感").font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(.red.opacity(0.9))
                .padding(.bottom, 4)
            }
            Text(highlightedBody)
                .font(item.kind == .code
                      ? .system(size: 12, design: .monospaced)
                      : .system(size: 13))
                .foregroundStyle(bodyTextColor)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .clipped()
    }

    private var displayText: String {
        let plain = item.text ?? ""
        guard !highlightTerms.isEmpty else { return plain }

        var earliest: Range<String.Index>?
        for term in highlightTerms where !term.isEmpty {
            if let found = plain.range(of: term, options: .caseInsensitive),
               earliest == nil || found.lowerBound < earliest!.lowerBound {
                earliest = found
            }
        }
        guard let match = earliest, match.lowerBound != plain.startIndex else { return plain }

        let lead = 36
        let distance = plain.distance(from: plain.startIndex, to: match.lowerBound)
        let start = plain.index(match.lowerBound, offsetBy: -min(lead, distance))
        return "…" + String(plain[start...])
    }

    private var highlightedBody: AttributedString {
        let plain = displayText
        var attributed = AttributedString(plain)
        guard !highlightTerms.isEmpty, !plain.isEmpty else { return attributed }

        for term in highlightTerms where !term.isEmpty {
            var searchStart = plain.startIndex
            while searchStart < plain.endIndex,
                  let found = plain.range(of: term,
                                          options: [.caseInsensitive],
                                          range: searchStart..<plain.endIndex) {
                if let range = Range(found, in: attributed) {
                    attributed[range].backgroundColor = Design.accent.opacity(0.55)
                    attributed[range].foregroundColor = .white
                }
                searchStart = found.upperBound
            }
        }
        return attributed
    }

    private var imageBody: some View {
        ZStack(alignment: .bottom) {
            CheckerboardView()
            Group {
                if let nsImage = ImageStore.thumbnail(forID: item.id) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            if let size = imageSizeLabel {
                Text(size)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .padding(.bottom, 8)
            }
        }
    }

    private var colorBody: some View {
        ZStack {
            if let hex = item.text {
                Color(hex: hex)
                Text(hex.uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: hex).prefersDarkText
                                     ? Color.black.opacity(0.75) : Color.white.opacity(0.95))
            } else {
                Color.gray
            }
        }
    }

    private var imageSizeLabel: String? {
        guard let data = ImageStore.fullData(forID: item.id),
              let size = ImageStore.pixelSize(forID: item.id, data: data) else { return nil }
        return "\(Int(size.width)) × \(Int(size.height))"
    }

    private var fileBody: some View {
        ZStack {
            if let path = item.paths.first, let icon = ImageStore.fileIcon(forPath: path) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
    }

    private var linkBody: some View {
        ZStack {
            Image(systemName: "globe")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.28))
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let title = item.linkTitle, item.kind == .link {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
            } else {
                Text(item.metaLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if isMultiSelecting {
                ZStack {
                    Circle()
                        .fill(isMultiSelected ? Design.accent : Color.clear)
                    Circle()
                        .strokeBorder(Color.white.opacity(isMultiSelected ? 0 : 0.4), lineWidth: 1.2)
                    if isMultiSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 15, height: 15)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .medium))
                    Text("\(index)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Design.cardBody)
    }
}

struct CheckerboardView: View {
    private static let tile: NSImage = {
        let s: CGFloat = 7
        let image = NSImage(size: NSSize(width: s * 2, height: s * 2))
        image.lockFocus()
        NSColor(white: 0.24, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s * 2, height: s * 2).fill()
        NSColor(white: 0.32, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: s, height: s).fill()
        NSRect(x: s, y: s, width: s, height: s).fill()
        image.unlockFocus()
        return image
    }()

    var body: some View {
        Image(nsImage: Self.tile)
            .resizable(resizingMode: .tile)
    }
}
