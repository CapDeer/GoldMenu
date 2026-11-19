import SwiftUI
import AppKit

@main
struct GoldMenuApp: App {
    @StateObject private var store = GoldStore()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(store)
        } label: {
            MenuBarLabel(spot: store.snapshot.spot)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - 菜单栏标题

struct MenuBarLabel: View {
    let spot: SpotGold?

    var body: some View {
        // 菜单栏 icon 默认按 template 渲染，会吞掉 SwiftUI 的 foregroundColor。
        // 用 NSAttributedString 把带色文字画进位图，并关闭 template，才能保留涨红跌绿。
        Image(nsImage: barImage)
            .renderingMode(.original)
    }

    // labelColor 是动态色，离屏画进 NSImage 时未绑定 appearance 会被解析成黑色。
    // 实测本机菜单栏为深色背景但 App appearance 报告 Aqua，判断不可靠，
    // 故固定用浅色字（白）——深色菜单栏上清晰可见；涨跌幅本身是红/绿也不受影响。
    private var priceColor: NSColor {
        NSColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1)
    }

    private var barImage: NSImage {
        let attr = NSMutableAttributedString()
        let priceFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let changeFont = NSFont.systemFont(ofSize: 11, weight: .semibold)

        if let s = spot {
            attr.append(NSAttributedString(
                string: String(format: "Au ¥%.2f  ", s.price),
                attributes: [.font: priceFont, .foregroundColor: priceColor]
            ))
            // 涨红跌绿（A 股习惯）
            let c = s.isUp
                ? NSColor(srgbRed: 0.85, green: 0.20, blue: 0.20, alpha: 1)
                : NSColor(srgbRed: 0.10, green: 0.62, blue: 0.30, alpha: 1)
            attr.append(NSAttributedString(
                string: String(format: "%@%.2f%%", s.isUp ? "↑" : "↓", abs(s.changePercent)),
                attributes: [.font: changeFont, .foregroundColor: c]
            ))
        } else {
            attr.append(NSAttributedString(
                string: "Au ¥--",
                attributes: [.font: priceFont, .foregroundColor: priceColor]
            ))
        }

        let textSize = attr.size()
        let image = NSImage(size: NSSize(width: ceil(textSize.width) + 2, height: 20))
        image.lockFocus()
        attr.draw(at: NSPoint(x: 1, y: (20 - textSize.height) / 2))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

// MARK: - 弹出面板

struct MenuPanel: View {
    @EnvironmentObject var store: GoldStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Text("今日金价")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.loading {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                } else {
                    Button(action: { store.refresh() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("立即刷新")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // 现货金价主区
            if let s = store.snapshot.spot {
                SpotSection(spot: s)
                // 分时走势图
                if let intra = store.snapshot.intraday, intra.isValid {
                    IntradayChart(data: intra)
                    Divider()
                }
                QuoteGrid(spot: s)
                Divider()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                    Text("金价数据获取失败").font(.system(size: 12)).foregroundColor(.secondary)
                    Button("重试") { store.refresh() }.font(.system(size: 12))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                Divider()
            }

            // 阶段涨跌幅
            PeriodSection(changes: store.snapshot.periodChanges)
                .padding(.vertical, 12)
            Divider()

            // 全部价格列表
            PriceListSection(groups: store.snapshot.priceGroups)
                .padding(.vertical, 12)
            Divider()

            // 底部栏
            HStack {
                Text(store.statusText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
    }
}

// MARK: - 现货金价区

struct SpotSection: View {
    let spot: SpotGold

    private var changeColor: Color {
        spot.isUp ? Color(red: 0.85, green: 0.25, blue: 0.25)
                  : Color(red: 0.13, green: 0.60, blue: 0.38)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("上海金 · Au99.99")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !spot.time.isEmpty {
                    Text("· \(spot.time)")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.2f", spot.price))
                    .font(.system(size: 38, weight: .semibold))
                Text("元/克")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 8) {
                Text(String(format: "%@ %.2f", spot.isUp ? "▲" : "▼", abs(spot.change)))
                    .font(.system(size: 14, weight: .medium))
                Text(String(format: "%@%.2f%%", spot.isUp ? "+" : "−", abs(spot.changePercent)))
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(changeColor.opacity(0.14))
                    .cornerRadius(5)
                Text("较昨收")
                    .font(.system(size: 10))
                    .foregroundColor(.tertiary)
            }
            .foregroundColor(changeColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 分时走势图

struct IntradayChart: View {
    let data: IntradayData
    private let chartHeight: CGFloat = 130

    private var isUp: Bool {
        (data.prices.last ?? 0) >= data.prevClose
    }
    private var lineColor: Color {
        isUp ? Color(red: 0.85, green: 0.20, blue: 0.20)
             : Color(red: 0.10, green: 0.62, blue: 0.30)
    }

    // 以昨收为中轴，取上下最大振幅作为绘制范围，保证基准线居中
    private var yRange: (min: Double, max: Double) {
        let base = data.prevClose
        let dev = data.prices.map { abs($0 - base) }.max() ?? 1
        let pad = max(dev * 0.15, 0.01)
        return (base - dev - pad, base + dev + pad)
    }

    private func xPos(_ i: Int) -> CGFloat {
        guard data.prices.count > 1 else { return 0 }
        return CGFloat(i) / CGFloat(data.prices.count - 1)
    }
    private func yPos(_ price: Double) -> CGFloat {
        let r = yRange
        guard r.max > r.min else { return 0.5 }
        return 1 - (price - r.min) / (r.max - r.min)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let h = chartHeight
                ZStack(alignment: .topLeading) {
                    // 基准虚线（昨收）
                    Path { p in
                        let y = yPos(data.prevClose) * h
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: w, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 0.8, dash: [4, 3]))

                    // 折线与填充
                    if data.prices.count > 1 {
                        let points = data.prices.enumerated().map {
                            CGPoint(x: xPos($0.offset) * w, y: yPos($0.element) * h)
                        }
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))

                        // 渐变填充到图表底部
                        Path { p in
                            p.move(to: points[0])
                            for pt in points.dropFirst() { p.addLine(to: pt) }
                            p.addLine(to: CGPoint(x: w, y: h))
                            p.addLine(to: CGPoint(x: 0, y: h))
                            p.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [lineColor.opacity(0.28), lineColor.opacity(0.0)]),
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    }
                }
            }
            .frame(height: chartHeight)

            // 时间轴
            HStack {
                Text(data.times.first ?? "")
                Spacer()
                Text("日内")
                Spacer()
                Text(data.times.last ?? "")
            }
            .font(.system(size: 9))
            .foregroundColor(.tertiary)
            .padding(.horizontal, 16)
        }
        .padding(.top, 4)
    }
}

// MARK: - 阶段涨跌幅

struct PeriodSection: View {
    let changes: [PeriodChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !changes.isEmpty {
                HStack(spacing: 8) {
                    ForEach(changes) { c in
                        VStack(spacing: 4) {
                            Text(c.label)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%@%.2f%%", c.isUp ? "+" : "−", abs(c.percent)))
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundColor(c.isUp
                                    ? Color(red: 0.85, green: 0.20, blue: 0.20)
                                    : Color(red: 0.10, green: 0.62, blue: 0.30))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(7)
                    }
                }
                .padding(.horizontal, 16)

                Text("伦敦金现货 · 周/月/年为历史基准价对比")
                    .font(.system(size: 9))
                    .foregroundColor(.tertiary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - 四宫格行情

struct QuoteGrid: View {
    let spot: SpotGold

    var body: some View {
        HStack(spacing: 0) {
            QuoteCell(label: "今开", value: spot.open)
            QuoteCell(label: "最高", value: spot.high)
            QuoteCell(label: "最低", value: spot.low)
            QuoteCell(label: "昨收", value: spot.prevClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
}

struct QuoteCell: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(String(format: "%.2f", value))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 全部价格列表

struct PriceListSection: View {
    let groups: [PriceGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("更多黄金报价")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                if !groups.isEmpty {
                    Text("\(groups.reduce(0) { $0 + $1.items.count }) 项")
                        .font(.system(size: 10))
                        .foregroundColor(.tertiary)
                }
            }
            .padding(.horizontal, 16)

            if groups.isEmpty {
                HStack {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 12))
                    Text("价格数据获取失败").font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(group.title)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)

                        ForEach(group.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.name)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                if !item.note.isEmpty {
                                    Text(item.note)
                                        .font(.system(size: 9))
                                        .foregroundColor(.tertiary)
                                }
                                Text(item.price == "--" ? "--" : "¥\(item.price)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .frame(minWidth: 58, alignment: .trailing)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                Text("聚合站每日更新，仅供比价参考 · 与银行 App 实时成交价可能存在差异")
                    .font(.system(size: 9))
                    .foregroundColor(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
    }
}

// MARK: - 状态管理

final class GoldStore: ObservableObject {
    @Published var snapshot = GoldSnapshot()
    @Published var loading = false

    private var timer: Timer?
    private var isFetching = false   // 防止 1 秒轮询下请求叠加、回调乱序

    init() {
        refresh(silent: true)
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh(silent: true)
        }
    }

    deinit { timer?.invalidate() }

    var statusText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        if snapshot.spot == nil && snapshot.priceGroups.isEmpty {
            return "数据获取失败 · 点击刷新重试"
        }
        return "更新于 \(f.string(from: snapshot.fetchTime)) · 每3秒自动刷新"
    }

    func refresh(silent: Bool = false) {
        // 上次请求未返回则跳过本次，避免高频轮询下请求堆积、价格乱跳
        guard !isFetching else { return }
        isFetching = true
        if !silent { loading = true }
        GoldService.shared.fetchAll { [weak self] newSnapshot in
            guard let self = self else { return }
            var snapshot = newSnapshot
            // 单次请求失败不能让已有数据消失（尤其图表闪没、菜单栏价格跳 --）
            if snapshot.spot == nil { snapshot.spot = self.snapshot.spot }
            if snapshot.intraday == nil { snapshot.intraday = self.snapshot.intraday }
            if snapshot.priceGroups.isEmpty { snapshot.priceGroups = self.snapshot.priceGroups }
            if snapshot.periodChanges.isEmpty { snapshot.periodChanges = self.snapshot.periodChanges }
            self.snapshot = snapshot
            self.loading = false
            self.isFetching = false
        }
    }
}

// MARK: - Color 扩展

extension Color {
    static let tertiary = Color.secondary.opacity(0.6)
}
