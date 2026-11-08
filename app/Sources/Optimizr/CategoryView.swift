import SwiftUI
import OptimizrCore

struct CategoryView: View {
    let category: ScanCategory
    @EnvironmentObject private var model: AppModel

    private var allFindings: [Finding] {
        model.report.findings(for: category)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)

            if allFindings.isEmpty && model.hasScanned {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "No \(category.title.lowercased()) issues found",
                    message: "Optimizr found no meaningful optimizations in this category. Rescan after installing apps or running heavy workloads.",
                    actionTitle: "Scan again",
                    action: { model.scan() }
                )
            } else {
                HStack(spacing: 0) {
                    listPane
                        .frame(width: 380)

                    Divider().opacity(0.35)

                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CategoryGlyph(category: category, size: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text(category.tagline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 18) {
                if model.report.reclaimableBytes(for: category) > 0 {
                    headerStat(
                        label: "Reclaimable",
                        value: Format.bytes(model.report.reclaimableBytes(for: category)),
                        color: Palette.storage
                    )
                }
                headerStat(
                    label: "Findings",
                    value: "\(model.report.count(for: category))",
                    color: category.color
                )
                ScoreRing(
                    score: model.report.score(for: category),
                    size: 44,
                    lineWidth: 4.5,
                    showCaption: false
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func headerStat(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: List

    private var listPane: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.30)

            if model.filteredFindings.isEmpty {
                EmptyStateView(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No matches",
                    message: "No findings in this category match the current filter.",
                    actionTitle: "Clear filters",
                    action: { model.clearFilters() }
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.filteredFindings) { finding in
                            Button {
                                model.selectedFindingID = finding.id
                            } label: {
                                FindingRow(
                                    finding: finding,
                                    isSelected: model.selectedFinding?.id == finding.id
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(11)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.18))
    }

    private var filterBar: some View {
        HStack(spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Filter findings", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            Menu {
                Button {
                    model.severityFilter = nil
                } label: {
                    Text("All severities")
                }
                Divider()
                ForEach([Severity.critical, .high, .medium, .low, .info], id: \.self) { severity in
                    Button {
                        model.severityFilter = severity
                    } label: {
                        HStack {
                            Text(severity.title)
                            if model.severityFilter == severity {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 9, weight: .semibold))
                    Text(model.severityFilter?.title ?? "All")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button {
                    model.scopeFilter = nil
                } label: {
                    Text("All scopes")
                }
                Divider()
                ForEach(FindingScope.allCases) { scope in
                    Button {
                        model.scopeFilter = scope
                    } label: {
                        HStack {
                            Label(scope.title, systemImage: scope.systemImage)
                            if model.scopeFilter == scope {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.scopeFilter?.systemImage ?? "square.3.layers.3d")
                        .font(.system(size: 9, weight: .semibold))
                    Text(model.scopeFilter?.shortTitle ?? "Scope")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(model.scopeFilter.map { $0.color.opacity(0.13) } ?? Color.primary.opacity(0.05))
                )
                .foregroundStyle(model.scopeFilter?.color ?? Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
    }

    // MARK: Detail

    @ViewBuilder
    private var detailPane: some View {
        if let finding = model.selectedFinding {
            FindingDetailView(finding: finding)
        } else {
            EmptyStateView(
                icon: "doc.text.magnifyingglass",
                title: "Select a finding",
                message: "Choose an opportunity to see the evidence and a step-by-step fix."
            )
        }
    }
}
