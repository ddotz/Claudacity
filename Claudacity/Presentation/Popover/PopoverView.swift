// MARK: - Imports
import SwiftUI

// MARK: - Popover View
struct PopoverView: View {
    // MARK: Properties
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var settingsStore = Dependencies.shared.settingsStore

    // MARK: Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content - 단일 뷰
            UsageTabView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            width: Dimensions.Popover.width,
            height: Dimensions.Popover.height
        )
        .preferredColorScheme(settingsStore.theme.colorScheme)
    }

    // MARK: Header View
    private var headerView: some View {
        HStack {
            // Claudacity 시그니처 아이콘 (75% 게이지)
            Image(nsImage: IconGenerator.shared.createGaugeIcon(forPercentage: 75))
                .renderingMode(.template)
                .foregroundColor(.accentColor)
            Text("Claudacity")
                .font(.headline)

            Spacer()

            // Refresh Button
            Button(action: { viewModel.refresh() }) {
                Image(systemName: viewModel.isLoading ? "arrow.clockwise" : "arrow.clockwise")
                    .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                    .animation(
                        viewModel.isLoading ?
                            .linear(duration: 1).repeatForever(autoreverses: false) :
                            .default,
                        value: viewModel.isLoading
                    )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .help("새로고침")

            // Settings Button
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("설정")
        }
        .padding()
    }


}

// MARK: - Preview
#Preview {
    let deps = Dependencies.shared
    PopoverView(viewModel: deps.usageViewModel)
}
