import Foundation

/// The one place where the object graph is wired. Change construction here only.
@MainActor
final class AppEnvironment {
    let settings: SettingsStore
    let credentials: any CredentialStoring
    let store: DeviceStore

    init() {
        let quota = QuotaLedger()
        let keychain = KeychainCredentialStore()
        let cache = DiskDeviceCache()
        let cloud = CloudClient(credentials: keychain, quota: quota)
        let lan = LANService()
        let settings = SettingsStore()

        self.settings = settings
        self.credentials = keychain
        self.store = DeviceStore(
            cloud: cloud,
            lan: lan,
            quota: quota,
            cache: cache,
            credentials: keychain,
            settings: settings
        )
    }
}
