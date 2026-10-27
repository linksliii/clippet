import AppKit
import SwiftUI

struct PreviewHost: View {
    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        if let item = model.previewItem {
            PreviewOverlay(item: item) { model.previewItem = nil }
                .id(item.id)
        } else {
            Color.clear
        }
    }
}

struct PreviewOverlay: View {
    let item: ClipItem
    let onClose: () -> Void

    @State private var fullImage: NSImage?
    @State private var isLoadingImage = false

    private var tint: Color {
        if let tint = item.sourceTint { return Color(hex: tint) }
        return Design.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.25)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(tint).frame(width: 9, height: 9)
            Text(item.kind.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text("·").foregroundStyle(.white.opacity(0.3))
            Text(item.createdAt.relativeLabel)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            if let app = item.sourceAppName {
                Text("·").foregroundStyle(.white.opacity(0.3))
                Text(app)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(item.sizeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text, .code:
            textPreview
        case .image:
            imagePreview
        case .link:
            linkPreview
        case .file:
            filePreview
        case .color:
            colorPreview
        }
    }

    private var textPreview: some View {
        let raw = item.text ?? ""
        let text = raw.count > 20_000
            ? String(raw.prefix(20_000)) + "\n\n…（已截断，共 \(raw.count) 字符）"
            : raw
        return ScrollView {
            Text(text)
                .font(item.kind == .code
                      ? .system(size: 12.5, design: .monospaced)
                      : .system(size: 13.5))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
        }
    }

    private var imagePreview: some View {
        ZStack {
            if let image = fullImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(18)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            guard fullImage == nil, !isLoadingImage else { return }
            isLoadingImage = true
            let id = item.id
            let image = await ImageStore.previewImageAsync(forID: id)
            if !Task.isCancelled, let image { fullImage = image }
            isLoadingImage = false
        }
    }

    private var linkPreview: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 54, weight: .ultraLight))
                .foregroundStyle(tint.opacity(0.85))
            if let title = item.linkTitle {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
            }
            Text(item.text ?? "")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
            Button("在浏览器中打开") {
                if let t = item.text, let url = URL(string: t) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var filePreview: some View {
        VStack(spacing: 14) {
            Spacer()
            if let path = item.paths.first, let icon = ImageStore.fileIcon(forPath: path) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
            }
            Text(item.filename ?? "文件")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
            Text(item.paths.first ?? "")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .textSelection(.enabled)
            Button("在访达中显示") {
                if let path = item.paths.first {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private var colorPreview: some View {
        VStack(spacing: 16) {
            Spacer()
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: item.text ?? "#000000"))
                .frame(height: 220)
                .padding(.horizontal, 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        .padding(.horizontal, 60)
                )
            Text((item.text ?? "").uppercased())
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}
