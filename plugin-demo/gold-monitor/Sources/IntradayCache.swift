import Foundation

private struct CachedSeries: Codable {
    let date: String
    let fetchedAt: TimeInterval
    let points: [GoldSeriesPoint]
}

private func cacheURL(dataDir: String, file: String) -> URL? {
    guard !dataDir.isEmpty else { return nil }
    return URL(fileURLWithPath: dataDir, isDirectory: true).appendingPathComponent(file)
}

private func loadCachedSeries(dataDir: String, symbol: GoldSymbol, date: String) -> CachedSeries? {
    guard let url = cacheURL(dataDir: dataDir, file: "series_\(symbol.rawValue).json"),
          let data = try? Data(contentsOf: url),
          let cached = try? JSONDecoder().decode(CachedSeries.self, from: data),
          cached.date == date else { return nil }
    return cached
}

private func saveCachedSeries(dataDir: String, symbol: GoldSymbol, cached: CachedSeries) {
    guard let url = cacheURL(dataDir: dataDir, file: "series_\(symbol.rawValue).json"),
          let data = try? JSONEncoder().encode(cached) else { return }
    try? data.write(to: url, options: .atomic)
}

private func updateTickBuffer(dataDir: String, symbol: GoldSymbol, quote: GoldQuote) -> [GoldSeriesPoint] {
    let hhmm = quote.time.count >= 5 ? String(quote.time.prefix(5)) : quote.time
    let point = GoldSeriesPoint(t: hhmm, p: quote.price)
    guard let url = cacheURL(dataDir: dataDir, file: "ticks_\(symbol.rawValue).json") else {
        return [point]
    }

    let cached = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(CachedSeries.self, from: $0) }
    var pts = (cached?.date == quote.date) ? (cached?.points ?? []) : []

    if let last = pts.last, last.t == hhmm {
        pts[pts.count - 1] = point
    } else {
        pts.append(point)
        if pts.count > 240 { pts.removeFirst(pts.count - 240) }
    }

    let next = CachedSeries(date: quote.date, fetchedAt: Date().timeIntervalSince1970, points: pts)
    if let data = try? JSONEncoder().encode(next) {
        try? data.write(to: url, options: .atomic)
    }
    return pts
}

func resolveIntradaySeries(dataDir: String, symbol: GoldSymbol, quote: GoldQuote) -> [GoldSeriesPoint] {
    let now = Date().timeIntervalSince1970
    let ticks = updateTickBuffer(dataDir: dataDir, symbol: symbol, quote: quote)
    let cached = loadCachedSeries(dataDir: dataDir, symbol: symbol, date: quote.date)

    var basePoints: [GoldSeriesPoint] = cached?.points ?? []
    let cacheAge = now - (cached?.fetchedAt ?? 0)

    if basePoints.isEmpty || cacheAge > 45 {
        if let em = fetchEastmoneyTrends(symbol: symbol) {
            basePoints = em
            saveCachedSeries(dataDir: dataDir, symbol: symbol, cached: CachedSeries(date: quote.date, fetchedAt: now, points: em))
        } else if basePoints.isEmpty, let wscn = fetchWscnKline(symbol: symbol) {
            basePoints = wscn
            saveCachedSeries(dataDir: dataDir, symbol: symbol, cached: CachedSeries(date: quote.date, fetchedAt: now, points: wscn))
        }
    }

    guard !basePoints.isEmpty else { return ticks }

    var merged = basePoints
    if let lastBaseTime = merged.last?.t {
        for tick in ticks where tick.t > lastBaseTime { merged.append(tick) }
    }
    let liveHHMM = quote.time.count >= 5 ? String(quote.time.prefix(5)) : quote.time
    if let last = merged.last, last.t == liveHHMM {
        merged[merged.count - 1] = GoldSeriesPoint(t: liveHHMM, p: quote.price)
    } else if !liveHHMM.isEmpty {
        merged.append(GoldSeriesPoint(t: liveHHMM, p: quote.price))
    }

    guard merged.count > 260 else { return merged }
    let step = Double(merged.count - 1) / 259.0
    var sampled: [GoldSeriesPoint] = []
    sampled.reserveCapacity(260)
    for i in 0..<259 { sampled.append(merged[Int(Double(i) * step)]) }
    sampled.append(merged[merged.count - 1])
    return sampled
}

func saveLastQuote(dataDir: String, quote: GoldQuote) {
    guard let url = cacheURL(dataDir: dataDir, file: "last_quote_\(quote.symbol).json"),
          let data = try? JSONEncoder().encode(quote) else { return }
    try? data.write(to: url, options: .atomic)
}

func loadLastQuote(dataDir: String, symbol: GoldSymbol) -> GoldQuote? {
    guard let url = cacheURL(dataDir: dataDir, file: "last_quote_\(symbol.rawValue).json"),
          let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(GoldQuote.self, from: data)
}

func resolveQuotes(dataDir: String) -> [GoldSymbol: GoldQuote] {
    var quotes = fetchSinaQuotes()
    for sym in [GoldSymbol.au9999, GoldSymbol.autd] {
        if let q = quotes[sym] { saveLastQuote(dataDir: dataDir, quote: q) }
        else if let cached = loadLastQuote(dataDir: dataDir, symbol: sym) { quotes[sym] = cached }
    }
    return quotes
}
