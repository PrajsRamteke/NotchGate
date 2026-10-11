import Foundation

extension StatusLineInstaller {
    /// The relay feeds every status line widget, so it only comes out once none of them is on.
    @MainActor
    func removeIfUnused(_ settings: AppSettings) throws {
        guard !settings.usageWidget, !settings.sessionWidget else { return }
        try uninstall()
    }
}
