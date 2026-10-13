// SPDX-License-Identifier: MIT

import Foundation
import UniformTypeIdentifiers

public struct FileEntry: Hashable, Sendable, Identifiable {
    public let url: URL
    public let name: String
    /// A folder the browser can open, including a symbolic link to one.
    /// Packages such as `.app` bundles are files.
    public let isFolder: Bool
    public let isPackage: Bool
    public let isSymbolicLink: Bool
    public let isHidden: Bool
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    public let typeIdentifier: String?
    public let kindDescription: String?

    public var id: URL { url }

    public init(
        url: URL, name: String, isFolder: Bool, isPackage: Bool = false,
        isSymbolicLink: Bool = false, isHidden: Bool = false, size: Int64? = nil,
        modified: Date? = nil, created: Date? = nil, typeIdentifier: String? = nil,
        kindDescription: String? = nil
    ) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.created = created
        self.typeIdentifier = typeIdentifier
        self.kindDescription = kindDescription
    }

    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isHiddenKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .contentTypeKey,
        .localizedTypeDescriptionKey,
    ]

    /// Reads one item's metadata. Symbolic links report their target's kind.
    public init(url: URL) throws {
        let values = try url.resourceValues(forKeys: Set(Self.resourceKeys))
        let isLink = values.isSymbolicLink ?? false
        var target = values
        if isLink,
            let resolved = try? url.resolvingSymlinksInPath()
                .resourceValues(forKeys: Set(Self.resourceKeys))
        {
            target = resolved
        }
        let isDirectory = target.isDirectory ?? false
        let isPackage = target.isPackage ?? false
        self.init(
            url: url.canonical,
            name: values.name ?? url.lastPathComponent,
            isFolder: isDirectory && !isPackage,
            isPackage: isPackage,
            isSymbolicLink: isLink,
            isHidden: values.isHidden ?? url.lastPathComponent.hasPrefix("."),
            size: isDirectory ? nil : target.fileSize.map(Int64.init),
            modified: target.contentModificationDate,
            created: target.creationDate,
            typeIdentifier: target.contentType?.identifier,
            kindDescription: target.localizedTypeDescription
        )
    }
}

public enum DirectoryListing {
    /// Lists a directory, skipping items that vanish while it is read.
    public static func entries(of directory: URL) throws -> [FileEntry] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: FileEntry.resourceKeys,
            options: []
        )
        return urls.compactMap { try? FileEntry(url: $0) }
    }
}
