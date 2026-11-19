import Foundation

private let ephemeralSession: URLSession = {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.urlCache = nil
    cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: cfg)
}()

private func httpGetData(urlString: String, headers: [String: String], timeout: TimeInterval = 4.5) -> Data? {
    guard let url = URL(string: urlString) else { return nil }
    var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    req.setValue(
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        forHTTPHeaderField: "User-Agent"
    )
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }

    let sem = DispatchSemaphore(value: 0)
    var result: Data?
    let task = ephemeralSession.dataTask(with: req) { data, resp, err in
        if err == nil, let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
            result = data
        }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + timeout + 0.5)
    return result
}

func fetchSinaQuotes() -> [GoldSymbol: GoldQuote] {
    guard let data = httpGetData(
        urlString: "https://hq.sinajs.cn/list=gds_AU9999,gds_AUTD",
        headers: ["Referer": "https://finance.sina.com.cn"]
    ) else { return [:] }

    let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    let text = String(data: data, encoding: gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
    var quotes: [GoldSymbol: GoldQuote] = [:]

    for sym in [GoldSymbol.au9999, GoldSymbol.autd] {
        let prefix = "var hq_str_\(sym.sinaCode)=\""
        guard let startRange = text.range(of: prefix),
              let endQuote = text[startRange.upperBound...].firstIndex(of: "\"") else { continue }
        let body = String(text[startRange.upperBound..<endQuote])
        let cols = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard cols.count >= 13, let price = Double(cols[0]), price > 0 else { continue }

        let bid = Double(cols[2]) ?? price
        let ask = Double(cols[3]) ?? price
        let high = Double(cols[4]) ?? price
        let low = Double(cols[5]) ?? price
        let timeStr = cols[6]
        let preClose = Double(cols[7]) ?? price
        let open = Double(cols[8]) ?? price
        let dateStr = cols[12]

        let change = price - preClose
        let changePct = preClose > 0 ? (change / preClose) * 100.0 : 0.0

        quotes[sym] = GoldQuote(
            symbol: sym.rawValue, name: sym.displayName, unit: "元/克",
            price: price, preClose: preClose, open: open, high: high, low: low,
            bid: bid, ask: ask, change: change, changePct: changePct,
            time: timeStr, date: dateStr, source: "新浪财经 · 实时"
        )
    }
    return quotes
}

func fetchEastmoneyTrends(symbol: GoldSymbol) -> [GoldSeriesPoint]? {
    let url = "https://push2.eastmoney.com/api/qt/stock/trends2/get?secid=\(symbol.eastmoneySecID)&fields1=f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13&fields2=f51,f52,f53,f54,f55,f56,f57,f58&iscr=0&ndays=1"
    guard let data = httpGetData(
        urlString: url,
        headers: ["Referer": "https://quote.eastmoney.com/", "Connection": "close"],
        timeout: 3.0
    ) else { return nil }

    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataDict = obj["data"] as? [String: Any],
          let trends = dataDict["trends"] as? [String],
          !trends.isEmpty else { return nil }

    var points: [GoldSeriesPoint] = []
    points.reserveCapacity(trends.count)
    for row in trends {
        let parts = row.split(separator: ",")
        guard parts.count >= 3, let closePx = Double(parts[2]), closePx > 0 else { continue }
        let dtParts = parts[0].split(separator: " ")
        let hhmm = dtParts.count >= 2 ? String(dtParts[1]) : String(parts[0])
        points.append(GoldSeriesPoint(t: hhmm, p: closePx))
    }
    return points.isEmpty ? nil : points
}

func fetchWscnKline(symbol: GoldSymbol) -> [GoldSeriesPoint]? {
    let url = "https://api-ddc-wscn.awtmt.com/market/kline?prod_code=\(symbol.wscnCode)&tick_count=320&period_type=60&fields=tick_at,close_px"
    guard let data = httpGetData(urlString: url, headers: [:], timeout: 3.5) else { return nil }

    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let dataDict = obj["data"] as? [String: Any],
          let candle = dataDict["candle"] as? [String: Any],
          let symDict = candle[symbol.wscnCode] as? [String: Any],
          let lines = symDict["lines"] as? [[Any]] else { return nil }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")

    var points: [GoldSeriesPoint] = []
    points.reserveCapacity(lines.count)
    for item in lines {
        guard item.count >= 2,
              let px = (item[0] as? NSNumber)?.doubleValue,
              let ts = (item[1] as? NSNumber)?.doubleValue,
              px > 0 else { continue }
        points.append(GoldSeriesPoint(t: formatter.string(from: Date(timeIntervalSince1970: ts)), p: px))
    }
    return points.isEmpty ? nil : points
}
