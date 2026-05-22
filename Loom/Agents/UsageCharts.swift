import SwiftUI

struct UsageBreakdownSlice: Identifiable {
    let label: String
    let value: Int
    let color: Color

    var id: String { label }
}

struct UsageBreakdownRow: Identifiable {
    let label: String
    let value: Int
    let color: Color

    var id: String { label }
}

struct UsageTokenMixView: View {
    let title: String
    let slices: [UsageBreakdownSlice]
    let totalLabel: String
    let valueFormatter: (Int) -> String

    private var total: Int { slices.reduce(0) { $0 + max($1.value, 0) } }
    private var visibleSlices: [UsageBreakdownSlice] { slices.filter { $0.value > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(title: title, detail: total > 0 ? totalLabel : nil)

            if total > 0 {
                segmentedBar
                    .frame(height: 9)
                    .clipShape(RoundedRectangle(cornerRadius: 999))
                HStack(spacing: 8) {
                    ForEach(slices) { slice in
                        mixLegendItem(slice)
                    }
                }
            } else {
                Text("No token mix in this window.")
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LoomTheme.panel.opacity(0.36))
        .overlay(
            RoundedRectangle(cornerRadius: LoomTheme.rowRadius)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.rowRadius))
    }

    private var segmentedBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(LoomTheme.hairline.opacity(0.72))

                ForEach(Array(segments(in: geo.size.width).enumerated()), id: \.offset) { _, segment in
                    Rectangle()
                        .fill(segment.slice.color)
                        .frame(width: segment.width)
                        .offset(x: segment.offset)
                        .help("\(segment.slice.label) — \(valueFormatter(segment.slice.value)) (\(percent(for: segment.slice.value)))")
                }
            }
        }
    }

    private func mixLegendItem(_ slice: UsageBreakdownSlice) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(slice.value > 0 ? slice.color : LoomTheme.hairline)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(slice.label.uppercased())
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.45)
                    .foregroundStyle(LoomTheme.mutedText)
                HStack(spacing: 4) {
                    Text(valueFormatter(slice.value))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LoomTheme.primaryText)
                    Text(percent(for: slice.value))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(LoomTheme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func segments(in width: CGFloat) -> [(slice: UsageBreakdownSlice, offset: CGFloat, width: CGFloat)] {
        guard total > 0, width > 0 else { return [] }
        var consumed = CGFloat(0)
        return visibleSlices.enumerated().map { idx, slice in
            let isLast = idx == visibleSlices.count - 1
            let segmentWidth = isLast
                ? max(0, width - consumed)
                : max(2, width * CGFloat(slice.value) / CGFloat(total))
            defer { consumed += segmentWidth }
            return (slice, consumed, segmentWidth)
        }
    }

    private func percent(for value: Int) -> String {
        guard total > 0, value > 0 else { return "0%" }
        let pct = Double(value) / Double(total) * 100
        if pct < 0.5 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }
}

struct UsageRankedBreakdownView: View {
    let title: String
    let rows: [UsageBreakdownRow]
    let emptyText: String
    let valueFormatter: (Int) -> String

    private var total: Int { rows.reduce(0) { $0 + max($1.value, 0) } }
    private var peak: Int { max(rows.map(\.value).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionHeader(title: title, detail: total > 0 ? valueFormatter(total) : nil)

            if total == 0 {
                Text(emptyText)
                    .font(.system(size: 10))
                    .foregroundStyle(LoomTheme.mutedText)
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        rankedRow(row)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(LoomTheme.panel.opacity(0.36))
        .overlay(
            RoundedRectangle(cornerRadius: LoomTheme.rowRadius)
                .stroke(LoomTheme.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: LoomTheme.rowRadius))
    }

    private func rankedRow(_ row: UsageBreakdownRow) -> some View {
        let ratio = CGFloat(row.value) / CGFloat(peak)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LoomTheme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                Text(valueFormatter(row.value))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(LoomTheme.primaryText)
                Text(percent(for: row.value))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(LoomTheme.mutedText)
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 999)
                        .fill(LoomTheme.hairline.opacity(0.54))
                    RoundedRectangle(cornerRadius: 999)
                        .fill(row.color)
                        .frame(width: max(3, geo.size.width * ratio))
                }
            }
            .frame(height: 5)
            .help("\(row.label) — \(valueFormatter(row.value)) (\(percent(for: row.value)))")
        }
    }

    private func percent(for value: Int) -> String {
        guard total > 0, value > 0 else { return "0%" }
        let pct = Double(value) / Double(total) * 100
        if pct < 0.5 { return "<1%" }
        return "\(Int(pct.rounded()))%"
    }
}

private func sectionHeader(title: String, detail: String?) -> some View {
    HStack(spacing: 8) {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(LoomTheme.mutedText)
        Spacer(minLength: 8)
        if let detail {
            Text(detail)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(LoomTheme.mutedText)
                .lineLimit(1)
        }
    }
}

/// Horizontal bar list for "top topics" — keyword + count, with a fill
/// proportional to the leader.
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
