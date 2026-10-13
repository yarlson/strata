// SPDX-License-Identifier: MIT

import AppKit

/// A layer-backed view filled with a palette color that follows theme and
/// system appearance changes.
class ThemedView: NSView {
    var fillColor: KeyPath<Palette, NSColor>? {
        didSet { needsDisplay = true }
    }
    var borderEdges: NSRectEdge? {
        didSet { needsDisplay = true }
    }
    init(fill: KeyPath<Palette, NSColor>? = \.background) {
        fillColor = fill
        super.init(frame: .zero)
        wantsLayer = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(themeChanged), name: Appearance.didChange, object: nil
        )
    }

    @objc private func themeChanged() {
        appearanceDidChange()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let palette = Appearance.shared.palette
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor.map { palette[keyPath: $0].cgColor }
            if let edge = borderEdges {
                applyBorder(edge, palette.border.cgColor)
            }
        }
    }

    /// Subclasses restyle their content here; call super.
    func appearanceDidChange() {
        needsDisplay = true
    }

    private func applyBorder(_ edge: NSRectEdge, _ color: CGColor) {
        let name = "strata-border"
        let border =
            layer?.sublayers?.first { $0.name == name }
            ?? {
                let line = CALayer()
                line.name = name
                layer?.addSublayer(line)
                return line
            }()
        border.backgroundColor = color
        border.autoresizingMask = []
        let bounds = layer?.bounds ?? .zero
        switch edge {
        case .minY: border.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        case .maxY: border.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        case .minX: border.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        case .maxX: border.frame = CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        @unknown default: break
        }
    }

    override func layout() {
        super.layout()
        if borderEdges != nil { needsDisplay = true }
    }
}

extension NSTextField {
    static func themedLabel(
        _ text: String = "", color: KeyPath<Palette, NSColor> = \.text, scale: CGFloat = 1,
        weight: NSFont.Weight = .regular
    ) -> ThemedLabel {
        let label = ThemedLabel(color: color, scale: scale, weight: weight)
        label.stringValue = text
        return label
    }
}

/// A non-editable label that restyles itself when the theme or text size changes.
final class ThemedLabel: NSTextField {
    var color: KeyPath<Palette, NSColor> { didSet { restyle() } }
    var scale: CGFloat { didSet { restyle() } }
    var weight: NSFont.Weight { didSet { restyle() } }
    init(color: KeyPath<Palette, NSColor>, scale: CGFloat, weight: NSFont.Weight) {
        self.color = color
        self.scale = scale
        self.weight = weight
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        lineBreakMode = .byTruncatingTail
        cell?.truncatesLastVisibleLine = true
        restyle()
        NotificationCenter.default.addObserver(
            self, selector: #selector(restyle), name: Appearance.didChange, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func restyle() {
        font = Appearance.shared.font(scale: scale, weight: weight)
        textColor = Appearance.shared.palette[keyPath: color]
    }
}
