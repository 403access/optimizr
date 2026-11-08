import SwiftUI
import OptimizrCore

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            AppBackground()

            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 238)

                Divider()
                    .opacity(0.35)

                ZStack {
                    switch model.selection {
                    case .overview:
                        OverviewView()
                    case let .category(category):
                        CategoryView(category: category)
                    }

                    if model.isScanning {
                        ScanningOverlay(phase: model.scanPhase)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 26)
        }
        .task {
            model.scanIfNeeded()
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 4)
                .padding(.bottom, 22)

            VStack(spacing: 3) {
                sidebarButton(
                    title: "Overview",
                    subtitle: "Health and top fixes",
                    icon: "gauge",
                    color: Palette.memory,
                    isSelected: model.selection == .overview,
                    count: model.report.findings.count
                ) {
                    model.showOverview()
                }

                ForEach(ScanCategory.allCases) { category in
                    sidebarButton(
                        title: category.title,
                        subtitle: category.tagline,
                        icon: category.systemImage,
                        color: category.color,
                        isSelected: model.selection == .category(category),
                        count: model.report.count(for: category)
                    ) {
                        model.selectCategory(category)
                    }
                }
            }

            Spacer(minLength: 20)

            privacyNote
                .padding(.bottom, 12)

            scanButton

            if let date = model.lastScanDate {
                Text("Last scan \(Format.relativeTime(from: date))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.brandGradient)
                    .frame(width: 31, height: 31)
                    .shadow(color: Palette.memory.opacity(0.35), radius: 6, y: 2)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Optimizr")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Mac tune-up")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func sidebarButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isSelected: Bool,
        count: Int,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color.opacity(isSelected ? 0.20 : 0.12))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                }
                .frame(width: 29, height: 29)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(count == 0 ? Color.secondary : color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(color.opacity(count == 0 ? 0.06 : 0.11)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.075) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? color.opacity(0.22) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.storage)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text("Read-only by design")
                    .font(.system(size: 10, weight: .semibold))
                Text("No data leaves this Mac. Optimizr never deletes files or changes settings.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var scanButton: some View {
        Button {
            model.scan()
        } label: {
            HStack(spacing: 6) {
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(model.isScanning ? "Scanning…" : model.hasScanned ? "Scan again" : "Scan this Mac")
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(Palette.brandGradient, in: Capsule())
            .shadow(color: Palette.memory.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
    }
}

// MARK: - Overview

private struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    private var report: ScanReport { model.report }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if model.hasScanned {
                    HStack(alignment: .top, spacing: 14) {
                        healthCard
                            .frame(maxWidth: .infinity)
                        vitalsCard
                            .frame(maxWidth: .infinity)
                    }

                    HStack(spacing: 14) {
                        ForEach(ScanCategory.allCases) { category in
                            categoryCard(category)
                        }
                    }

                    opportunitiesCard

                    readOnlyFooter
                } else {
                    welcome
                }
            }
            .padding(26)
            .frame(maxWidth: 1_260, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(text: "System overview")
                Text(report.snapshot.hostName.isEmpty ? "This Mac" : report.snapshot.hostName)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(report.snapshot.osVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    model.exportReport()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(!model.hasScanned)

                Button {
                    model.scan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(model.isScanning)
            }
        }
    }

    private var healthCard: some View {
        HStack(spacing: 20) {
            ScoreRing(score: report.healthScore, size: 116, lineWidth: 11)

            VStack(alignment: .leading, spacing: 5) {
                Text("Mac health")
                    .font(.headline)
                Text(report.scoreLabel())
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(scoreColor(report.healthScore))
                Text("\(report.findings.count) finding\(report.findings.count == 1 ? "" : "s") across memory, CPU, and storage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if report.totalReclaimableBytes > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(Format.bytes(report.totalReclaimableBytes)) reclaimable")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Palette.storage)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .cardSurface()
    }

    private var vitalsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Live vitals")
                    .font(.headline)
                Spacer()
                Text("snapshot")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                spacing: 13
            ) {
                VitalRow(
                    icon: "memorychip",
                    title: "Memory",
                    value: Format.bytes(report.snapshot.memoryUsed),
                    detail: "\(Format.percent(report.snapshot.memoryFreePercent / 100)) free · \(report.snapshot.memoryPressureLabel)",
                    fraction: 1 - report.snapshot.memoryFreePercent / 100,
                    color: pressureColor(report.snapshot.memoryPressure)
                )

                VitalRow(
                    icon: "arrow.left.arrow.right",
                    title: "Swap",
                    value: Format.bytes(report.snapshot.swapUsed),
                    detail: report.snapshot.swapTotal > 0
                        ? "\(Format.percent(report.snapshot.swapFraction)) of \(Format.bytes(report.snapshot.swapTotal))"
                        : "No swap in use",
                    fraction: report.snapshot.swapFraction,
                    color: pressureColor(report.snapshot.swapFraction)
                )

                VitalRow(
                    icon: "cpu",
                    title: "CPU load",
                    value: Format.decimal(report.snapshot.loadAverage1),
                    detail: "\(report.snapshot.cpuCount) cores · \(Format.decimal(perCoreLoad))× per core",
                    fraction: min(1, perCoreLoad / 2),
                    color: loadColor(perCoreLoad)
                )

                VitalRow(
                    icon: "internaldrive",
                    title: "Disk",
                    value: Format.bytes(report.snapshot.diskFree),
                    detail: "\(Format.percent(report.snapshot.diskUsedFraction)) used of \(Format.bytes(report.snapshot.diskTotal))",
                    fraction: report.snapshot.diskUsedFraction,
                    color: report.snapshot.diskUsedFraction > 0.9 ? Palette.critical : Palette.storage
                )
            }
        }
        .cardSurface()
    }

    private var perCoreLoad: Double {
        guard report.snapshot.cpuCount > 0 else { return 0 }
        return report.snapshot.loadAverage1 / Double(report.snapshot.cpuCount)
    }

    private func pressureColor(_ value: Double) -> Color {
        switch value {
        case 0.80...: return Palette.critical
        case 0.65..<0.80: return Palette.high
        case 0.45..<0.65: return Palette.medium
        default: return Palette.storage
        }
    }

    private func loadColor(_ value: Double) -> Color {
        switch value {
        case 2.0...: return Palette.critical
        case 1.3..<2.0: return Palette.high
        case 0.8..<1.3: return Palette.medium
        default: return Palette.storage
        }
    }

    private func categoryCard(_ category: ScanCategory) -> some View {
        let score = report.score(for: category)
        let count = report.count(for: category)
        let bytes = report.reclaimableBytes(for: category)

        return Button {
            model.selectCategory(category)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    CategoryGlyph(category: category, size: 32)
                    Spacer()
                    ScoreRing(score: score, size: 42, lineWidth: 4, showCaption: false)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(category.tagline)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Divider()
                    .opacity(0.5)

                HStack(spacing: 5) {
                    Image(systemName: count == 0 ? "checkmark.circle" : "exclamationmark.circle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(count == 0 ? Palette.storage : category.color)
                    Text("\(count) finding\(count == 1 ? "" : "s")")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if bytes > 0 {
                        Text(Format.bytes(bytes))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.storage)
                    }
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(category.color.opacity(0.16), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var opportunitiesCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Top opportunities")
                    .font(.headline)
                Spacer()
                Text("\(report.findings.count) total")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if report.sortedFindings.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.storage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing to fix")
                            .font(.subheadline.weight(.semibold))
                        Text("No significant optimizations were found on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(report.sortedFindings.prefix(5)) { finding in
                        Button {
                            model.selectFinding(finding)
                        } label: {
                            FindingRow(finding: finding, compact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .cardSurface()
    }

    private var readOnlyFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            Text("Optimizr inspects the Mac and suggests fixes. It never deletes files, terminates processes, or changes settings on its own.")
                .font(.system(size: 10))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Palette.memory.opacity(0.10))
                    .frame(width: 108, height: 108)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(Palette.brandGradient)
            }
            Text("Find the drag. Fix the Mac.")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Optimizr audits memory, CPU, and storage, then shows you exactly what to do next — in priority order, with commands you can copy.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button {
                model.scan()
            } label: {
                Label("Scan this Mac", systemImage: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }
}
