// MARK: - Imports
import SwiftUI
import Charts

// MARK: - Usage Tab View
struct UsageTabView: View {
    // MARK: Properties
    @ObservedObject var viewModel: UsageViewModel
    @State private var selectedPeriod: TimePeriod = .daily

    private var chartData: [ChartDataPoint] {
        viewModel.chartData(for: selectedPeriod)
    }

    // MARK: Body
    var body: some View {
        VStack(spacing: Dimensions.Spacing.medium) {
            usageContent
        }
        .padding(.horizontal)
        .padding(.vertical, Dimensions.Spacing.medium)
        // Note: .task 제거 - 권한 요청 방지를 위해 차트 자동 로드 비활성화
        // 차트 데이터는 사용자가 명시적으로 요청할 때만 로드됨
        .onChange(of: selectedPeriod) { _, newPeriod in
            Task {
                // 차트가 표시될 때만 로드 (차트 데이터가 비어있지 않을 때만)
                if !viewModel.chartData(for: newPeriod).isEmpty {
                    await viewModel.loadChartData(for: newPeriod)
                }
            }
        }
    }

    // MARK: Usage Content
    @ViewBuilder
    private var usageContent: some View {
        if viewModel.isNotInUse {
            emptyView
        } else {
            // 사용량 섹션
            sectionHeader(String(localized: "tab.usage"))
            combinedUsageCard
            tokenBreakdownView
            
            // 통계 섹션
            sectionHeader(String(localized: "tab.stats"))
            chartCard
        }
    }

    // MARK: Combined Usage Card
    private var combinedUsageCard: some View {
        VStack(spacing: Dimensions.Spacing.medium) {
            // Session (CLI /usage)
            compactUsageRow(
                title: "Session",
                remainingPercent: viewModel.currentPercentage,
                usedPercent: viewModel.sessionUsedPercentage,
                resetTime: viewModel.sessionResetTimeFormatted
            )

            Divider()

            // Weekly (CLI /usage)
            compactUsageRow(
                title: "Weekly",
                remainingPercent: viewModel.weeklyPercentage,
                usedPercent: viewModel.weeklyUsedPercentage,
                resetTime: viewModel.weeklyResetTimeFormatted
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
    }

    private func compactUsageRow(title: String, remainingPercent: Double, usedPercent: Double, resetTime: String?) -> some View {
        VStack(spacing: Dimensions.Spacing.small) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("\(Int(remainingPercent))%")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(statusColor(for: remainingPercent))
                Spacer()
                if let reset = resetTime {
                    Text(reset)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ProgressBarView(percentage: remainingPercent, height: 6)
        }
    }



    // MARK: Token Breakdown (CLI /usage 기반)
    private var tokenBreakdownView: some View {
        HStack(spacing: 0) {
            usageStatItem(label: String(localized: "usage.session_used"), value: "\(Int(viewModel.sessionUsedPercentage))%", color: .blue)
            Spacer()
            usageStatItem(label: String(localized: "usage.weekly_used"), value: "\(Int(viewModel.weeklyUsedPercentage))%", color: .green)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
    }

    private func usageStatItem(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    // MARK: Chart Card (토큰 사용량 차트)
    private var chartCard: some View {
        VStack(spacing: Dimensions.Spacing.small) {
            // Chart Section
            VStack(alignment: .leading, spacing: Dimensions.Spacing.small) {
                Text(String(localized: "chart.token_usage"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                MiniChartView(
                    data: chartData,
                    period: selectedPeriod,
                    style: .bar,
                    height: 80,
                    showXAxis: true,
                    showYAxis: true,
                    showGrid: true,
                    animate: true
                )
            }
            
            // Period Picker (차트 아래에 위치)
            periodPicker
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
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
        .background(Color.claudacity.tertiaryBackground)
        .cornerRadius(Dimensions.CornerRadius.small)
    }

    // MARK: Empty View
    private var emptyView: some View {
        VStack(spacing: Dimensions.Spacing.medium) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.largeTitle)
                .foregroundColor(.blue)
            Text(String(localized: "usage.loading"))
                .font(.subheadline)
                .fontWeight(.medium)
            Text(String(localized: "usage.loading_desc"))
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            // CLI 상태 정보
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "usage.cli_status"))
                    .font(.caption2)
                    .fontWeight(.bold)
                Text("\(String(localized: "usage.cli_installed")) \(viewModel.isClaudeCodeInstalled ? String(localized: "common.yes") : String(localized: "common.no"))")
                    .font(.caption2)
                Text("\(String(localized: "usage.cli_available")) \(viewModel.isCLIUsageAvailable ? String(localized: "common.yes") : String(localized: "common.no"))")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)

            Button(String(localized: "common.refresh")) {
                Task {
                    await viewModel.loadCLIUsage()
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: Helpers
    private func statusColor(for percentage: Double) -> Color {
        if percentage > 50 {
            return Color.claudacity.safe
        } else if percentage > 30 {
            return Color.claudacity.caution
        } else if percentage > 10 {
            return Color.claudacity.warning
        } else {
            return Color.claudacity.danger
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

// MARK: - Preview
#Preview {
    UsageTabView(viewModel: Dependencies.shared.usageViewModel)
        .frame(width: Dimensions.Popover.width, height: 400)
}
