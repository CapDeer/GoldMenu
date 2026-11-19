import Foundation

// MARK: - 数据模型

struct SpotGold {
    var name: String = ""
    var price: Double = 0          // 现价
    var open: Double = 0           // 今开
    var high: Double = 0           // 最高
    var low: Double = 0            // 最低
    var prevClose: Double = 0      // 昨收
    var time: String = ""          // 报价时间
    var date: String = ""          // 报价日期

    var change: Double { price - prevClose }
    var changePercent: Double { prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0 }
    var isUp: Bool { change >= 0 }
}

struct PriceItem: Identifiable {
    let id: String
    let name: String
    let price: String
    let note: String

    init(name: String, price: String, note: String = "") {
        self.id = name
        self.name = name
        self.price = price
        self.note = note
    }
}

struct PriceGroup: Identifiable {
    let id: String
    let title: String
    let items: [PriceItem]

    init(title: String, items: [PriceItem]) {
        self.id = title
        self.title = title
        self.items = items
    }
}

// 日内分时走势（上金所 Au99.99）
struct IntradayData {
    var times: [String] = []
    var prices: [Double] = []
    var prevClose: Double = 0      // 昨收（基准线）
    var high: Double = 0
    var low: Double = 0
    var updateTime: String = ""
    var isValid: Bool { !prices.isEmpty }
}

// 单周期涨跌幅（今日/近一周/近一月/近一年）
struct PeriodChange: Identifiable {
    let id: String          // 周期标识: today/week/month/year
    let label: String       // 显示名: 今日/近一周/近一月/近一年
    let percent: Double     // 涨跌幅 %
    let currentPrice: Double
    let basePrice: Double
    let baseDate: String    // 基准价日期
    var isUp: Bool { percent >= 0 }
}

struct GoldSnapshot {
    var spot: SpotGold?
    var priceGroups: [PriceGroup] = []
    var periodChanges: [PeriodChange] = []
    var intraday: IntradayData?
    var fetchTime: Date = Date()
}

// MARK: - 数据抓取服务

final class GoldService {
    static let shared = GoldService()
    private init() {}

    private let sinaURL = "https://hq.sinajs.cn/list=gds_AU9999"
    private let xxapiURL = "https://v2.xxapi.cn/api/goldprice"
    private let xauHistoryURL = "https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var%20t=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol=XAU"
    private let sgeIntradayURL = "https://www.sge.com.cn/graph/quotations"

    // 历史日K约 692KB，按天缓存，避免每秒刷新重复拉取
    private var cachedPeriods: [PeriodChange]?
    private var cachedDay: String = ""
    // 分时数据约 12KB，短缓存 3 秒，避免每秒重拉
    private var cachedIntraday: IntradayData?
    private var intradayCacheTime: Date = Date.distantPast

    func fetchAll(completion: @escaping (GoldSnapshot) -> Void) {
        let group = DispatchGroup()
        var snapshot = GoldSnapshot()

        group.enter()
        fetchSpot { spot in
            DispatchQueue.main.async { snapshot.spot = spot }
            group.leave()
        }

        group.enter()
        fetchAllPrices { groups in
            DispatchQueue.main.async { snapshot.priceGroups = groups ?? [] }
            group.leave()
        }

        group.enter()
        fetchPeriodChanges { periods in
            DispatchQueue.main.async { snapshot.periodChanges = periods ?? [] }
            group.leave()
        }

        group.enter()
        fetchIntraday { intraday in
            DispatchQueue.main.async { snapshot.intraday = intraday }
            group.leave()
        }

        group.notify(queue: .main) {
            // "今日"用实时现货覆盖，保证秒级更新；其余周期用历史基准
            if let spot = snapshot.spot, !snapshot.periodChanges.isEmpty {
                snapshot.periodChanges[0] = PeriodChange(
                    id: "today", label: "今日",
                    percent: spot.changePercent,
                    currentPrice: spot.price, basePrice: spot.prevClose, baseDate: "昨收"
                )
            }
            snapshot.fetchTime = Date()
            completion(snapshot)
        }
    }

    // 新浪 XAU 伦敦金历史日K（jsonp），计算近一周/一月/一年涨跌幅
    func fetchPeriodChanges(completion: @escaping ([PeriodChange]?) -> Void) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        if let cached = cachedPeriods, cachedDay == today {
            completion(cached)
            return
        }

