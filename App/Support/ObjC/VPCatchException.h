#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and returns nil when it finished, or "name: reason" when it raised an Objective-C exception.
/// Used only around `CKContainer(identifier:)` (App/Support/CloudKitGate.swift): CloudKit is reported to raise an exception
/// when the app has no iCloud entitlement (an unsigned build), which would otherwise end the app. Swift cannot catch it.
FOUNDATION_EXPORT NSString * _Nullable VPCatchException(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
