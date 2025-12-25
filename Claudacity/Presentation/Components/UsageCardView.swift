// MARK: - Imports
import SwiftUI

// MARK: - Usage Card View
struct UsageCardView: View {
    // MARK: Properties
    let title: String
    let percentage: Double
    let used: Int64
    let limit: Int64
    let resetTime: String?

    // MARK: Init
    init(
        title: String,
        percentage: Double,
        used: Int64,
        limit: Int64,
        resetTime: String? = nil
    ) {
        self.title = title
        self.percentage = percentage
        self.used = used
        self.limit = limit
        self.resetTime = resetTime
    }

    init(title: String, level: UsageLevel) {
        self.title = title
        self.percentage = level.percentage
        self.used = level.used
        self.limit = level.limit
        self.resetTime = level.formattedResetTime
    }

    // MARK: Body
    var body: some View {
        VStack(alignment: .leading, spacing: Dimensions.Spacing.medium) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color.claudacity.primaryText)
                Spacer()
                Text("\(Int(percentage))% left")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor(for: percentage))
            }

            // Progress Bar
            ProgressBarView(percentage: percentage)

            // Footer
            HStack {
                Text(formatTokens(used))
                    .font(.caption)
                    .foregroundColor(Color.claudacity.secondaryText)
                Spacer()
                Text(formatTokens(limit))
                    .font(.caption)
                    .foregroundColor(Color.claudacity.secondaryText)
            }

            // Reset Time (optional)
            if let resetTime = resetTime {
                HStack {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("\(String(localized: "common.reset")) \(resetTime)")
                        .font(.caption)
                }
                .foregroundColor(Color.claudacity.secondaryText)
            }
        }
        .padding()
        .background(Color.claudacity.secondaryBackground)
        .cornerRadius(Dimensions.CornerRadius.medium)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) 사용량")
        .accessibilityValue("\(Int(percentage))퍼센트 남음")
    }

    // MARK: Private Methods
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
#Preview("Normal") {
    UsageCardView(
        title: "Session",
        percentage: 72,
        used: 28000,
        limit: 100000,
        resetTime: "3h 24m"
    )
    .frame(width: 300)
    .padding()
}

#Preview("Low") {
    UsageCardView(
        title: "Daily",
        percentage: 25,
        used: 375000,
        limit: 500000,
        resetTime: "8h 15m"
    )
    .frame(width: 300)
    .padding()
}

#Preview("Critical") {
    UsageCardView(
        title: "Weekly",
        percentage: 8,
        used: 1840000,
        limit: 2000000,
        resetTime: "3d 12h"
    )
    .frame(width: 300)
    .padding()
}
