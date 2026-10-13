// SPDX-License-Identifier: MIT

import Foundation

public struct NavigationHistory: Sendable {
    public private(set) var current: URL
    private var back: [URL] = []
    private var forward: [URL] = []
    private let limit: Int

    public init(start: URL, limit: Int = 128) {
        current = start
        self.limit = limit
    }

    public var canGoBack: Bool { !back.isEmpty }
    public var canGoForward: Bool { !forward.isEmpty }

    public mutating func visit(_ location: URL) {
        guard location != current else { return }
        back.append(current)
        if back.count > limit { back.removeFirst(back.count - limit) }
        forward.removeAll()
        current = location
    }

    /// Follows a rename or deletion without adding a history entry.
    public mutating func replaceCurrent(with location: URL) {
        current = location
    }

    public mutating func goBack() -> URL? {
        guard let previous = back.popLast() else { return nil }
        forward.append(current)
        current = previous
        return previous
    }

    public mutating func goForward() -> URL? {
        guard let next = forward.popLast() else { return nil }
        back.append(current)
        current = next
        return next
    }
}
