import SwiftUI
import OptimizrCore

struct FindingDetailView: View {
    let finding: Finding
    @EnvironmentObject private var model: AppModel

    @State private var copiedAll = false

    private var commands: String {
        finding.remediation.compactMap(\.command).joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                evidence
                explanation
                remediation
                if !finding.paths.isEmpty { locations }
                if !finding.references.isEmpty { references }
                footer
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                CategoryPill(category: finding.category)
                SeverityBadge(severity: finding.severity)
                if let bytes = finding.reclaimableBytes, bytes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Up to \(Format.bytes(bytes))")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(Palette.storage)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Palette.storage.opacity(0.12)))
                }
                Spacer()
                if let firstPath = finding.paths.first {
                    Button {
                        model.reveal(firstPath)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text(finding.title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Text(finding.summary)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // MARK: Evidence

    @ViewBuilder
    private var evidence: some View {
        if !finding.metrics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Evidence")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 148), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(finding.metrics) { metric in
                        MetricTile(metric: metric)
                    }
                }
            }
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "What is happening")
            Text(finding.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    // MARK: Remediation

    private var remediation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "How to fix")
                Spacer()
                if !commands.isEmpty {
                    Button {
                        model.copy(commands)
                        withAnimation(.easeOut(duration: 0.15)) { copiedAll = true }
                        Task {
                            try? await Task.sleep(nanoseconds: 1_400_000_000)
                            withAnimation(.easeOut(duration: 0.2)) { copiedAll = false }
                        }
                    } label: {
                        Label(copiedAll ? "Copied" : "Copy commands", systemImage: copiedAll ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(finding.remediation.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundStyle(finding.category.color)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(finding.category.color.opacity(0.13)))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 5) {
                                Text(step.title)
                                    .font(.system(size: 12.5, weight: .semibold))
                                StepKindBadge(kind: step.kind)
                            }
                            Text(step.detail)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let command = step.command {
                                CommandBlock(command: command)
                                    .padding(.top, 2)
                            }
                        }
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.primary.opacity(0.022))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: Locations

    private var locations: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Relevant locations")

            VStack(spacing: 5) {
                ForEach(finding.paths.prefix(6), id: \.self) { path in
                    HStack(spacing: 7) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                            .foregroundStyle(finding.category.color)
                        Text(Paths.display(URL(fileURLWithPath: path)))
                            .font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer()
                        Button("Reveal") {
                            model.reveal(path)
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .insetSurface(cornerRadius: 8)
                }
            }

            if finding.paths.count > 6 {
                Text("+ \(finding.paths.count - 6) more")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
    }

    // MARK: References

    private var references: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Learn more")
            ForEach(finding.references) { reference in
                if let url = URL(string: reference.url) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10))
                            Text(reference.title)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(finding.category.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.storage)
                .padding(.top, 1)
            Text("Optimizr did not change anything on this Mac. Review commands before running them, and make sure you have a backup of anything you delete.")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}

private struct StepKindBadge: View {
    let kind: RemediationKind

    private var icon: String {
        switch kind {
        case .command: return "terminal"
        case .settings: return "gearshape"
        case .manual: return "hand.raised"
        case .restart: return "arrow.clockwise"
        }
    }

    private var label: String {
        switch kind {
        case .command: return "Command"
        case .settings: return "Settings"
        case .manual: return "Manual"
        case .restart: return "Restart"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7.5, weight: .semibold))
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.055)))
    }
}
