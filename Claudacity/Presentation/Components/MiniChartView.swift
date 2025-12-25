//
//  MiniChartView.swift
//  Claudacity
//

// MARK: - Imports
import SwiftUI
import Charts

// MARK: - Chart Data Point
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let periodEnd: Date?
    let value: Double
    let label: String?

    init(timestamp: Date, periodEnd: Date? = nil, value: Double, label: String? = nil) {
        self.timestamp = timestamp
        self.periodEnd = periodEnd
        self.value = value
        self.label = label
    }

    init(from record: UsageRecord) {
        self.timestamp = record.timestamp
        self.periodEnd = nil
        self.value = Double(record.usedTokens)
        self.label = nil
    }
}

// MARK: - Chart Style
enum ChartStyle {
    case bar
    case line
    case area

    var gradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Time Period
enum TimePeriod: String, CaseIterable, Identifiable {
    case hourly
    case daily

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hourly: return String(localized: "period.24h")
        case .daily: return String(localized: "period.7d")
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .hourly: return .hour
        case .daily: return .day
        }
    }

    var strideCount: Int {
        switch self {
        case .hourly: return 6
        case .daily: return 1
        }
    }

    var dateFormat: Date.FormatStyle {
        switch self {
        case .hourly: return .dateTime.hour()
        case .daily: return .dateTime.weekday(.abbreviated)
        }
    }

    var durationInSeconds: TimeInterval {
        switch self {
        case .hourly: return 24 * 3600
        case .daily: return 7 * 24 * 3600
        }
    }

    var startDate: Date {
        Date().addingTimeInterval(-durationInSeconds)
    }
}

// MARK: - Mini Chart View
struct MiniChartView: View {
    // MARK: Properties
    let data: [ChartDataPoint]
    let period: TimePeriod
    var style: ChartStyle = .bar
    var height: CGFloat = 120
    var showXAxis: Bool = true
    var showYAxis: Bool = true
    var showGrid: Bool = true
    var animate: Bool = true

    @State private var animationProgress: CGFloat = 0
    @State private var selectedDate: Date?

    private var selectedPoint: ChartDataPoint? {
        guard let selectedDate = selectedDate else { return nil }
        
        // 마우스 위치(selectedDate)가 해당 기간 내에 포함되는지 확인 (Range Base Selection)
        return data.first(where: { point in
            let startDate = point.timestamp
            let endDate: Date
            
            if let periodEnd = point.periodEnd {
                endDate = periodEnd
            } else {
                // periodEnd가 없는 경우 기본 간격으로 계산
                let calendar = Calendar.current
                let component = period.calendarComponent
                // period.strideCount가 아니라 1 unit 간격(예: 1시간, 1일)으로 계산해야 개별 막대 범위가 됨
                endDate = calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate
            }
            
            return selectedDate >= startDate && selectedDate < endDate
        })
    }

