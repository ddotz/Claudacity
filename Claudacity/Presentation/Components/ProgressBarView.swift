// MARK: - Imports
import SwiftUI

// MARK: - Progress Bar View
struct ProgressBarView: View {
    // MARK: Properties
    let percentage: Double
    var height: CGFloat = Dimensions.ProgressBar.height
    var showAnimation: Bool = true

    private var fillColor: Color {
        statusColor(for: percentage)
    }

    private var fillWidth: Double {
        min(max(percentage, 0), 100) / 100
    }

    // MARK: Body
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.claudacity.secondaryBackground)

                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(fillColor)
                    .frame(width: geometry.size.width * fillWidth)
                    .animation(
                        showAnimation ? .easeInOut(duration: 0.3) : nil,
                        value: percentage
                    )
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int(percentage))퍼센트")
    }
}

// MARK: - Preview
#Preview("Default") {
    VStack(spacing: 16) {
        ProgressBarView(percentage: 72)
        ProgressBarView(percentage: 45)
        ProgressBarView(percentage: 25)
        ProgressBarView(percentage: 8)
    }
    .frame(width: 300)
    .padding()
}
