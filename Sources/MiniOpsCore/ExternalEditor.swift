import Foundation
import AppKit

public struct ExternalEditor {
    public static let supportedBundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed"
    ]

    public typealias AppFinder = (String) -> URL?
    public typealias URLOpener = (URL) -> Bool
    public typealias FileOpener = ([URL], URL) -> Bool

    /// Resolves the preferred editor application URL, if any of the supported editors are installed.
    public static func preferredEditorURL(
        appFinder: AppFinder = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    ) -> (bundleId: String, appURL: URL)? {
        for bundleId in supportedBundleIdentifiers {
            if let appURL = appFinder(bundleId) {
                return (bundleId, appURL)
            }
        }
        return nil
    }

    /// Opens the specified file or directory path in the preferred external editor (VS Code, Cursor, Zed),
    /// or falls back to the system default application.
    @discardableResult
    public static func open(
        path: String,
        appFinder: AppFinder = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileOpener: FileOpener = { urls, appURL in
            let config = NSWorkspace.OpenConfiguration()
            var opened = false
            let semaphore = DispatchSemaphore(value: 0)
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, error in
                opened = (error == nil)
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1.0)
            return opened
        },
        defaultOpener: URLOpener = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        let fileURL = URL(fileURLWithPath: path)
        if let (_, appURL) = preferredEditorURL(appFinder: appFinder) {
            if fileOpener([fileURL], appURL) {
                return true
            }
        }
        return defaultOpener(fileURL)
    }
}
