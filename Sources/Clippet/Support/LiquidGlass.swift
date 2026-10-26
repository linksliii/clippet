import AppKit
import ObjectiveC

enum LiquidGlass {

    private static let className = "NSGlassEffectView"

    static var isAvailable: Bool {

        _ = NSApplication.shared
        _ = NSVisualEffectView.self
        return NSClassFromString(className) != nil
    }

    static func makeBackground(cornerRadius: CGFloat) -> NSView? {
        guard isAvailable,
              let cls = NSClassFromString(className) as? NSView.Type else { return nil }
        let view = cls.init(frame: .zero)
        view.wantsLayer = true
        configure(view, cornerRadius: cornerRadius)
        return view
    }

    static func configure(_ view: NSView, cornerRadius: CGFloat) {
        set(view, "cornerRadius", cornerRadius)

        set(view, "style", 0)

        set(view, "effectIsInteractive", true)
        set(view, "_inverseMeshed", false)
    }

    private static func set(_ view: NSView, _ key: String, _ value: Any) {
        guard view.responds(to: NSSelectorFromString(key)) ||
              classHasProperty(type(of: view), key) else { return }
        view.setValue(value, forKey: key)
    }

    private static func classHasProperty(_ cls: AnyClass, _ name: String) -> Bool {
        var count: UInt32 = 0
        guard let props = class_copyPropertyList(cls, &count) else { return false }
        defer { free(props) }
        for i in 0..<Int(count) {
            if String(cString: property_getName(props[i])) == name { return true }
        }
        return false
    }
}

final class MaterialBackgroundView: NSView {
    private let effect = NSVisualEffectView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.autoresizingMask = [.width, .height]
        effect.wantsLayer = true
        addSubview(effect)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        effect.frame = bounds
        effect.layer?.cornerRadius = 18
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
    }
}
