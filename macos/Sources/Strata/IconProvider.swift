// SPDX-License-Identifier: MIT

import AppKit
import QuickLookThumbnailing
import StrataCore
import UniformTypeIdentifiers

/// System file icons and Quick Look thumbnails, cached in memory.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private let icons = NSCache<NSString, NSImage>()
    private let thumbnails = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage?) -> Void]] = [:]

    private init() {
        icons.countLimit = 2_000
        thumbnails.countLimit = 600
    }

    /// Folders, packages, and links get their own icon; other files share one per type.
    func icon(for entry: FileEntry) -> NSImage {
        let perItem = entry.isFolder || entry.isPackage || entry.isSymbolicLink
        let key = (perItem ? entry.url.path : "type:" + (entry.typeIdentifier ?? "public.data")) as NSString
        if let cached = icons.object(forKey: key) { return cached }
        let image: NSImage
        if perItem {
            image = NSWorkspace.shared.icon(forFile: entry.url.path)
        } else {
            let type = entry.typeIdentifier.flatMap(UTType.init) ?? .data
            image = NSWorkspace.shared.icon(for: type)
        }
        icons.setObject(image, forKey: key)
        return image
    }

    func cachedThumbnail(for entry: FileEntry, size: CGFloat) -> NSImage? {
        thumbnails.object(forKey: thumbnailKey(entry, size) as NSString)
    }

    /// Calls `completion` on the main actor with a thumbnail, or nil when Quick
    /// Look has none beyond the type icon.
    func thumbnail(for entry: FileEntry, size: CGFloat, completion: @escaping (NSImage?) -> Void) {
        let key = thumbnailKey(entry, size)
        if let cached = thumbnails.object(forKey: key as NSString) {
            completion(cached)
            return
        }
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: entry.url, size: CGSize(width: size, height: size), scale: scale,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.nsImage
            Task { @MainActor in
                let shared = IconProvider.shared
                if let image { shared.thumbnails.setObject(image, forKey: key as NSString) }
                let callbacks = shared.pending.removeValue(forKey: key) ?? []
                callbacks.forEach { $0(image) }
            }
        }
    }

    private func thumbnailKey(_ entry: FileEntry, _ size: CGFloat) -> String {
        let stamp = entry.modified?.timeIntervalSinceReferenceDate ?? 0
        return "\(entry.url.path)|\(stamp)|\(entry.size ?? 0)|\(Int(size))"
    }

    /// A tinted SF Symbol for interface controls.
    static func symbol(_ name: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }
}