        guard let url = URL(string: xauHistoryURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let raw = String(data: data, encoding: .utf8),
                  let s = raw.range(of: "var t=(")?.upperBound,
                  let e = raw.range(of: ");", range: s..<raw.endIndex)?.lowerBound,
                  let arr = try? JSONSerialization.jsonObject(with: String(raw[s..<e]).data(using: .utf8)!) as? [[String: Any]],
                  arr.count > 2 else {
                completion(nil)
                return
            }

            func price(of item: [String: Any]) -> Double {
                Double(item["close"] as? String ?? "") ?? 0
            }
            func date(of item: [String: Any]) -> Date? {
                guard let ds = item["date"] as? String else { return nil }
                return df.date(from: ds)
            }

            let last = arr[arr.count - 1]
            let current = price(of: last)
            guard current > 0, let lastDate = date(of: last) else { completion(nil); return }

            // 找到不晚于目标日期的最近交易日（arr 按日期升序）
            func base(daysAgo: Int) -> [String: Any]? {
                guard let target = Calendar.current.date(byAdding: .day, value: -daysAgo, to: lastDate) else { return nil }
                var best: [String: Any]?
                for item in arr {
                    guard let d = date(of: item) else { continue }
                    if d <= target { best = item } else { break }
                }
                return best
            }

            let specs: [(id: String, label: String, days: Int)] = [
                ("today", "今日", 1), ("week", "近一周", 7),
                ("month", "近一月", 30), ("year", "近一年", 365)
            ]
            var result: [PeriodChange] = []
            for spec in specs {
                guard let b = base(daysAgo: spec.days), price(of: b) > 0 else { continue }
                let bp = price(of: b)
                result.append(PeriodChange(
                    id: spec.id, label: spec.label,
                    percent: (current - bp) / bp * 100,
                    currentPrice: current, basePrice: bp,
                    baseDate: b["date"] as? String ?? ""
                ))
            }

            if !result.isEmpty {
                self.cachedPeriods = result
                self.cachedDay = today
            }
            completion(result.isEmpty ? nil : result)
        }.resume()
    }

    // 上金所 Au99.99 日内分时：times[] 与 data[] 对齐，首点为昨收基准
    func fetchIntraday(completion: @escaping (IntradayData?) -> Void) {
        if let cached = cachedIntraday,
           Date().timeIntervalSince(intradayCacheTime) < 3 {
            completion(cached)
            return
        }
        // 接口偶发失败时回退到上次成功的数据，避免图表刷新后消失
        let fallback = self.cachedIntraday
        guard let url = URL(string: sgeIntradayURL) else { completion(fallback); return }
        var request = URLRequest(url: url)
        request.setValue("https://www.sge.com.cn/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let times = json["times"] as? [String],
                  let rawPrices = json["data"] as? [String],
                  !times.isEmpty, times.count == rawPrices.count else {
                completion(fallback)
                return
            }
            let prices = rawPrices.compactMap { Double($0) }
            guard prices.count == times.count, let first = prices.first else { completion(fallback); return }

            var intra = IntradayData()
            intra.times = times
            intra.prices = prices
            intra.prevClose = first            // 分时首点 = 昨收
            intra.high = (json["max"] as? NSNumber)?.doubleValue ?? prices.max() ?? 0
            intra.low = (json["min"] as? NSNumber)?.doubleValue ?? prices.min() ?? 0
            intra.updateTime = json["delaystr"] as? String ?? (json["now"] as? String ?? "")
            self.cachedIntraday = intra
            self.intradayCacheTime = Date()
            completion(intra)
        }.resume()
    }

    // 新浪 Au99.99：GBK 编码，逗号分隔
    // 实测字段: 0现价 2买价 3卖价 4最高 5最低 6时间 7昨收 8今开 12日期 13名称
    func fetchSpot(completion: @escaping (SpotGold?) -> Void) {
        guard let url = URL(string: sinaURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let raw = String(data: data, encoding: .gbk) ?? String(data: data, encoding: .utf8),
                  let quote = raw.slice(between: "\"", and: "\""),
                  !quote.isEmpty else {
                completion(nil)
                return
            }
            let f = quote.split(separator: ",").map(String.init)
            guard f.count > 8 else { completion(nil); return }

            var spot = SpotGold()
            spot.price = Double(f[0]) ?? 0
            spot.high = Double(f[4]) ?? 0
            spot.low = Double(f[5]) ?? 0
            spot.prevClose = Double(f[7]) ?? 0
            spot.open = Double(f[8]) ?? 0
            if f.count > 6 { spot.time = f[6] }
            if f.count > 12 { spot.date = f[12] }
            if f.count > 13 { spot.name = f[13] }
            completion(spot.price > 0 ? spot : nil)
        }.resume()
    }

    // xxapi.cn 聚合接口：把返回的所有价格按三组列出
    func fetchAllPrices(completion: @escaping ([PriceGroup]?) -> Void) {
        guard let url = URL(string: xxapiURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let obj = json["data"] as? [String: Any] else {
                completion(nil)
                return
            }

            var groups: [PriceGroup] = []

            // 1. 银行投资金条
            if let list = obj["bank_gold_bar_price"] as? [[String: Any]], !list.isEmpty {
                let items = list.map { item -> PriceItem in
                    PriceItem(
                        name: item["bank"] as? String ?? "",
                        price: item["price"] as? String ?? "--"
                    )
                }
                groups.append(PriceGroup(title: "银行投资金条", items: items))
            }

            // 2. 品牌金饰金价
            if let list = obj["precious_metal_price"] as? [[String: Any]], !list.isEmpty {
                let items = list.map { item -> PriceItem in
                    PriceItem(
                        name: item["brand"] as? String ?? "",
                        price: item["gold_price"] as? String ?? "--",
                        note: item["updated_date"] as? String ?? ""
                    )
                }
                groups.append(PriceGroup(title: "品牌金饰金价", items: items))
            }

            completion(groups.isEmpty ? nil : groups)
        }.resume()
    }
}

// MARK: - 工具

extension String {
    func slice(between start: String, and end: String) -> String? {
        guard let s = range(of: start)?.upperBound,
              let e = range(of: end, range: s..<endIndex)?.lowerBound else { return nil }
        return String(self[s..<e])
    }
}

extension String.Encoding {
    static let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GBK_95.rawValue)))
}
