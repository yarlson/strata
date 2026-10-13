// SPDX-License-Identifier: MIT

import AppKit

/// A layer-backed view with an optional system background color and a
/// separator line along one edge. Both follow light and dark appearance.
class PaneView: NSView {
    var fillColor: NSColor? {
        didSet { needsDisplay = true }
    }
    var separatorEdge: NSRectEdge? {
        didSet { needsDisplay = true }
    }

    init(fill: NSColor? = nil) {
        fillColor = fill
        super.init(frame: .zero)
        wantsLayer = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged), name: Appearance.didChange, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = fillColor?.cgColor
            if let edge = separatorEdge {
                applySeparator(edge, NSColor.separatorColor.cgColor)
            }
        }
    }

    @objc private func appearanceChanged() {
        appearanceDidChange()
    }

    /// Subclasses restyle their content here; call super.
    func appearanceDidChange() {
        needsDisplay = true
    }

    private func applySeparator(_ edge: NSRectEdge, _ color: CGColor) {
        let name = "strata-separator"
        let line =
            layer?.sublayers?.first { $0.name == name }
            ?? {
                let line = CALayer()
                line.name = name
                layer?.addSublayer(line)
                return line
            }()
        line.backgroundColor = color
        let bounds = layer?.bounds ?? .zero
        switch edge {
        case .minY: line.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
        case .maxY: line.frame = CGRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        case .minX: line.frame = CGRect(x: 0, y: 0, width: 1, height: bounds.height)
        case .maxX: line.frame = CGRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        @unknown default: break
        }
    }

    override func layout() {
        super.layout()
        if separatorEdge != nil { needsDisplay = true }
    }
}

extension NSTextField {
    static func scaledLabel(
        _ text: String = "", color: NSColor = .labelColor, scale: CGFloat = 1, weight: NSFont.Weight = .regular
    ) -> ScaledLabel {
        let label = ScaledLabel(scale: scale, weight: weight)
        label.textColor = color
        label.stringValue = text
        return label
    }
}

/// A non-editable label whose font follows the text size preference.
final class ScaledLabel: NSTextField {
    var scale: CGFloat { didSet { restyle() } }
    var weight: NSFont.Weight { didSet { restyle() } }

    init(scale: CGFloat, weight: NSFont.Weight) {
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
    }
}
