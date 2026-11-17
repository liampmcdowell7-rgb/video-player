import XCTest
import RemuxEngine
import PlaybackStatus
import DolbyVisionRPU
@testable import AppLogic

final class DynamicHDRPlaybackTests: XCTestCase {
    func testHDR10PlusByModel() {
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "AppleTV5,3"), .no, "HD")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "AppleTV6,2"), .no, "4K 1st generation")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "AppleTV11,1"), .no, "4K 2nd generation")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "AppleTV14,1"), .yes, "4K 3rd generation")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "AppleTV16,1"), .yes, "later models (PROVISIONAL)")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: "arm64"), .unknown, "simulator")
        XCTAssertEqual(DeviceVideoCapabilities.sendsHDR10Plus(modelIdentifier: ""), .unknown)
    }

    func testEngineOptionsAddTheConverterWhenTheLibraryIsThere() {
        var base = RemuxOptions()
        base.targetSegmentSeconds = 4
        let options = RemuxPlaybackModel.engineOptions(base)
        XCTAssertEqual(options.targetSegmentSeconds, 4, "other options pass through")
        // Without the native library (Linux without VP_LIBDOVI) there is no converter; with it (every Apple build) there is one.
        XCTAssertEqual(options.dolbyVisionConverter != nil, DolbyVisionProfile7Converter.isAvailable)
    }
}
