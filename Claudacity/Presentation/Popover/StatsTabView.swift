//
//  StatsTabView.swift
//  Claudacity
//

// MARK: - Imports
import SwiftUI
import Charts

// MARK: - Stats Tab View
struct StatsTabView: View {
    // MARK: Properties
    @ObservedObject var viewModel: UsageViewModel
    @State private var selectedPeriod: TimePeriod = .daily

    private var chartData: [ChartDataPoint] {
        viewModel.chartData(for: selectedPeriod)
    }

    private var statistics: ChartStatistics {
        ChartStatistics(data: chartData)
    }

    // MARK: Body
    var body: some View {
        VStack(spacing: Dimensions.Spacing.medium) {
            // Period Picker
            periodPicker

            // Chart
            chartSection

            // Summary Stats
            summaryView

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal)
        .padding(.vertical, Dimensions.Spacing.medium)
        .task {
            await viewModel.loadAllChartData()
        }
        .onChange(of: selectedPeriod) { _, newPeriod in
            Task {
                await viewModel.loadChartData(for: newPeriod)
            }
        }
    }

    // MARK: Period Picker
    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(TimePeriod.allCases) { period in
                Text(period.displayName)
                    .font(.caption)
                    .fontWeight(selectedPeriod == period ? .semibold : .regular)
                    .foregroundColor(selectedPeriod == period ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        selectedPeriod == period ?
                            Color.accentColor :
                            Color.clear
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriod = period
                        }
                    }
            }
        }
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.small)
    }

    // MARK: Chart Section
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: Dimensions.Spacing.small) {
            Text(String(localized: "chart.token_usage"))
                .font(.caption)
                .foregroundColor(.secondary)
            .padding(.bottom, 4)

            MiniChartView(
                data: chartData,
                period: selectedPeriod,
                style: .bar,
                height: 100,
                showXAxis: true,
                showYAxis: true,
                showGrid: true,
                animate: true
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
    }

    // MARK: Summary View
    private var summaryView: some View {
        HStack(spacing: 0) {
            statItem(
                icon: "sum",
                title: "총 사용량",
                value: formatTokens(statistics.total)
            )

            Divider()
                .frame(height: 40)

            statItem(
                icon: "chart.bar",
                title: "평균",
                value: formatTokens(statistics.average)
            )

            Divider()
                .frame(height: 40)

            statItem(
                icon: "arrow.up",
                title: "최대",
                value: formatTokens(statistics.peak)
            )
        }
        .padding(.vertical, 8)
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
    }

    private func statItem(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers
    private func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Preview
#Preview {
    StatsTabView(viewModel: Dependencies.shared.usageViewModel)
        .frame(width: Dimensions.Popover.width)
}
