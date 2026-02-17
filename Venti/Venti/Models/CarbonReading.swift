import Foundation

struct CarbonReading: Sendable {
    let intensity: Int
    let region: String
    let timestamp: Date

    static let offline = CarbonReading(intensity: 0, region: Constants.defaultRegion, timestamp: .now)
}
