import Foundation

struct GoldSeriesPoint: Codable {
    let t: String
    let p: Double
}

struct GoldQuote: Codable {
    let symbol: String
    let name: String
    let unit: String
    let price: Double
    let preClose: Double
    let open: Double
    let high: Double
    let low: Double
    let bid: Double
    let ask: Double
    let change: Double
    let changePct: Double
    let time: String
    let date: String
    let source: String
}

struct DockLaunchState: Codable {
    var edge: String
    var anchorX: Double?
    var anchorY: Double?
    var fromMode: String
    var pendingSnap: Bool
}

struct GoldSnapshotPayload: Codable {
    let ok: Bool
    let symbol: String
    let name: String
    let unit: String
    let price: Double
    let preClose: Double
    let open: Double
    let high: Double
    let low: Double
    let bid: Double
    let ask: Double
    let change: Double
    let changePct: Double
    let time: String
    let date: String
    let source: String
    let colorScheme: String
    let themeStyle: String
    let defaultMode: String
    let refreshIntervalSec: Int
    let series: [GoldSeriesPoint]
    let alerts: SymbolAlertSummary?
    let alertTriggered: AlertTriggeredInfo?
    let dockState: DockLaunchState?
    let error: String?
}

enum GoldSymbol: String {
    case au9999 = "AU9999"
    case autd = "AUTD"

    init(raw: String) {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self = (normalized == "AUTD" || normalized == "AU(T+D)" || normalized == "TD") ? .autd : .au9999
    }

    var sinaCode: String {
        switch self {
        case .au9999: return "gds_AU9999"
        case .autd: return "gds_AUTD"
        }
    }

    var eastmoneySecID: String {
        switch self {
        case .au9999: return "118.AU9999"
        case .autd: return "118.AUTD"
        }
    }

    var wscnCode: String {
        switch self {
        case .au9999: return "AU9999.SGE"
        case .autd: return "AUTD.SGE"
        }
    }

    var displayName: String {
        switch self {
        case .au9999: return "上海金 Au99.99"
        case .autd: return "黄金延期 Au(T+D)"
        }
    }

    var englishName: String {
        switch self {
        case .au9999: return "Shanghai Gold Au99.99"
        case .autd: return "Gold T+D (Au(T+D))"
        }
    }
}

enum WindowStyle: String {
    case standard
    case mini
    case dock
}

func emitEncodableJSON<T: Encodable>(_ value: T) {
    let enc = JSONEncoder()
    enc.outputFormatting = [.withoutEscapingSlashes]
    if let data = try? enc.encode(value), let str = String(data: data, encoding: .utf8) {
        print(str)
    }
}
