import Foundation
import AppKit

public struct ExternalEditor {
    public static let supportedBundleIdentifiers = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.Zed"
    ]

    public typealias AppFinder = (String) -> URL?
    public typealias AsyncFileOpener = ([URL], URL, @escaping (Bool) -> Void) -> Void
    public typealias AsyncURLOpener = (URL, @escaping (Bool) -> Void) -> Void

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

    /// Opens the specified file or directory path in the preferred external editor (VS Code, Cursor, Zed) asynchronously,
    /// or falls back to the system default application only if the preferred editor launch fails.
    public static func open(
        path: String,
        appFinder: AppFinder = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileOpener: @escaping AsyncFileOpener = { urls, appURL, completion in
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { _, error in
                completion(error == nil)
            }
        },
        defaultOpener: @escaping AsyncURLOpener = { url, completion in
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open(url, configuration: config) { _, error in
                completion(error == nil)
            }
        },
        completion: ((Bool) -> Void)? = nil
    ) {
        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardized
        if let (_, appURL) = preferredEditorURL(appFinder: appFinder) {
            fileOpener([fileURL], appURL) { success in
                if success {
                    completion?(true)
                } else {
                    // Preferred editor failed to open, fallback to default
                    defaultOpener(fileURL) { defaultSuccess in
                        completion?(defaultSuccess)
                    }
                }
            }
        } else {
            defaultOpener(fileURL) { defaultSuccess in
                completion?(defaultSuccess)
            }
        }
    }
}
