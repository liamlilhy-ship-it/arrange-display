import ServiceManagement

/// Launch-at-login via SMAppService — the modern login-item API, no
/// helper bundle and no permission prompt (the system just notifies
/// that the app was added as a login item). At login the app only
/// appears in the menu bar: nothing is applied and no panel opens.
enum LoginItem {
    /// Make the system registration match the setting; safe to call on
    /// every launch (registering while enabled is a no-op).
    static func sync(enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("LoginItem sync failed: \(error)")
        }
    }
}
