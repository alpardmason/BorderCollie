import SwiftUI

struct AgentUsageMenuBarView: View {
    @StateObject private var viewModel: MenuBarUsageViewModel

    private let runsAutoRefresh: Bool

    @MainActor
    init(viewModel: MenuBarUsageViewModel? = nil, runsAutoRefresh: Bool = true) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MenuBarUsageViewModel())
        self.runsAutoRefresh = runsAutoRefresh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(spacing: 8) {
                ForEach(viewModel.rows) { row in
                    usageRow(row)
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .topLeading)
        .task {
            await runAutoRefreshLoop()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Usage remaining", systemImage: "gauge")
                .font(.headline)

            Spacer()

            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.refresh()
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 24, height: 24)
                .opacity(viewModel.isRefreshing ? 0.45 : 1)
        }
        .buttonStyle(.borderless)
        .disabled(viewModel.isRefreshing)
        .accessibilityLabel("Refresh")
        .help("Refresh")
    }

    private func usageRow(_ row: MenuBarUsageRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.title)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(row.detail)
                .font(.callout.monospacedDigit())
                .foregroundStyle(detailForegroundStyle(for: row.state))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func runAutoRefreshLoop() async {
        guard runsAutoRefresh, !Self.isRunningInXcodePreview else {
            return
        }

        await viewModel.refresh()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }

            await viewModel.refresh()
        }
    }

    private func detailForegroundStyle(for state: MenuBarUsageRowState) -> AnyShapeStyle {
        switch state {
        case .loading:
            AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        case .success:
            AnyShapeStyle(HierarchicalShapeStyle.secondary)
        case .unavailable:
            AnyShapeStyle(Color.orange)
        }
    }
}

private extension AgentUsageMenuBarView {
    static var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

struct AgentUsageMenuBarView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        AgentUsageMenuBarView(viewModel: .preview, runsAutoRefresh: false)
            .previewDisplayName("Menu Bar Usage")
    }
}
