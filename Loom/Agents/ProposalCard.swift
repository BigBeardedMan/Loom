import SwiftUI

/// Inline confirmation card rendered under an assistant message that
/// generated a list of items. Shows the items as checkbox rows, lets the
/// user pick whether to create new tabs or append to the active tab, and
/// commits via closures on `WorkspaceContext`.
struct ProposalCard: View {
    let messageID: UUID
    @Binding var proposals: [ItemProposal]
    @Binding var mode: ProposalMode
    @Binding var committedSummary: String?

    let workspace: WorkspaceContext
    let onDismiss: () -> Void

    private var acceptedCount: Int {
        proposals.filter(\.accepted).count
    }

    private var addLabel: String {
        let n = acceptedCount
        if n == 0 { return "Add" }
        return n == 1 ? "Add 1 idea" : "Add \(n) ideas"
    }

    var body: some View {
        if let summary = committedSummary {
            committedBanner(summary)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            itemList
            Divider().overlay(Color.white.opacity(0.08))
            modeRow
            actionRow
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.96, green: 0.77, blue: 0.20).opacity(0.30), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.20))
            Text("\(proposals.count) ideas for ")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
            +
            Text("\u{201C}\(workspace.activeTabName)\u{201D}")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 0.96, green: 0.77, blue: 0.20))
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach($proposals) { $item in
                itemRow($item)
            }
        }
    }

    private func itemRow(_ item: Binding<ItemProposal>) -> some View {
        Button {
            item.wrappedValue.accepted.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.wrappedValue.accepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(item.wrappedValue.accepted
                                     ? Color(red: 0.96, green: 0.77, blue: 0.20)
                                     : Color.white.opacity(0.35))
                    .padding(.top, 1)
                Text(item.wrappedValue.text)
                    .font(.system(size: 12))
                    .foregroundStyle(item.wrappedValue.accepted ? Color.primary : Color.secondary)
                    .strikethrough(!item.wrappedValue.accepted, color: Color.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    private var modeRow: some View {
        HStack(spacing: 14) {
            ForEach(ProposalMode.allCases) { option in
                modeChip(option)
            }
            Spacer()
        }
    }

    private func modeChip(_ option: ProposalMode) -> some View {
        let selected = mode == option
        return Button {
            mode = option
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(selected
                                     ? Color(red: 0.96, green: 0.77, blue: 0.20)
                                     : Color.white.opacity(0.35))
                Text(option.label)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(option == .appendToActive && !workspace.hasActiveTab)
        .opacity(option == .appendToActive && !workspace.hasActiveTab ? 0.4 : 1)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.system(size: 11, weight: .medium))
            Button(addLabel) { commit() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Color(red: 0.96, green: 0.77, blue: 0.20))
                .disabled(acceptedCount == 0)
        }
    }

    private func commit() {
        let items = proposals.filter(\.accepted).map(\.text)
        guard !items.isEmpty else { return }
        switch mode {
        case .createNewTabs:
            workspace.createTabsForItems?(items)
        case .appendToActive:
            workspace.appendToActiveTab?(items)
        }
        let summary: String
        switch mode {
        case .createNewTabs:
            summary = items.count == 1
                ? "Added 1 idea as a new tab"
                : "Added \(items.count) ideas as new tabs"
        case .appendToActive:
            summary = items.count == 1
                ? "Appended 1 idea to \u{201C}\(workspace.activeTabName)\u{201D}"
                : "Appended \(items.count) ideas to \u{201C}\(workspace.activeTabName)\u{201D}"
        }
        committedSummary = summary
    }

    private func committedBanner(_ summary: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.46))
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
