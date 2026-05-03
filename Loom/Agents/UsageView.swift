import SwiftUI

/// Single-tool usage dashboard. Each top-bar tab (Claude / Codex / Gemini)
/// instantiates its own UsageView with the matching `tool`, so each CLI gets
/// a dedicated full-width dashboard. Dismissed by clicking any workspace in
/// the sidebar.
struct UsageView: View {
    @Environment(UsageService.self) private var usage
    let tool: CLITool

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().overlay(LoomTheme.hairline)

            ZStack {
                if usage.tools.isEmpty {
                    placeholder
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            toolDashboard
                        }
                        .padding(16)
                    }
                    .opacity(usage.isRefreshing ? 0.25 : 1)
                    .allowsHitTesting(!usage.isRefreshing)
                }

                // Sits above existing data while a snapshot rebuilds — Year
                // refreshes can take ~minute and the unannotated wait left
                // the dashboard looking frozen.
                if usage.isRefreshing && !usage.tools.isEmpty {
                    refreshingOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LoomTheme.panel)
        .task {
            usage.requestRefresh()
        }
    }

    private var toolDashboard: some View {
        let resolved = usage.tools.first(where: { $0.tool == tool }) ?? .unavailable(tool)
        return headlineColumn(title: "\(tool.label) Usage", tool: resolved)
    }

    private var refreshingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.extraLarge)
                .scaleEffect(2.0)
                .tint(LoomTheme.primaryText)
            Text("Crunching \(usage.timeframe.headlineLabel.lowercased())…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LoomTheme.primaryText)
            Text("Reading every CLI session log on disk.")
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LoomTheme.softPanel.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(LoomTheme.hairline, lineWidth: 1)
                )
        )
    }

    private func headlineColumn(title: String, tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: tool.tool.systemImage)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tool.tool.brandColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Spacer()
                if tool.activeSessions > 0 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(LoomTheme.green)
                            .frame(width: 6, height: 6)
                        Text(tool.activeSessions == 1 ? "1 active" : "\(tool.activeSessions) active")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(LoomTheme.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(LoomTheme.green.opacity(0.14))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(LoomTheme.inset)
            .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)

            toolBody(tool)
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LoomTheme.softPanel.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func toolBody(_ tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            statusLine(for: tool)
                .font(.system(size: 10))
                .foregroundStyle(LoomTheme.mutedText)

            if tool.isInstalled {
                statGrid(tool)

                if !tool.chartBuckets.isEmpty {
                    bucketChart(tool)
                }

                analyticsRow(tool)

                if !tool.topTopics.isEmpty || tool.tool == .claude {
                    TopTopicsView(
                        title: "Top topics",
                        items: tool.topTopics.map { ($0.keyword, $0.count) },
                        tint: tool.tool.brandColor
                    )
                }

                if tool.hourlyDistribution.contains(where: { $0 > 0 }) {
                    HourlyHeatmapView(
                        title: "Tokens by hour",
                        hourly: tool.hourlyDistribution,
                        tint: tool.tool.brandColor
                    )
                }

                if !tool.recentPrompts.isEmpty {
                    RecentPromptsView(title: "Latest prompts", prompts: tool.recentPrompts)
                }

                if !tool.topProjects.isEmpty {
                    topProjectsList(tool)
                }

                if !tool.models.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "cube")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LoomTheme.mutedText)
                        Text(tool.models.joined(separator: " · "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(LoomTheme.mutedText)
                            .lineLimit(2)
                    }
                }
            } else {
                Text("Not installed — no local logs found.")
                    .font(.system(size: 11))
                    .foregroundStyle(LoomTheme.mutedText)
            }
        }
    }

    private var controlBar: some View {
        @Bindable var usage = usage
        return HStack(spacing: 10) {
            Picker("Timeframe", selection: $usage.timeframe) {
                ForEach(UsageTimeframe.allCases) { tf in
                    Text(tf.label).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)

            Spacer()

            if let stamp = usage.lastRefreshedAt {
                Text("updated \(relativeTime(stamp))")
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
            }

            Button {
                usage.requestRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoomTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Recompute totals")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LoomTheme.inset)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.extraLarge)
                .scaleEffect(2.0)
                .tint(LoomTheme.primaryText)
            Text("Crunching \(usage.timeframe.headlineLabel.lowercased())…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(LoomTheme.primaryText)
            Text("Reading every CLI session log on disk.")
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusLine(for tool: CLIToolUsage) -> Text {
        guard tool.isInstalled else {
            return Text("Awaiting first session")
        }
        if let last = tool.lastActivity {
            return Text("Last activity \(relativeTime(last))")
        }
        return Text("No usage recorded yet")
    }

    private func statGrid(_ tool: CLIToolUsage) -> some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            statCell("Sessions today",  formatCount(tool.sessionsToday))
            statCell("Sessions total",  formatCount(tool.sessionsTotal))
            statCell("Total tokens",    formatTokens(tool.totalTokens))
            statCell("Input",           formatTokens(tool.inputTokens))
            statCell("Output",          formatTokens(tool.outputTokens))
            statCell("Cached",          formatTokens(tool.cachedTokens))
        }
    }

    /// Three small donut charts laid out vertically so they fit even in
    /// the side-by-side Claude/Codex layout. Each is hidden when its source
    /// data is empty (e.g. Codex has no per-line model data yet).
    @ViewBuilder
    private func analyticsRow(_ tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if tool.totalTokens > 0 {
                PieChartView(
                    title: "Token mix",
                    slices: tokenMixSlices(tool),
                    centerLabel: formatTokens(tool.totalTokens),
                    centerSubLabel: "TOTAL"
                )
            }
            if !tool.tokensByModel.isEmpty {
                PieChartView(
                    title: "Models",
                    slices: modelSlices(tool),
                    centerLabel: "\(tool.tokensByModel.count)",
                    centerSubLabel: "MODELS"
                )
            }
            if !tool.tokensByProject.isEmpty {
                PieChartView(
                    title: "Project mix",
                    slices: projectSlices(tool),
                    centerLabel: "\(tool.tokensByProject.count)",
                    centerSubLabel: "REPOS"
                )
            }
            if tool.promptCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LoomTheme.mutedText)
                    Text("\(tool.promptCount) prompt\(tool.promptCount == 1 ? "" : "s") in window")
                        .font(.system(size: 10))
                        .foregroundStyle(LoomTheme.mutedText)
                }
            }
        }
    }

    private func tokenMixSlices(_ tool: CLIToolUsage) -> [PieSlice] {
        [
            PieSlice(label: "Input",  value: tool.inputTokens,  color: tool.tool.brandColor),
            PieSlice(label: "Output", value: tool.outputTokens, color: tool.tool.brandColor.opacity(0.55)),
            PieSlice(label: "Cached", value: tool.cachedTokens, color: LoomTheme.blue.opacity(0.7))
        ]
    }

    /// Build up to 5 brand-tinted slices for the model donut. Anything
    /// past the top 5 gets folded into "Other" so the legend stays
    /// readable.
    private func modelSlices(_ tool: CLIToolUsage) -> [PieSlice] {
        sliceMix(
            entries: tool.tokensByModel.map { (label: $0.displayName, value: $0.tokens) },
            base: tool.tool.brandColor
        )
    }

    private func projectSlices(_ tool: CLIToolUsage) -> [PieSlice] {
        sliceMix(
            entries: tool.tokensByProject.map { (label: $0.displayName, value: $0.tokens) },
            base: LoomTheme.blue
        )
    }

    private func sliceMix(
        entries: [(label: String, value: Int)],
        base: Color
    ) -> [PieSlice] {
        let palette: [Color] = [
            base,
            base.opacity(0.7),
            base.opacity(0.5),
            base.opacity(0.35),
            base.opacity(0.22)
        ]
        let cap = 5
        let head = entries.prefix(cap)
        let tail = entries.dropFirst(cap)
        var slices: [PieSlice] = []
        for (idx, entry) in head.enumerated() {
            slices.append(
                PieSlice(
                    label: entry.label,
                    value: entry.value,
                    color: palette[min(idx, palette.count - 1)]
                )
            )
        }
        let rest = tail.reduce(0) { $0 + $1.value }
        if rest > 0 {
            slices.append(PieSlice(label: "Other", value: rest, color: LoomTheme.hairline))
        }
        return slices
    }

    private func statCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(LoomTheme.mutedText)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(LoomTheme.primaryText)
        }
    }

    @ViewBuilder
    private func bucketChart(_ tool: CLIToolUsage) -> some View {
        let buckets = tool.chartBuckets
        let peak = max(buckets.map(\.tokens).max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(usage.timeframe.headlineLabel)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(LoomTheme.mutedText)
                Spacer()
                Text("Peak \(formatTokens(peak))")
                    .font(.system(size: 9))
                    .foregroundStyle(LoomTheme.mutedText)
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(buckets) { bucket in
                    let h = max(2, CGFloat(bucket.tokens) / CGFloat(peak) * 48)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(bucket.tokens > 0 ? tool.tool.brandColor.opacity(0.85) : LoomTheme.hairline)
                        .frame(height: h)
                        .frame(maxWidth: .infinity)
                        .help("\(bucket.label) — \(formatTokens(bucket.tokens)) tokens")
                }
            }
            .frame(height: 48)
            HStack(spacing: 3) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, bucket in
                    Text(shortAxisLabel(idx: idx, total: buckets.count, label: bucket.label))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(LoomTheme.mutedText.opacity(idx == 0 || idx == buckets.count - 1 || idx == buckets.count / 2 ? 1 : 0.45))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    /// Pick ~6 evenly-spaced labels so 24-hour and 30-day timeframes don't
    /// turn the axis into illegible mush. Always keeps the first and last
    /// label so the range stays anchored.
    private func shortAxisLabel(idx: Int, total: Int, label: String) -> String {
        if total <= 8 { return label }
        if idx == 0 || idx == total - 1 { return label }
        let stride = max(1, total / 6)
        return idx % stride == 0 ? label : ""
    }

    @ViewBuilder
    private func topProjectsList(_ tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Top projects")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(LoomTheme.mutedText)
            VStack(spacing: 4) {
                ForEach(tool.topProjects) { project in
                    HStack(spacing: 8) {
                        Text(project.displayName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(LoomTheme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(project.sessions == 1 ? "1 session" : "\(project.sessions) sessions")
                            .font(.system(size: 10))
                            .foregroundStyle(LoomTheme.mutedText)
                        Text(relativeTime(project.lastActivity))
                            .font(.system(size: 10))
                            .foregroundStyle(LoomTheme.mutedText)
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func formatCount(_ value: Int) -> String {
        value.formatted()
    }

    private func formatTokens(_ value: Int) -> String {
        if value == 0 { return "0" }
        if value < 1_000 { return value.formatted() }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        if value < 1_000_000 {
            let n = Double(value) / 1_000
            return (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + "K"
        }
        if value < 1_000_000_000 {
            let n = Double(value) / 1_000_000
            return (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + "M"
        }
        let n = Double(value) / 1_000_000_000
        return (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + "B"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
