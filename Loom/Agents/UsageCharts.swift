import SwiftUI

/// Generic donut/pie chart slice. Each piece carries a label, value, and
/// the color the slice should be drawn in. Empty input renders as a
/// hairline ring placeholder.
struct PieSlice: Identifiable, Hashable {
    let label: String
    let value: Int
    let color: Color

    var id: String { label }
}

/// Compact donut chart with an inline legend. Designed for the usage
/// dashboard — caps slice count, lumps overflow into "Other", and shows a
/// total in the donut hole.
struct PieChartView: View {
    let title: String
    let slices: [PieSlice]
    let centerLabel: String?
    let centerSubLabel: String?

    init(
        title: String,
        slices: [PieSlice],
        centerLabel: String? = nil,
        centerSubLabel: String? = nil
    ) {
        self.title = title
        self.slices = slices
        self.centerLabel = centerLabel
        self.centerSubLabel = centerSubLabel
    }

    private var total: Int { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(LoomTheme.mutedText)

            if total == 0 {
                emptyDonut
            } else {
                HStack(alignment: .center, spacing: 12) {
                    donut
                        .frame(width: 92, height: 92)
                    legend
                }
            }
        }
    }

    private var emptyDonut: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(LoomTheme.hairline, lineWidth: 12)
                    .frame(width: 92, height: 92)
                Text("—")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LoomTheme.mutedText)
            }
            Text("No data yet")
                .font(.system(size: 11))
                .foregroundStyle(LoomTheme.mutedText)
        }
    }

    private var donut: some View {
        ZStack {
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Path { path in
                    path.addArc(
                        center: CGPoint(x: 46, y: 46),
                        radius: 40,
                        startAngle: arc.start,
                        endAngle: arc.end,
                        clockwise: false
                    )
                }
                .stroke(arc.slice.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
            }
            VStack(spacing: 1) {
                if let centerLabel {
                    Text(centerLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(LoomTheme.primaryText)
                }
                if let centerSubLabel {
                    Text(centerSubLabel)
                        .font(.system(size: 8, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(LoomTheme.mutedText)
                }
            }
        }
    }

    private var arcs: [DonutArc] {
        guard total > 0 else { return [] }
        let totalDegrees: Double = 360
        var current: Double = -90 // 12 o'clock
        var out: [DonutArc] = []
        for slice in slices {
            let portion = Double(slice.value) / Double(total) * totalDegrees
            let start = Angle(degrees: current)
            let end = Angle(degrees: current + portion)
            out.append(DonutArc(slice: slice, start: start, end: end))
            current += portion
        }
        return out
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(slices) { slice in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(LoomTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(percent(for: slice))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(LoomTheme.mutedText)
                }
            }
        }
    }

    private func percent(for slice: PieSlice) -> String {
        guard total > 0 else { return "0%" }
        let pct = Double(slice.value) / Double(total) * 100
        if pct < 0.5 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }

    private struct DonutArc {
        let slice: PieSlice
        let start: Angle
        let end: Angle
    }
}

/// Horizontal bar list for "top topics" — keyword + count, with a fill
/// proportional to the leader. Compact enough to drop next to a pie chart.
struct TopTopicsView: View {
    let title: String
    let items: [(label: String, count: Int)]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(LoomTheme.mutedText)

            if items.isEmpty {
                Text("Not enough prompts yet to surface topics.")
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
            } else {
                let peak = max(items.map(\.count).max() ?? 1, 1)
                VStack(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        topicRow(item: item, peak: peak)
                    }
                }
            }
        }
    }

    private func topicRow(item: (label: String, count: Int), peak: Int) -> some View {
        let fillFraction = max(0.05, CGFloat(item.count) / CGFloat(peak))
        return HStack(spacing: 8) {
            Text(item.label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(LoomTheme.primaryText)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.tail)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(LoomTheme.hairline.opacity(0.6))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tint.opacity(0.85))
                        .frame(width: geo.size.width * fillFraction)
                }
            }
            .frame(height: 8)
            Text("\(item.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(LoomTheme.mutedText)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// 24-cell heatmap, one cell per hour-of-day. Used to show when in the
/// day the user actually drives the CLI most.
struct HourlyHeatmapView: View {
    let title: String
    let hourly: [Int]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(LoomTheme.mutedText)
                Spacer()
                if let peak = peakHourLabel {
                    Text("Peak \(peak)")
                        .font(.system(size: 9))
                        .foregroundStyle(LoomTheme.mutedText)
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    cell(for: hour)
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(label(for: hour))
                        .font(.system(size: 7, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(LoomTheme.mutedText.opacity(hour % 6 == 0 ? 1 : 0.4))
                }
            }
        }
    }

    private var peak: Int { max(hourly.max() ?? 0, 1) }

    private var peakHourLabel: String? {
        guard let max = hourly.max(), max > 0 else { return nil }
        guard let idx = hourly.firstIndex(of: max) else { return nil }
        return label(for: idx)
    }

    private func cell(for hour: Int) -> some View {
        let value = hour < hourly.count ? hourly[hour] : 0
        let intensity = CGFloat(value) / CGFloat(peak)
        return RoundedRectangle(cornerRadius: 3)
            .fill(value > 0 ? tint.opacity(0.18 + 0.72 * intensity) : LoomTheme.hairline)
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .help("\(label(for: hour)) — \(value) tokens")
    }

    private func label(for hour: Int) -> String {
        switch hour {
        case 0:  return "12a"
        case 12: return "12p"
        case 1...11: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }
}

/// Two-line preview of recent user prompts. Each row shows the prompt's
/// first line, the project, and a relative timestamp.
struct RecentPromptsView: View {
    let title: String
    let prompts: [PromptPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(LoomTheme.mutedText)
            if prompts.isEmpty {
                Text("No prompts in this window yet.")
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prompts) { prompt in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.text)
                                .font(.system(size: 11))
                                .foregroundStyle(LoomTheme.primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(prompt.project)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(LoomTheme.mutedText)
                                Text("·")
                                    .font(.system(size: 9))
                                    .foregroundStyle(LoomTheme.mutedText)
                                Text(relativeTime(prompt.timestamp))
                                    .font(.system(size: 9))
                                    .foregroundStyle(LoomTheme.mutedText)
                            }
                        }
                    }
                }
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
