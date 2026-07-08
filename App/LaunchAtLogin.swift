import ServiceManagement

// MARK: - Uruchamianie przy logowaniu (macOS 13+)

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            print("LaunchAtLogin: nie udało się zmienić ustawienia — \(error)")
        }
    }
}
