#if canImport(CloudKit)
import CloudKit
import Foundation

/// The one place a `CKContainer` is made. Nothing makes it at app start: the adapters ask the shared `LazyCloudResource`
/// on their first call (launch safety, docs/API_USAGE.md). The app passes a maker that also catches the Objective-C
/// exception CloudKit is reported to raise when the app has no iCloud entitlement (App/Support/CloudKitGate.swift); Apple's
/// page for `init(identifier:)` only says the identifier "must be in the app's ... entitlement".
public enum CloudKitContainers {
    /// Plain maker (no exception guard): `CKContainer(identifier:)` on first use.
    public static func make(identifier: String = UserDataModule.cloudKitContainerIdentifier) -> LazyCloudResource<CKContainer> {
        LazyCloudResource { .success(CKContainer(identifier: identifier)) }
    }
}
#endif
