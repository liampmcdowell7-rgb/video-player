import Foundation
import XCTest
@testable import UserData

let base = Date(timeIntervalSince1970: 1_700_000_000)
func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
func stamp(_ seconds: Double, _ device: String = "A") -> UDStamp { UDStamp(at(seconds), device: device) }

struct LCG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
}

final class Sleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    func record(_ s: Double) { lock.withLock { values.append(s) } }
    var all: [Double] { lock.withLock { values } }
}

func makeLedger(_ device: String = "A", clock: @escaping @Sendable () -> Date = { base }) -> UserDataLedger {
    UserDataLedger(deviceID: device, clock: clock)
}

func makeEngine(_ ledger: UserDataLedger, _ cloud: any UserDataCloud, limits: UDLimits = .cloudKit, sleeps: Sleeps = Sleeps()) -> UserDataSyncEngine {
    UserDataSyncEngine(ledger: ledger, cloud: cloud, limits: limits, maxAttempts: 4, defaultBackoff: 2, sleep: { sleeps.record($0) })
}

func watched(_ key: String, position: Double = 0, watched: Bool = true, count: Int = 1, played: Double, favorite: Bool = false) -> (String, UDWatchValue) {
    (key, UDWatchValue(position: position, duration: 7200, watched: watched, playCount: count, lastPlayed: at(played), favorite: favorite, hidden: false))
}

func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("userdata-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
