import Foundation

/// Detected SMC key support for the current hardware/firmware
struct SMCCapabilities: Sendable {
    let useTahoeCharging: Bool   // CHTE supported
    let useLegacyCharging: Bool  // CH0B/CH0C supported

    let useCHIE: Bool            // Tahoe discharge key
    let useCH0J: Bool            // Alternate discharge key
    let useCH0I: Bool            // Legacy discharge key

    var canControlCharging: Bool {
        useTahoeCharging || useLegacyCharging
    }

    var canControlDischarging: Bool {
        useCHIE || useCH0J || useCH0I
    }
}