    // MARK: Body
    var body: some View {
        Group {
            if data.isEmpty {
                emptyState
            } else {
                chartContent
            }
        }
        .frame(height: height)
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 0.8)) {
                    animationProgress = 1
                }
            } else {
                animationProgress = 1
            }
        }
    }

    // MARK: Chart Content
    @ViewBuilder
    private var chartContent: some View {
        let maxY = data.map(\.value).max() ?? 0
        VStack(spacing: 0) {
            // 정밀 툴팁 레이어 (차트 렌더링에 영향을 주지 않도록 Overlay 구조 활용)
            Chart(data) { point in
                switch style {
                case .bar:
                    BarMark(
                        x: .value("Time", point.timestamp, unit: period.calendarComponent),
                        y: .value("Value", point.value * animationProgress)
                    )
                    .foregroundStyle(style.gradient)
                    .opacity(selectedDate == nil || selectedPoint?.timestamp == point.timestamp ? 1 : 0.4)
                    .cornerRadius(2)

                case .line:
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value * animationProgress)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value * animationProgress)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(20)

                case .area:
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value * animationProgress)
                    )
                    .foregroundStyle(style.gradient.opacity(0.3))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value * animationProgress)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }

                // 위치 가이드라인 (막대 중앙)
                if let point = selectedPoint {
                    RuleMark(x: .value("Selected", midDate(for: point)))
                        .foregroundStyle(Color.accentColor.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            .chartXAxis(showXAxis ? .automatic : .hidden)
            .chartYAxis(showYAxis ? .automatic : .hidden)
            .chartXSelection(value: $selectedDate)
            .animation(.none, value: selectedDate)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let point = selectedPoint,
                       let xPos = proxy.position(forX: midDate(for: point)),
                       let yPos = proxy.position(forY: point.value) {
                        // ChartProxy는 plotArea 기준 좌표를 반환하므로, 전체 뷰 내에서 plotArea의 시작점(Y축 너비)을 계산해야 함
                        let plotAreaOriginX = geometry.size.width - proxy.plotAreaSize.width
                        VStack(spacing: 0) {
                            VStack(spacing: 2) {
                                Text(formatPointTime(point.timestamp))
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(formatCompact(Int64(point.value)))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.claudacity.secondaryBackground)
                                    .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                            )
                            
                            // 아래쪽 화살표 모양 (점선과 일직선)
                            Image(systemName: "triangle.fill")
                                .resizable()
                                .frame(width: 8, height: 4)
                                .rotationEffect(.degrees(180))
                                .foregroundColor(Color.claudacity.secondaryBackground)
                                .offset(y: -1)
                            
                            Spacer()
                                .frame(height: 10)
                        }
                        // .position은 뷰의 중심을 해당 좌표에 배치함.
                        // xPos는 PlotArea 기준, GeometryReader는 전체 뷰 기준이므로 Origin을 더해 보정
                        // yPos는 값의 상단 위치를 가리킴
                        .position(x: xPos + plotAreaOriginX, y: yPos - 25)
                    }
                }
            }
            .chartXAxis {
                if showXAxis {
                    AxisMarks(values: .stride(by: period.calendarComponent, count: period.strideCount)) { value in
                        AxisGridLine()
                        AxisValueLabel(format: period.dateFormat, centered: true)
                            .font(.caption2)
                    }
                }
            }
            .chartYAxis {
                if showYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        if showGrid {
                            AxisGridLine()
                        }
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(formatCompact(Int64(intValue)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .chartXScale(range: .plotDimension(padding: 12))
            .chartYScale(domain: 0...(maxY * 1.5))
        }
    }

    private func midDate(for point: ChartDataPoint) -> Date {
        if let periodEnd = point.periodEnd {
            return Date(timeIntervalSince1970: (point.timestamp.timeIntervalSince1970 + periodEnd.timeIntervalSince1970) / 2)
        }
        // 기본적으로 period가 1시간인 경우 처리
        let calendar = Calendar.current
        let component = period.calendarComponent
        if let nextDate = calendar.date(byAdding: component, value: 1, to: point.timestamp) {
            return Date(timeIntervalSince1970: (point.timestamp.timeIntervalSince1970 + nextDate.timeIntervalSince1970) / 2)
        }
        return point.timestamp
    }

    // MARK: Empty State
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(String(localized: "chart.no_data"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Helpers
    private func formatPointTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch period {
        case .hourly:
            formatter.dateFormat = "HH:mm"
        case .daily:
            formatter.dateFormat = "MM/dd"
        }
        return formatter.string(from: date)
    }

    private func formatCompact(_ count: Int64) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Compact Mini Chart (for menu bar or small spaces)
struct CompactChartView: View {
    let data: [ChartDataPoint]
    var width: CGFloat = 60
    var height: CGFloat = 20
    var color: Color = .accentColor

    var body: some View {
        if data.isEmpty {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: width, height: height)
                .cornerRadius(2)
        } else {
            Chart(data) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.5), color.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: width, height: height)
        }
    }
}

// MARK: - Chart Statistics
struct ChartStatistics {
    let total: Int64
    let average: Int64
    let peak: Int64
    let minimum: Int64

    init(data: [ChartDataPoint]) {
        let values = data.map { Int64($0.value) }
        self.total = values.reduce(0, +)
        self.average = values.isEmpty ? 0 : total / Int64(values.count)
        self.peak = values.max() ?? 0
        self.minimum = values.min() ?? 0
    }
}

// MARK: - Preview
#Preview("Bar Chart") {
    let mockData = (0..<24).map { hour in
        ChartDataPoint(
            timestamp: Date().addingTimeInterval(TimeInterval(-hour * 3600)),
            value: Double.random(in: 5000...50000)
        )
    }.reversed()

    return MiniChartView(
        data: Array(mockData),
        period: .hourly,
        style: .bar
    )
    .padding()
}

#Preview("Line Chart") {
    let mockData = (0..<7).map { day in
        ChartDataPoint(
            timestamp: Date().addingTimeInterval(TimeInterval(-day * 86400)),
            value: Double.random(in: 100000...500000)
        )
    }.reversed()

    return MiniChartView(
        data: Array(mockData),
        period: .daily,
        style: .line
    )
    .padding()
}

#Preview("Compact Chart") {
    let mockData = (0..<12).map { i in
        ChartDataPoint(
            timestamp: Date().addingTimeInterval(TimeInterval(-i * 3600)),
            value: Double.random(in: 1000...10000)
        )
    }.reversed()

    return CompactChartView(data: Array(mockData))
        .padding()
}
