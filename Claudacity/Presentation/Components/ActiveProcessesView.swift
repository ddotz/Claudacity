//
//  ActiveProcessesView.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import SwiftUI

// MARK: - Active Processes View

struct ActiveProcessesView: View {
    // MARK: Properties

    let processes: [ActiveClaudeProcess]

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if processes.isEmpty {
                emptyStateView
            } else if processes.count <= 2 {
                // 2개 이하면 스크롤 없이 표시
                ForEach(processes) { process in
                    ProcessRowView(process: process)
                }
            } else {
                // 3개 이상이면 스크롤뷰로 2개씩 표시
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        ForEach(processes) { process in
                            ProcessRowView(process: process)
                                .frame(width: 280)  // 고정 너비로 카드처럼 표시
                        }
                    }
                }
                .frame(height: 80)  // 스크롤뷰 높이 고정
            }
        }
    }

    // MARK: Subviews

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("활성 세션 없음")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("프로젝트에서 Claude Code를 실행하면 컨텍스트 사용량이 표시됩니다")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Process Row View

struct ProcessRowView: View {
    // MARK: Properties

    let process: ActiveClaudeProcess

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(process.projectName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                Text(process.formattedContextUsage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            HStack {
                Text("\(Int(process.contextUsagePercent))% used")
                    .font(.caption2)
                    .foregroundColor(usageColor)

                Spacer()

                if process.pid > 0 {
                    Text("PID: \(process.pid)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                } else {
                    Text("Session: \(String(process.sessionId.prefix(8)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }

            ProgressBar(
                percentage: process.contextUsagePercent,
                color: usageColor,
                height: 4
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: Computed Properties

    private var usageColor: Color {
        let remaining = process.contextRemainingPercent

        if remaining > 50 {
            return .green
        } else if remaining > 30 {
            return .orange
        } else {
            return .red
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    // MARK: Properties

    let percentage: Double
    let color: Color
    let height: CGFloat

    // MARK: Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .cornerRadius(height / 2)

                // Progress
                Rectangle()
                    .fill(color)
                    .frame(width: geometry.size.width * (percentage / 100))
                    .cornerRadius(height / 2)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview("With Processes") {
    ActiveProcessesView(processes: [
        ActiveClaudeProcess(
            id: 12345,
            sessionId: "pid-12345",
            pid: 12345,
            workingDirectory: "/Users/hyuns/Code/Claudacity",
            projectName: "Claudacity",
            contextTokensUsed: 32_000,
            lastModified: Date()
        ),
        ActiveClaudeProcess(
            id: 67890,
            sessionId: "pid-67890",
            pid: 67890,
            workingDirectory: "/Users/hyuns/Code/MyProject",
            projectName: "MyProject",
            contextTokensUsed: 80_000,
            lastModified: Date()
        ),
        ActiveClaudeProcess(
            id: 11111,
            sessionId: "pid-11111",
            pid: 11111,
            workingDirectory: "/Users/hyuns/Code/CriticalProject",
            projectName: "CriticalProject",
            contextTokensUsed: 185_000,
            lastModified: Date()
        )
    ])
    .padding()
    .frame(width: 320)
}

#Preview("Empty State") {
    ActiveProcessesView(processes: [])
        .padding()
        .frame(width: 320)
}
