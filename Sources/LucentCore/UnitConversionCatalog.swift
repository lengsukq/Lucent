import LucentFoundation
import Foundation

enum UnitConversionCatalog {
    static func evaluate(_ raw: String) -> UnitConversionResult? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard let split = splitConversionClause(trimmed) else { return nil }
        if let base = evaluateBaseConversion(lhs: split.lhs, target: split.rhs, expr: raw) {
            return base
        }
        return evaluateDimensionalConversion(lhs: split.lhs, target: split.rhs, expr: raw)
    }

    private static func splitConversionClause(_ s: String) -> (lhs: String, rhs: String)? {
        let patterns = [" to ", " in ", " as ", " -> ", " => ", " 转 ", " 换算 ", " 等于 ", "转"]
        let lower = s.lowercased()
        for sep in patterns {
            if let range = lower.range(of: sep) {
                let left = String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(s[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty && !right.isEmpty { return (left, right) }
            }
        }
        return nil
    }

    private static func evaluateBaseConversion(lhs: String, target: String, expr: String) -> UnitConversionResult? {
        let lowLHS = lhs.lowercased()
        let number: Int64?
        if lowLHS.hasPrefix("0x") { number = Int64(lowLHS.dropFirst(2), radix: 16) }
        else if lowLHS.hasPrefix("0b") { number = Int64(lowLHS.dropFirst(2), radix: 2) }
        else if lowLHS.hasPrefix("0o") { number = Int64(lowLHS.dropFirst(2), radix: 8) }
        else { number = Int64(lowLHS) }
        guard let number else { return nil }

        let badge = L10n.pick("进制", "Base")
        switch target.lowercased() {
        case "hex", "16", "十六进制", "16进制":
            return UnitConversionResult(expression: expr, resultText: "0x" + String(number, radix: 16, uppercase: true), badgeLabel: badge)
        case "bin", "2", "二进制", "2进制":
            return UnitConversionResult(expression: expr, resultText: "0b" + String(number, radix: 2), badgeLabel: badge)
        case "oct", "8", "八进制", "8进制":
            return UnitConversionResult(expression: expr, resultText: "0o" + String(number, radix: 8), badgeLabel: badge)
        case "dec", "10", "十进制", "10进制":
            return UnitConversionResult(expression: expr, resultText: String(number), badgeLabel: badge)
        default:
            return nil
        }
    }

    private static func parseValueAndUnit(_ lhs: String) -> (Double, String)? {
        let chars = Array(lhs)
        var i = 0
        if i < chars.count && (chars[i] == "+" || chars[i] == "-") { i += 1 }
        var seenDigit = false, seenDot = false
        while i < chars.count {
            if chars[i].isNumber { seenDigit = true; i += 1 }
            else if chars[i] == "." && !seenDot { seenDot = true; i += 1 }
            else { break }
        }
        guard seenDigit, let val = Double(String(chars[..<i])) else { return nil }
        let unit = String(chars[i...]).trimmingCharacters(in: .whitespaces).lowercased()
        return unit.isEmpty ? nil : (val, unit)
    }

    private static func evaluateDimensionalConversion(lhs: String, target: String, expr: String) -> UnitConversionResult? {
        guard let (value, u1) = parseValueAndUnit(lhs) else { return nil }
        let u2 = target.trimmingCharacters(in: .whitespaces).lowercased()

        if let t1 = tempKind(u1), let t2 = tempKind(u2) {
            let celsius: Double = switch t1.kind {
            case "c": value
            case "f": (value - 32.0) * 5.0 / 9.0
            default: value - 273.15
            }
            let out: Double = switch t2.kind {
            case "c": celsius
            case "f": celsius * 9.0 / 5.0 + 32.0
            default: celsius + 273.15
            }
            return formatResult(out, label: t2.label, expr: expr)
        }

        for table in [lengthFactors, massFactors, dataFactors, timeFactors, areaFactors, volumeFactors, cssFactors, angleFactors, speedFactors] {
            if let f1 = table[u1], let f2 = table[u2] {
                let out = value * f1.factor / f2.factor
                return formatResult(out, label: f2.label, expr: expr)
            }
        }
        return nil
    }

    private static func formatResult(_ val: Double, label: String, expr: String) -> UnitConversionResult {
        let formatted: String
        if abs(val - val.rounded()) < 1e-9 && abs(val) < 1e12 {
            formatted = String(Int64(val.rounded()))
        } else {
            formatted = String(format: "%.4g", val)
        }
        return UnitConversionResult(expression: expr, resultText: "\(formatted) \(label)", badgeLabel: L10n.pick("换算", "Unit"))
    }

    private static func tempKind(_ u: String) -> (kind: String, label: String)? {
        switch u {
        case "c", "°c", "celsius", "摄氏度", "度": ("c", "°C")
        case "f", "°f", "fahrenheit", "华氏度": ("f", "°F")
        case "k", "kelvin", "开尔文": ("k", "K")
        default: nil
        }
    }

    private struct UnitSpec { let factor: Double; let label: String }

    private static let lengthFactors: [String: UnitSpec] = [
        "km": .init(factor: 1000, label: "km"), "公里": .init(factor: 1000, label: "km"), "千米": .init(factor: 1000, label: "km"),
        "m": .init(factor: 1, label: "m"), "米": .init(factor: 1, label: "m"),
        "cm": .init(factor: 0.01, label: "cm"), "厘米": .init(factor: 0.01, label: "cm"),
        "mm": .init(factor: 0.001, label: "mm"), "毫米": .init(factor: 0.001, label: "mm"),
        "mi": .init(factor: 1609.344, label: "mi"), "mile": .init(factor: 1609.344, label: "mi"), "miles": .init(factor: 1609.344, label: "mi"), "英里": .init(factor: 1609.344, label: "mi"),
        "yd": .init(factor: 0.9144, label: "yd"), "码": .init(factor: 0.9144, label: "yd"),
        "ft": .init(factor: 0.3048, label: "ft"), "feet": .init(factor: 0.3048, label: "ft"), "英尺": .init(factor: 0.3048, label: "ft"),
        "in": .init(factor: 0.0254, label: "in"), "inch": .init(factor: 0.0254, label: "in"), "英寸": .init(factor: 0.0254, label: "in")
    ]

    private static let massFactors: [String: UnitSpec] = [
        "t": .init(factor: 1_000_000, label: "t"), "吨": .init(factor: 1_000_000, label: "t"),
        "kg": .init(factor: 1000, label: "kg"), "千克": .init(factor: 1000, label: "kg"), "公斤": .init(factor: 1000, label: "kg"),
        "jin": .init(factor: 500, label: "斤"), "斤": .init(factor: 500, label: "斤"),
        "liang": .init(factor: 50, label: "两"), "两": .init(factor: 50, label: "两"),
        "g": .init(factor: 1, label: "g"), "克": .init(factor: 1, label: "g"),
        "mg": .init(factor: 0.001, label: "mg"), "毫克": .init(factor: 0.001, label: "mg"),
        "lb": .init(factor: 453.59237, label: "lb"), "lbs": .init(factor: 453.59237, label: "lb"), "磅": .init(factor: 453.59237, label: "lb"),
        "oz": .init(factor: 28.349523125, label: "oz"), "盎司": .init(factor: 28.349523125, label: "oz")
    ]

    private static let dataFactors: [String: UnitSpec] = [
        "pb": .init(factor: 1_125_899_906_842_624, label: "PB"),
        "tb": .init(factor: 1_099_511_627_776, label: "TB"),
        "gb": .init(factor: 1_073_741_824, label: "GB"),
        "mb": .init(factor: 1_048_576, label: "MB"),
        "kb": .init(factor: 1024, label: "KB"),
        "b": .init(factor: 1, label: "B"), "byte": .init(factor: 1, label: "B"), "bytes": .init(factor: 1, label: "B")
    ]

    private static let timeFactors: [String: UnitSpec] = [
        "ms": .init(factor: 0.001, label: "ms"), "毫秒": .init(factor: 0.001, label: "ms"),
        "s": .init(factor: 1, label: "s"), "sec": .init(factor: 1, label: "s"), "秒": .init(factor: 1, label: "s"),
        "min": .init(factor: 60, label: "min"), "mins": .init(factor: 60, label: "min"), "分钟": .init(factor: 60, label: "min"),
        "h": .init(factor: 3600, label: "h"), "hr": .init(factor: 3600, label: "h"), "hour": .init(factor: 3600, label: "h"), "小时": .init(factor: 3600, label: "h"),
        "d": .init(factor: 86400, label: "d"), "day": .init(factor: 86400, label: "d"), "days": .init(factor: 86400, label: "d"), "天": .init(factor: 86400, label: "d"),
        "wk": .init(factor: 604800, label: "wk"), "week": .init(factor: 604800, label: "wk"), "周": .init(factor: 604800, label: "wk")
    ]

    private static let areaFactors: [String: UnitSpec] = [
        "sqm": .init(factor: 1, label: "m²"), "m2": .init(factor: 1, label: "m²"), "平方米": .init(factor: 1, label: "m²"), "平米": .init(factor: 1, label: "m²"),
        "sqft": .init(factor: 0.09290304, label: "ft²"), "ft2": .init(factor: 0.09290304, label: "ft²"), "平方英尺": .init(factor: 0.09290304, label: "ft²"),
        "ha": .init(factor: 10000, label: "ha"), "公顷": .init(factor: 10000, label: "ha"),
        "acre": .init(factor: 4046.8564224, label: "acre"), "acres": .init(factor: 4046.8564224, label: "acre"), "英亩": .init(factor: 4046.8564224, label: "acre")
    ]

    private static let volumeFactors: [String: UnitSpec] = [
        "l": .init(factor: 1000, label: "L"), "liter": .init(factor: 1000, label: "L"), "升": .init(factor: 1000, label: "L"),
        "ml": .init(factor: 1, label: "mL"), "毫升": .init(factor: 1, label: "mL"),
        "cup": .init(factor: 236.5882365, label: "cup"), "杯": .init(factor: 236.5882365, label: "cup"),
        "floz": .init(factor: 29.5735295625, label: "fl oz"), "液量盎司": .init(factor: 29.5735295625, label: "fl oz"),
        "gal": .init(factor: 3785.411784, label: "gal"), "加仑": .init(factor: 3785.411784, label: "gal")
    ]

    private static let cssFactors: [String: UnitSpec] = [
        "px": .init(factor: 1, label: "px"),
        "rem": .init(factor: 16, label: "rem"),
        "em": .init(factor: 16, label: "em"),
        "pt": .init(factor: 4.0 / 3.0, label: "pt")
    ]

    private static let angleFactors: [String: UnitSpec] = [
        "rad": .init(factor: 1, label: "rad"), "弧度": .init(factor: 1, label: "rad"),
        "deg": .init(factor: .pi / 180.0, label: "deg"), "degree": .init(factor: .pi / 180.0, label: "deg"),
        "degrees": .init(factor: .pi / 180.0, label: "deg"), "度": .init(factor: .pi / 180.0, label: "deg"),
        "角度": .init(factor: .pi / 180.0, label: "deg"),
        "turn": .init(factor: 2.0 * .pi, label: "turn"), "turns": .init(factor: 2.0 * .pi, label: "turn"),
        "圈": .init(factor: 2.0 * .pi, label: "turn")
    ]

    private static let speedFactors: [String: UnitSpec] = [
        "m/s": .init(factor: 1, label: "m/s"), "mps": .init(factor: 1, label: "m/s"), "米每秒": .init(factor: 1, label: "m/s"),
        "km/h": .init(factor: 1.0 / 3.6, label: "km/h"), "kmh": .init(factor: 1.0 / 3.6, label: "km/h"),
        "kph": .init(factor: 1.0 / 3.6, label: "km/h"), "公里每小时": .init(factor: 1.0 / 3.6, label: "km/h"),
        "mph": .init(factor: 0.44704, label: "mph"), "英里每小时": .init(factor: 0.44704, label: "mph"),
        "kn": .init(factor: 1852.0 / 3600.0, label: "kn"), "knot": .init(factor: 1852.0 / 3600.0, label: "kn"),
        "knots": .init(factor: 1852.0 / 3600.0, label: "kn"), "节": .init(factor: 1852.0 / 3600.0, label: "kn")
    ]
}
