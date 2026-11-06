import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var checks: [DiagnosticCheck] = []
    @State private var isRunning = false

    private var passedCount: Int { checks.filter(\.passed).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                VStack(spacing: 0) {
                    ForEach(Array(checks.enumerated()), id: \.element.id) { index, check in
                        row(check)
                        if index < checks.count - 1 {
                            Hairline().padding(.leading, 52)
                        }
                    }
                }
                .card(padded: false)

                Text("自检只读取本地状态，不会写入生词本，也不联网（AI 连接测试在设置页单独触发）。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("自检")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isRunning ? "运行中…" : "重新运行") {
                    run()
                }
                .font(Theme.font(size: 13, weight: .semibold))
                .disabled(isRunning)
            }
        }
        .task {
            if checks.isEmpty { run() }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(checks.isEmpty ? "尚未运行" : "\(passedCount) / \(checks.count) 项通过")
                .font(Theme.font(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("覆盖词典索引、动词还原、断词、复习算法、持久化与本地存储。")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
            if isRunning {
                ProgressView().tint(Theme.accent)
            }
        }
        .card()
    }

    private func row(_ check: DiagnosticCheck) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(Theme.font(size: 16))
                .foregroundStyle(check.passed ? Theme.jade : Theme.rose)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title)
                    .font(Theme.font(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text(check.detail)
                    .font(Theme.font(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func run() {
        isRunning = true
        // Hop to a new main-actor task so the spinner can render before the
        // synchronous checks run.
        Task { @MainActor in
            let results = Diagnostics.run(app: app)
            checks = results
            isRunning = false
        }
    }
}
