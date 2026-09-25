import Foundation

enum TemperatureStatus: Equatable {
    case unavailable
    case normal
    case warning
    case critical

    static func disk(_ celsius: Double?) -> Self {
        guard let celsius, celsius.isFinite else { return .unavailable }
        let displayed = Int(celsius.rounded())
        if displayed >= 71 { return .critical }
        if displayed >= 51 { return .warning }
        return .normal
    }

    static func battery(_ celsius: Double?) -> Self {
        guard let celsius, celsius.isFinite else { return .unavailable }
        let displayed = Int(celsius.rounded())
        return displayed < 10 || displayed >= 35 ? .warning : .normal
    }

    static func label(_ celsius: Double?) -> String? {
        guard let celsius, celsius.isFinite else { return nil }
        return "\(Int(celsius.rounded()))°C"
    }
}
