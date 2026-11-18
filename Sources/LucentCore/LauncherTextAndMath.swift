import Foundation
import LucentFoundation

public enum SafeMathEvaluator {
    public static func evaluate(_ raw: String) -> String? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "π", with: "pi")
        guard normalized.count >= 2 else { return nil }

        if let pctOf = evaluatePercentOf(normalized) {
            return formatDouble(pctOf)
        }
        normalized = normalized.replacingOccurrences(
            of: #"(?i)\bof\b"#, with: "*", options: .regularExpression
        )

        let lower = normalized.lowercased()
        let fnNames = ["sqrt(", "sin(", "cos(", "tan(", "abs(", "ln(", "log(", "round(", "ceil(", "floor("]
        let hasMathSignal = normalized.contains(where: { "+-*/%^()".contains($0) })
            || lower.hasPrefix("0x") || lower.hasPrefix("0b")
            || fnNames.contains(where: { lower.contains($0) })
        guard hasMathSignal else { return nil }

        var parser = Parser(chars: Array(normalized))
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return formatDouble(value)
    }

    private static func evaluatePercentOf(_ s: String) -> Double? {
        let lower = s.lowercased()
        let parts = lower.components(separatedBy: "% of ")
        guard parts.count == 2 else { return nil }
        var p1 = Parser(chars: Array(parts[0]))
        var p2 = Parser(chars: Array(parts[1]))
        guard let pct = p1.parseExpression(), p1.isAtEnd,
              let base = p2.parseExpression(), p2.isAtEnd else { return nil }
        return (pct / 100.0) * base
    }

    private static func formatDouble(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-10 && abs(value) <= Double(Int64.max / 2) {
            return String(Int64(value.rounded()))
        }
        return String(format: "%.6g", value)
    }

    private struct Parser {
        let chars: [Character]
        var index: Int = 0
        var isAtEnd: Bool { mutating get { skipSpaces(); return index >= chars.count } }

        mutating func parseExpression() -> Double? {
            guard var lhs = parseTerm() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count, chars[index] == "+" || chars[index] == "-" else { break }
                let op = chars[index]; index += 1
                let saved = index
                guard let rhs = parseTerm() else { return nil }
                skipSpaces()
                let rhsWasBarePercent = checkTrailingPercentOnly(from: saved, to: index)
                let adjustedRHS = rhsWasBarePercent ? (lhs * rhs) : rhs
                lhs = (op == "+") ? (lhs + adjustedRHS) : (lhs - adjustedRHS)
            }
            return lhs
        }

        private func checkTrailingPercentOnly(from start: Int, to end: Int) -> Bool {
            let slice = String(chars[start..<end]).trimmingCharacters(in: .whitespaces)
            guard slice.hasSuffix("%"), !slice.dropLast().contains(where: { "+-*/%^".contains($0) }) else { return false }
            return Double(slice.dropLast().trimmingCharacters(in: .whitespaces)) != nil
        }

        mutating func parseTerm() -> Double? {
            guard var lhs = parsePower() else { return nil }
            while true {
                skipSpaces()
                guard index < chars.count, "*/%".contains(chars[index]) else { break }
                let op = chars[index]
                if op == "%" {
                    let nextIdx = index + 1
                    var peek = nextIdx
                    while peek < chars.count && chars[peek].isWhitespace { peek += 1 }
                    if peek >= chars.count || "+-*/^)".contains(chars[peek]) {
                        index = nextIdx
                        lhs /= 100.0
                        continue
                    }
                }
                index += 1
                guard let rhs = parsePower() else { return nil }
                if (op == "/" || op == "%") && rhs == 0 { return nil }
                lhs = op == "*" ? lhs * rhs : (op == "/" ? lhs / rhs : lhs.truncatingRemainder(dividingBy: rhs))
            }
            return lhs
        }

        mutating func parsePower() -> Double? {
            guard var base = parsePostfixPercent() else { return nil }
            skipSpaces()
            if index < chars.count && chars[index] == "^" {
                index += 1
                guard let exp = parsePower() else { return nil }
                base = pow(base, exp)
            }
            return base
        }

        mutating func parsePostfixPercent() -> Double? {
            guard var val = parseFactor() else { return nil }
            skipSpaces()
            if index < chars.count && chars[index] == "%" {
                let nextIdx = index + 1
                var peek = nextIdx
                while peek < chars.count && chars[peek].isWhitespace { peek += 1 }
                if peek >= chars.count || "+-*/^)".contains(chars[peek]) {
                    index = nextIdx
                    val /= 100.0
                }
            }
            return val
        }

        mutating func parseFactor() -> Double? {
            skipSpaces()
            guard index < chars.count else { return nil }
            if chars[index] == "+" { index += 1; return parseFactor() }
            if chars[index] == "-" { index += 1; return parseFactor().map { -$0 } }
            if chars[index] == "(" {
                index += 1
                guard let inner = parseExpression() else { return nil }
                skipSpaces()
                guard index < chars.count && chars[index] == ")" else { return nil }
                index += 1
                return inner
            }
            if chars[index].isLetter {
                return parseIdentifierOrFunction()
            }
            return parseNumber()
        }

        mutating func parseIdentifierOrFunction() -> Double? {
            let start = index
            while index < chars.count && (chars[index].isLetter || chars[index].isNumber) { index += 1 }
            let ident = String(chars[start..<index]).lowercased()
            if ident == "pi" { return .pi }
            if ident == "e" { return M_E }
            skipSpaces()
            guard index < chars.count && chars[index] == "(" else { return nil }
            index += 1
            guard let arg = parseExpression() else { return nil }
            skipSpaces()
            guard index < chars.count && chars[index] == ")" else { return nil }
            index += 1
            switch ident {
            case "sqrt": return arg >= 0 ? sqrt(arg) : nil
            case "sin": return sin(arg)
            case "cos": return cos(arg)
            case "tan": return tan(arg)
            case "abs": return abs(arg)
            case "ln": return arg > 0 ? log(arg) : nil
            case "log", "log10": return arg > 0 ? log10(arg) : nil
            case "round": return arg.rounded()
            case "ceil": return ceil(arg)
            case "floor": return floor(arg)
            default: return nil
            }
        }

        mutating func parseNumber() -> Double? {
            skipSpaces()
            let start = index
            if index + 1 < chars.count && chars[index] == "0" {
                let tag = chars[index + 1]
                if tag == "x" || tag == "X" {
                    index += 2; let hStart = index
                    while index < chars.count && chars[index].isHexDigit { index += 1 }
                    guard index > hStart, let v = UInt64(String(chars[hStart..<index]), radix: 16) else { return nil }
                    return Double(v)
                }
                if tag == "b" || tag == "B" {
                    index += 2; let bStart = index
                    while index < chars.count && (chars[index] == "0" || chars[index] == "1") { index += 1 }
                    guard index > bStart, let v = UInt64(String(chars[bStart..<index]), radix: 2) else { return nil }
                    return Double(v)
                }
            }
            var seenDot = false
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { index += 1 }
                else if c == "." && !seenDot { seenDot = true; index += 1 }
                else { break }
            }
            guard index > start else { return nil }
            return Double(String(chars[start..<index]))
        }

        mutating func skipSpaces() {
            while index < chars.count && chars[index].isWhitespace { index += 1 }
        }
    }
}
