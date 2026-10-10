import Foundation

/// Labels list salt, so the app shows salt; sodium is what's stored. Salt is
/// 40% sodium, so a gram of salt is 400 mg of sodium (the same factor the label
/// scanner uses).
nonisolated enum SaltConversion {
    static let sodiumMgPerGramSalt = 400.0

    static func saltG(fromSodiumMg mg: Double) -> Double { mg / sodiumMgPerGramSalt }
    static func sodiumMg(fromSaltG g: Double) -> Double { g * sodiumMgPerGramSalt }

    /// "0.3 g", "2.35 g" - up to two decimals, no trailing zeros.
    static func label(sodiumMg mg: Double) -> String {
        let text = String(format: "%.2f", saltG(fromSodiumMg: mg))
        return text.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + " g"
    }
}
