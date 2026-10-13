// SPDX-License-Identifier: MIT

import AppKit

struct Volume: Equatable {
    let url: URL
    let name: String
    let isEjectable: Bool
    let isRoot: Bool
    let isLocal: Bool
}

/// Mounted volumes for the sidebar's Devices section, kept current from
/// workspace mount notifications.
@MainActor
final class VolumeMonitor {
    static let shared = VolumeMonitor()
    nonisolated static let didChange = Notification.Name("StrataVolumesDidChange")

    private(set) var volumes: [Volume] = []

    private init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ] {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { VolumeMonitor.shared.refresh() }
            }
        }
    }

    func refresh() {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeIsEjectableKey, .volumeIsRemovableKey,
            .volumeIsRootFileSystemKey, .volumeIsLocalKey,
        ]
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
            ) ?? []
        volumes = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Volume(
                url: url,
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                isEjectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false)
                    || !(values.volumeIsLocal ?? true),
                isRoot: values.volumeIsRootFileSystem ?? false,
                isLocal: values.volumeIsLocal ?? true
            )
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// Local volumes other than the startup disk, which home search already covers.
    var searchRoots: [URL] {
        volumes.filter { $0.isLocal && !$0.isRoot }.map(\.url)
    }

    func eject(_ volume: Volume, from window: NSWindow?) {
        let url = volume.url
        Task.detached {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            } catch {
                await MainActor.run {
                    Alerts.showError(
                        tr("Could not eject %{name}", ["name": quoted(volume.name)]),
                        detail: error.localizedDescription, window: window
                    )
                }
            }
        }
    }
}
