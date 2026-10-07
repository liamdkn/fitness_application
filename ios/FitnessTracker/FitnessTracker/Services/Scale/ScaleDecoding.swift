import Foundation

/// Reads grams out of a scale's Bluetooth data.
nonisolated enum ScaleDecoding {
    /// Standard Bluetooth "Weight Scale" measurement (characteristic 0x2A9D):
    /// a flags byte, then a 16-bit weight. Flag bit 0 says pounds; otherwise
    /// kilograms in 0.005 steps (pounds in 0.01 steps).
    static func standardWeightScale(_ data: Data) -> Double? {
        guard data.count >= 3 else { return nil }
        let flags = data[data.startIndex]
        let raw = Double(UInt16(data[data.startIndex + 1]) | UInt16(data[data.startIndex + 2]) << 8)
        let isImperial = flags & 0x01 != 0
        let kg = isImperial ? raw * 0.01 * 0.45359237 : raw * 0.005
        return (kg * 1000 * 10).rounded() / 10
    }

    // MARK: ICOMON / Fitdays+ kitchen scales

    /// Kitchen scales of this family (device type 0x42, e.g. KG2458ULB-D,
    /// advertised as MY_SCALE) frame everything as
    /// `AC 42 [payload...] [command] [checksum]`, the checksum being the sum of
    /// every byte after the 42, command included, modulo 256.
    struct IcomonFrame {
        /// The notification type (0xA0 capabilities, 0xA6 live weight, ...).
        let type: UInt8
        let payload: [UInt8]
        let checksumOK: Bool
    }

    static func icomonFrame(_ data: Data) -> IcomonFrame? {
        let bytes = [UInt8](data)
        guard bytes.count >= 4, bytes[0] == 0xAC, bytes[1] == 0x42 else { return nil }
        let body = bytes[2..<(bytes.count - 1)]
        let checksum = UInt8(truncatingIfNeeded: body.reduce(0) { $0 + Int($1) })
        return IcomonFrame(type: bytes[bytes.count - 2], payload: Array(bytes[2..<(bytes.count - 2)]),
                           checksumOK: checksum == bytes[bytes.count - 1])
    }

    /// A command frame for the scale.
    static func icomonCommand(payload: [UInt8], command: UInt8) -> Data {
        let body = payload + [command]
        let checksum = UInt8(truncatingIfNeeded: body.reduce(0) { $0 + Int($1) })
        return Data([0xAC, 0x42] + body + [checksum])
    }

    /// The reply to the scale's capabilities message: sent once after connecting.
    /// It is `AC 42 00 02 00 A0 00 D1 73`.
    static let icomonHandshake = icomonCommand(payload: [0x00, 0x02, 0x00, 0xA0, 0x00], command: 0xD1)

    /// Tells the scale who is weighing (user 1). Weight only starts streaming
    /// after this - found by trying it against a real KN2432LB: the scale
    /// acknowledges it and then sends a weight message about every 0.13 s.
    /// It is `AC 42 00 04 00 00 00 00 01 DB E0`.
    static let icomonUserInfo = icomonCommand(payload: [0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x01], command: 0xDB)

    /// Zeroes the scale, as pressing TARE does: the library's tare setting
    /// (command 0xD2, type 0). It is `AC 42 00 02 00 00 00 D2 D4`.
    static var icomonTare: Data { icomonCommand(payload: [0x00, 0x02, 0x00, 0x00, 0x00], command: 0xD2) }

    /// Sets the scale's display unit (the library's unit setting: command 0xD2,
    /// type 2). For milk ml (code 5) it is `AC 42 00 02 00 02 05 D2 DB`.
    static func icomonUnit(_ code: Int) -> Data {
        icomonCommand(payload: [0x00, 0x02, 0x00, 0x02, UInt8(truncatingIfNeeded: code)], command: 0xD2)
    }

    /// The scale unit that suits a food: grams for a food in g, milk ml for milk,
    /// plain ml for any other liquid counted in ml. `nil` for foods not counted by weight or volume.
    static func preferredScaleUnit(foodName: String, foodUnit: String) -> Int? {
        switch foodUnit.lowercased() {
        case "g": 0
        case "ml": foodName.localizedCaseInsensitiveContains("milk") ? 5 : 1
        default: nil
        }
    }

    struct IcomonWeight: Equatable {
        /// Grams, negative when the scale shows a minus (the bowl lifted off after a tare).
        /// The scale reports milligrams.
        let grams: Double
        /// The unit the scale is set to (0 grams, 1 millilitres, 2 pounds, 3 ounces, ...).
        let unit: UInt8
        /// Grams or millilitres (1 ml of water is 1 g): the units the app can use.
        var isMetric: Bool { unit == 0 || unit == 1 }
        /// The reading has settled (the scale's own flag): false while it is still changing.
        let settled: Bool
        let isNegative: Bool
        /// The scale's own food selected with its arrow buttons (0 when none). A message
        /// that changes this is the scale announcing a pick, not a weight on the plate.
        let foodId: UInt32
    }

    /// Reads a live-weight (0xA6) notification: after a 3-byte length/sequence
    /// header come a flags byte (0x80 minus sign, 0x01 settled), the unit in the
    /// high nibble of the next, then the weight in milligrams as 24 bits.
    /// Checked against a KN2432LB: lifting a bowl off after a tare gave a steady
    /// reading with 0x80 set and the weight's size; 0x40 never appeared, even for TARE.
    static func icomonWeight(_ frame: IcomonFrame) -> IcomonWeight? {
        guard frame.type == 0xA6 else { return nil }
        let body = frame.payload
        let data = body.count >= 8 ? Array(body.dropFirst(3)) : body
        guard data.count >= 5 else { return nil }
        let flags = data[0]
        let milligrams = Int(data[2]) << 16 | Int(data[3]) << 8 | Int(data[4])
        let negative = flags & 0x80 != 0
        let magnitude = (Double(milligrams) / 1000 * 10).rounded() / 10
        let foodId = data.count >= 9 ? data[5..<9].reduce(UInt32(0)) { $0 << 8 | UInt32($1) } : 0
        return IcomonWeight(
            grams: negative ? -magnitude : magnitude,
            unit: data[1] >> 4,
            settled: flags & 0x01 != 0,
            isNegative: negative,
            foodId: foodId
        )
    }

    /// Spots a press of TARE on the scale. The scale doesn't flag it; it just drops
    /// from a settled weight straight to zero. (Lifting a bowl off a tared scale goes
    /// negative instead, and putting one back climbs up gradually, so neither looks like this.)
    struct TareDetector {
        private var previous: (grams: Double, settled: Bool)?

        /// Feed each reading; returns the weight the scale held just before it zeroed, when it just did.
        mutating func feed(grams: Double, settled: Bool) -> Double? {
            defer { previous = (grams, settled) }
            guard let previous, previous.settled, previous.grams >= 2, abs(grams) < 0.5 else { return nil }
            return previous.grams
        }

        mutating func reset() { previous = nil }
    }

    /// The scale's display units, as the UNIT button cycles them. The weight on
    /// the wire is always mass (milligrams) whatever is displayed; the unit only
    /// says how the scale itself shows it.
    static func unitName(_ code: Int) -> String {
        switch code {
        case 0: "g"
        case 1: "ml"
        case 2: "lb:oz"
        case 3: "oz"
        case 4: "mg"
        case 5: "ml (milk)"
        case 6: "fl oz"
        case 7: "fl oz (milk)"
        default: "unit \(code)"
        }
    }

    /// Grams in one millilitre for the scale's current unit: milk modes use milk's
    /// density, everything else water's.
    static func gramsPerMillilitre(scaleUnit code: Int?) -> Double {
        code == 5 || code == 7 ? 1.03 : 1.0
    }

    /// What to record for `grams` of mass on the scale, in the unit the food is
    /// counted in: grams for a food in g, millilitres for one in ml (using the
    /// scale's milk setting when it is on, so "ml milk" reads the same here as
    /// on the scale). `nil` when the food isn't counted by weight or volume.
    static func amount(forGrams grams: Double, foodUnit: String, scaleUnit: Int?) -> Double? {
        switch foodUnit.lowercased() {
        case "g": grams
        case "ml": grams / gramsPerMillilitre(scaleUnit: scaleUnit)
        default: nil
        }
    }

    /// Hex dump for the setup screen: "0A 1F 00".
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
