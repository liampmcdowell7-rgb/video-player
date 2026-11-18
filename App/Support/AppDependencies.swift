import Foundation
import CloudKit
import UserData
import LibraryBackup
import AppLogic

/// Every Apple-only dependency the app needs, built in one place (launch safety, docs/API_USAGE.md):
/// - nothing here touches iCloud, CloudKit, the App Group or the Keychain while it is being built;
/// - the CloudKit container is made on the first iCloud call, through `CloudKitGate`, and shared by the three adapters;
/// - the UI-test modes (Debug only) get in-memory stand-ins, so CI never depends on entitlements or an iCloud account.
struct AppDependencies {
    var userDataCloud: any UserDataCloud
    var secretCloud: any SecretCloud
    var credentials: any CredentialStore
    var backupCloud: any BackupCloud
    /// The App Group folder the Top Shelf extension reads, checked before use; nil when it cannot be used.
    var sharedFolder: () -> URL?
    /// Nil while iCloud can be used; the reason otherwise. The first call makes the CloudKit container.
    var cloudUnavailable: () -> CloudUnavailable?

    static func live() -> AppDependencies {
        let containers = CloudKitGate.containers()
        return AppDependencies(
            userDataCloud: CloudKitUserDataCloud(containers: containers),
            secretCloud: CloudKitSecretCloud(containers: containers),
            credentials: KeychainCredentialStore(),
            backupCloud: CloudKitBackupCloud(containers: containers),
            sharedFolder: {
                SharedFolder.usable(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedFolder.appGroup))
            },
            cloudUnavailable: { containers.unavailableReason() })
    }

    #if DEBUG
    /// UI-test modes (-UITestEmpty, -UITestFixtures): in-memory clouds and passwords, a plain folder in Caches instead of the
    /// App Group, and iCloud reported as off with the reason, so Settings shows a true sentence in the screenshots.
    static func uiTest() -> AppDependencies {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let off = CloudUnavailable("iCloud is off in UI-test mode.")
        return AppDependencies(
            userDataCloud: InMemoryCloud(),
            secretCloud: InMemorySecretCloud(),
            credentials: InMemoryCredentialStore(),
            backupCloud: InMemoryBackupCloud(),
            sharedFolder: { SharedFolder.usable(caches.appendingPathComponent("uitest-app-group", isDirectory: true)) },
            cloudUnavailable: { off })
    }
    #endif

    /// The dependencies for this launch: the stand-ins in a UI-test mode (Debug only), the real ones otherwise.
    static func forThisLaunch() -> AppDependencies {
        #if DEBUG
        if UITestMode.current != .off { return uiTest() }
        #endif
        return live()
    }
}

/// Makes the one CloudKit container on first use and turns the Objective-C exception CloudKit is reported to raise without
/// the iCloud entitlement (an unsigned build) into a reason the app shows, instead of a crash. Apple's page for
/// `CKContainer.init(identifier:)` says only that the identifier "must be in the app's ... entitlement"; what happens otherwise
/// is not documented, so the reason text says what was caught.
enum CloudKitGate {
    static func containers(identifier: String = UserDataModule.cloudKitContainerIdentifier) -> LazyCloudResource<CKContainer> {
        LazyCloudResource {
            var made: CKContainer?
            if let problem = VPCatchException({ made = CKContainer(identifier: identifier) }) {
                NSLog("Video Player: iCloud container could not be created: %@", problem)
                return .failure(CloudUnavailable("iCloud is not available in this copy of the app (\(problem))."))
            }
            guard let made else { return .failure(.notInThisBuild) }
            return .success(made)
        }
    }
}
