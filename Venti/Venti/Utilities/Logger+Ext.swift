import os

extension Logger {
    static let battery = Logger(subsystem: Constants.logSubsystem, category: "battery")
    static let carbon = Logger(subsystem: Constants.logSubsystem, category: "carbon")
    static let smc = Logger(subsystem: Constants.logSubsystem, category: "smc")
    static let setup = Logger(subsystem: Constants.logSubsystem, category: "setup")
    static let loop = Logger(subsystem: Constants.logSubsystem, category: "loop")
}
