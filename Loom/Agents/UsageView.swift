import SwiftUI

private enum UsageDashboardMode: Hashable {
    case usage
    case limits
}

private struct LimitPressure {
    let label: String
    let detail: String
    let color: Color
}

private struct LimitMeterRow: Identifiable {
    let label: String
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?

    var id: String { label }
}

/// Single-tool usage dashboard. Each top-bar tab (Claude / Codex / Gemini)
/// instantiates its own UsageView with the matching `tool`, so each CLI gets
/// a dedicated full-width dashboard. Dismissed by clicking any workspace in
/// the sidebar.
struct UsageView: View {
    @Environment(UsageService.self) private var usage
    let tool: CLITool
    @State private var mode: UsageDashboardMode = .usage

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
                            if mode == .limits {
                                limitsDashboard
                            } else {
                                toolDashboard
                            }
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

    private var limitsDashboard: some View {
        let resolved = usage.tools.first(where: { $0.tool == tool }) ?? .unavailable(tool)
        return limitsColumn(title: "\(tool.label) Limits", tool: resolved)
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

    private func limitsColumn(title: String, tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tool.tool.brandColor)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Spacer()
                Text(tool.tool.shortLabel.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(tool.tool.brandColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(tool.tool.brandColor.opacity(0.14))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(LoomTheme.inset)
            .overlay(Divider().overlay(LoomTheme.hairline), alignment: .bottom)

            limitBody(tool)
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
    private func limitBody(_ tool: CLIToolUsage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if tool.isInstalled {
                limitHero(tool)

                if let snapshot = tool.limitSnapshot, hasLimitData(snapshot) {
                    let rows = limitRows(snapshot)
                    if !rows.isEmpty {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)
                            ],
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(rows) { row in
                                limitMeterCard(row, tint: tool.tool.brandColor)
                            }
                        }
                    }
                    limitMetadata(snapshot)
                } else {
                    noLimitSignal(tool)
                }

                localSignalGrid(tool)
            } else {
                noLimitSignal(tool)
            }
        }
    }

    private func limitHero(_ tool: CLIToolUsage) -> some View {
        let pressure = limitPressure(for: tool)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIMIT PRESSURE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(LoomTheme.mutedText)
                Text(pressure.label)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(1)
                Text(pressure.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            ZStack {
                Circle()
                    .stroke(pressure.color.opacity(0.18), lineWidth: 11)
                    .frame(width: 76, height: 76)
                Circle()
                    .trim(from: 0, to: max(0.08, CGFloat(limitPressureRatio(for: tool))))
                    .stroke(
                        pressure.color,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(pressure.color)
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    tool.tool.brandColor.opacity(0.16),
                    pressure.color.opacity(0.10),
                    LoomTheme.inset.opacity(0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tool.tool.brandColor.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func limitMeterCard(_ row: LimitMeterRow, tint: Color) -> some View {
        let width = min(max((row.usedPercent ?? 0) / 100, 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(row.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Spacer()
                Text(row.usedPercent.map(formatPercent) ?? "Unknown")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(LoomTheme.primaryText)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(LoomTheme.hairline.opacity(0.9))
                    RoundedRectangle(cornerRadius: 999)
                        .fill(limitColor(for: row.usedPercent, fallback: tint))
                        .frame(width: proxy.size.width * width)
                }
            }
            .frame(height: 7)
            HStack(spacing: 8) {
                Text(row.windowMinutes.map(formatWindow) ?? "Window unknown")
                    .lineLimit(1)
                Spacer()
                if let resetsAt = row.resetsAt {
                    Text("resets \(absoluteTime(resetsAt))")
                        .lineLimit(1)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(LoomTheme.mutedText)
        }
        .padding(12)
        .background(LoomTheme.inset.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func limitMetadata(_ snapshot: UsageLimitSnapshot) -> some View {
        HStack(spacing: 8) {
            if let plan = snapshot.planType {
                metadataPill("Plan \(plan)")
            }
            if let credits = snapshot.credits {
                metadataPill("Credits \(formatCredits(credits))")
            }
            if let reached = snapshot.reachedType {
                metadataPill("Reached \(reached)")
            }
            if let observed = snapshot.observedAt {
                metadataPill("Observed \(relativeTime(observed))")
            }
        }
    }

    private func metadataPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(LoomTheme.mutedText)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(LoomTheme.inset.opacity(0.8))
            .clipShape(Capsule())
    }

    private func noLimitSignal(_ tool: CLIToolUsage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tool.tool.brandColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text("No local limit signal found")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LoomTheme.primaryText)
                Text("\(tool.tool.label) has not written readable limit data to its local logs yet.")
                    .font(.system(size: 11))
                    .foregroundStyle(LoomTheme.mutedText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(LoomTheme.inset.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func localSignalGrid(_ tool: CLIToolUsage) -> some View {
        let columns: [GridItem] = [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            statCell("Active", formatCount(tool.activeSessions))
            statCell("Last activity", tool.lastActivity.map(relativeTime) ?? "None")
            statCell("Local tokens", formatTokens(tool.totalTokens))
        }
    }

    private var controlBar: some View {
        @Bindable var usage = usage
        return HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(UsageTimeframe.allCases) { tf in
                    usageModeButton(
                        title: tf.label,
                        isActive: mode == .usage && usage.timeframe == tf
                    ) {
                        mode = .usage
                        usage.timeframe = tf
                    }
                }
                usageModeButton(title: "Limits", isActive: mode == .limits) {
                    mode = .limits
                }
            }
            .padding(2)
            .background(LoomTheme.softPanel.opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(LoomTheme.hairline, lineWidth: 1)
            )

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

    private func usageModeButton(
        title: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isActive ? Color.white : LoomTheme.mutedText)
                .lineLimit(1)
                .frame(width: title == "Limits" ? 58 : 52, height: 24)
                .background(isActive ? tool.brandColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(title == "Limits" ? "Show local limit signals" : "Show \(title.lowercased()) usage")
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

    private func hasLimitData(_ snapshot: UsageLimitSnapshot) -> Bool {
        snapshot.primaryUsedPercent != nil
            || snapshot.primaryWindowMinutes != nil
            || snapshot.primaryResetsAt != nil
            || snapshot.secondaryUsedPercent != nil
            || snapshot.secondaryWindowMinutes != nil
            || snapshot.secondaryResetsAt != nil
            || snapshot.planType != nil
            || snapshot.credits != nil
            || snapshot.reachedType != nil
            || snapshot.observedAt != nil
    }

    private func limitRows(_ snapshot: UsageLimitSnapshot) -> [LimitMeterRow] {
        [
            LimitMeterRow(
                label: "Primary",
                usedPercent: snapshot.primaryUsedPercent,
                windowMinutes: snapshot.primaryWindowMinutes,
                resetsAt: snapshot.primaryResetsAt
            ),
            LimitMeterRow(
                label: "Secondary",
                usedPercent: snapshot.secondaryUsedPercent,
                windowMinutes: snapshot.secondaryWindowMinutes,
                resetsAt: snapshot.secondaryResetsAt
            )
        ].filter {
            $0.usedPercent != nil || $0.windowMinutes != nil || $0.resetsAt != nil
        }
    }

    private func limitPressure(for tool: CLIToolUsage) -> LimitPressure {
        guard let snapshot = tool.limitSnapshot, hasLimitData(snapshot) else {
            return LimitPressure(
                label: "No Signal",
                detail: "Loom is watching local logs for limit snapshots.",
                color: tool.tool.brandColor
            )
        }

        if let reached = snapshot.reachedType, !reached.isEmpty {
            return LimitPressure(
                label: "Limited",
                detail: "Codex reported a reached \(reached) limit.",
                color: LoomTheme.pink
            )
        }

        let peak = [
            snapshot.primaryUsedPercent,
            snapshot.secondaryUsedPercent
        ].compactMap { $0 }.max()

        guard let peak else {
            return LimitPressure(
                label: "Signal Found",
                detail: "Limit metadata is present, but usage percentage is not available.",
                color: tool.tool.brandColor
            )
        }

        if peak >= 100 {
            return LimitPressure(
                label: "Limited",
                detail: "One local meter is at or above its recorded ceiling.",
                color: LoomTheme.pink
            )
        }
        if peak >= 85 {
            return LimitPressure(
                label: "Hot",
                detail: "One limit window is running close to the ceiling.",
                color: LoomTheme.orange
            )
        }
        if peak >= 60 {
            return LimitPressure(
                label: "Warming",
                detail: "Usage is elevated inside the latest logged window.",
                color: Color(red: 0.96, green: 0.77, blue: 0.20)
            )
        }
        return LimitPressure(
            label: "Calm",
            detail: "Latest local limit snapshot has comfortable headroom.",
            color: LoomTheme.green
        )
    }

    private func limitPressureRatio(for tool: CLIToolUsage) -> Double {
        guard let snapshot = tool.limitSnapshot else { return 0.08 }
        if snapshot.reachedType != nil { return 1 }
        let peak = [
            snapshot.primaryUsedPercent,
            snapshot.secondaryUsedPercent
        ].compactMap { $0 }.max() ?? 8
        return min(max(peak / 100, 0.08), 1)
    }

    private func limitColor(for percent: Double?, fallback: Color) -> Color {
        guard let percent else { return fallback.opacity(0.45) }
        if percent >= 100 { return LoomTheme.pink }
        if percent >= 85 { return LoomTheme.orange }
        if percent >= 60 { return Color(red: 0.96, green: 0.77, blue: 0.20) }
        return fallback
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

    private func formatPercent(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.05 {
            return "\(Int(value.rounded()))%"
        }
        return String(format: "%.1f%%", value)
    }

    private func formatWindow(_ minutes: Int) -> String {
        if minutes >= 1_440, minutes % 1_440 == 0 {
            return "\(minutes / 1_440)d window"
        }
        if minutes >= 60, minutes % 60 == 0 {
            return "\(minutes / 60)h window"
        }
        return "\(minutes)m window"
    }

    private func formatCredits(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func absoluteTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}
