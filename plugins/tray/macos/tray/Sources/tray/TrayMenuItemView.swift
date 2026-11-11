import AppKit
import CoreText

// A native item leaves a fixed gap before its submenu arrow, so rows are drawn
// here to keep a detail next to the arrow. The metrics copy the native menu so
// these rows line up with the separators the menu still draws.
final class TrayMenuItemView: NSView {
    struct Content {
        let label: String
        let detail: String?
        let checked: Bool
        let enabled: Bool
        let hasSubmenu: Bool
    }

    private struct Metrics {
        let height: CGFloat
        let stateX: CGFloat
        let titleX: CGFloat
        let trailing: CGFloat
        let highlightInset: CGFloat
        let highlightRadius: CGFloat
        let font: NSFont

        static let current: Metrics = {
            if #available(macOS 26, *) {
                return Metrics(
                    height: 24,
                    stateX: 12,
                    titleX: 30,
                    trailing: 23,
                    highlightInset: 5,
                    highlightRadius: 8,
                    font: .menuFont(ofSize: 13)
                )
            }
            return Metrics(
                height: 22,
                stateX: 9,
                titleX: 21,
                trailing: 14,
                highlightInset: 5,
                highlightRadius: 4,
                font: .menuFont(ofSize: 0)
            )
        }()
    }

    private static let metrics = Metrics.current
    private static let detailGap: CGFloat = 20
    private static let arrowGap: CGFloat = 6
    private static let checkGap: CGFloat = 3

    private static let detailFont = NSFont.monospacedDigitSystemFont(
        ofSize: metrics.font.pointSize,
        weight: .regular
    )

    private static let checkmark = symbol("checkmark", weight: .medium)
    private static let arrow = symbol("chevron.right", weight: .semibold)

    private let content: Content

    init(content: Content) {
        self.content = content
        let metrics = TrayMenuItemView.metrics
        var width = metrics.titleX + TrayMenuItemView.labelWidth(content.label) + metrics.trailing
        if let detail = content.detail {
            width += TrayMenuItemView.detailGap + TrayMenuItemView.width(detail, font: TrayMenuItemView.detailFont)
        }
        if content.hasSubmenu {
            width += TrayMenuItemView.arrowGap + TrayMenuItemView.arrow.size.width
        }
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(width), height: metrics.height))
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel([content.label, content.detail].compactMap { $0 }.joined(separator: ", "))
        setAccessibilityEnabled(content.enabled)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    private var isHighlighted: Bool {
        content.enabled && enclosingMenuItem?.isHighlighted == true
    }

    override func draw(_ dirtyRect: NSRect) {
        let metrics = TrayMenuItemView.metrics
        let highlighted = isHighlighted
        if highlighted {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: metrics.highlightInset, dy: 0),
                xRadius: metrics.highlightRadius,
                yRadius: metrics.highlightRadius
            ).fill()
        }

        let primary: NSColor = highlighted
            ? .selectedMenuItemTextColor
            : content.enabled ? .labelColor : .tertiaryLabelColor
        if content.checked {
            drawSymbol(
                TrayMenuItemView.checkmark,
                x: metrics.stateX,
                color: primary,
                maxWidth: metrics.titleX - metrics.stateX - TrayMenuItemView.checkGap
            )
        }

        var trailingX = bounds.width - metrics.trailing
        if content.hasSubmenu {
            let arrowWidth = TrayMenuItemView.arrow.size.width
            drawSymbol(TrayMenuItemView.arrow, x: trailingX - arrowWidth, color: primary)
            trailingX -= arrowWidth + TrayMenuItemView.arrowGap
        }

        if let detail = content.detail {
            let color: NSColor = highlighted
                ? .selectedMenuItemTextColor
                : content.enabled ? .secondaryLabelColor : .tertiaryLabelColor
            let detailWidth = TrayMenuItemView.width(detail, font: TrayMenuItemView.detailFont)
            drawText(detail, x: trailingX - detailWidth, width: detailWidth, color: color, font: TrayMenuItemView.detailFont)
            trailingX -= detailWidth + TrayMenuItemView.detailGap
        }

        drawLabel(content.label, x: metrics.titleX, width: trailingX - metrics.titleX, color: primary)
    }

    override func mouseUp(with event: NSEvent) {
        guard content.enabled, !content.hasSubmenu, let item = enclosingMenuItem,
              let action = item.action else {
            return
        }
        var root = item.menu
        while let parent = root?.supermenu {
            root = parent
        }
        root?.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private func drawLabel(_ text: String, x: CGFloat, width: CGFloat, color: NSColor) {
        let string = TrayMenuItemView.label(text, color: color)
        let used = string.boundingRect(
            with: NSSize(width: max(width, 0), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
        let height = ceil(used.height)
        let rect = NSRect(x: x, y: (bounds.height - height) / 2, width: max(width, 0), height: height)
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func drawText(_ text: String, x: CGFloat, width: CGFloat, color: NSColor, font: NSFont) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let height = ceil(font.ascender - font.descender)
        let rect = NSRect(x: x, y: (bounds.height - height) / 2, width: max(width, 0), height: height)
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]
        )
    }

    // Before macOS 26 the title starts closer to the state column than a
    // checkmark at the menu font's size is wide, so the mark shrinks to fit.
    private func drawSymbol(_ image: NSImage, x: CGFloat, color: NSColor, maxWidth: CGFloat = .infinity) {
        let scale = min(1, maxWidth / image.size.width)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = NSRect(
            x: x,
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        let tinted = NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds)
            color.setFill()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private static func labelWidth(_ text: String) -> CGFloat {
        ceil(label(text, color: .labelColor).size().width)
    }

    private static func width(_ text: String, font: NSFont) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // Apple Color Emoji ships no Taiwan flag, so the menu font draws that pair
    // as a missing glyph. Both indicators stay in one run so Twemoji's ligature forms.
    private static func label(_ text: String, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: metrics.font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let flagAttributes: [NSAttributedString.Key: Any]? = TrayFlagFont.font.map {
            [.font: $0, .foregroundColor: color, .paragraphStyle: paragraph]
        }
        let result = NSMutableAttributedString()
        let scalars = text.unicodeScalars
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let next = scalars.index(after: index)
            if let flagAttributes,
               isRegionalIndicator(scalars[index]),
               next < scalars.endIndex,
               isRegionalIndicator(scalars[next]) {
                let end = scalars.index(after: next)
                result.append(
                    NSAttributedString(string: String(scalars[index..<end]), attributes: flagAttributes)
                )
                index = end
                continue
            }
            result.append(NSAttributedString(string: String(scalars[index]), attributes: textAttributes))
            index = next
        }
        return result
    }

    private static func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
        (0x1F1E6...0x1F1FF).contains(scalar.value)
    }

    private static func symbol(_ name: String, weight: NSFont.Weight) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: metrics.font.pointSize, weight: weight)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) ?? NSImage()
    }

    private enum TrayFlagFont {
        static let font: NSFont? = {
            guard let url = Bundle.main.privateFrameworksURL?
                .appendingPathComponent(
                    "App.framework/Resources/flutter_assets/assets/fonts/Twemoji.Mozilla.ttf"
                ),
                FileManager.default.fileExists(atPath: url.path)
            else {
                return nil
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, CTFontManagerScope.process, nil)
            return NSFont(name: "TwemojiCOLRv0-Regular", size: metrics.font.pointSize)
        }()
    }
}
