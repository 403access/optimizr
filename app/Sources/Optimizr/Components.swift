import SwiftUI
import AppKit
import OptimizrCore

// MARK: - Score

struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 120
    var lineWidth: CGFloat = 12
    var showCaption: Bool = true

    private var color: Color { scoreColor(score) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.55), color]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: score)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if showCaption {
                    Text("of 100")
                        .font(.system(size: max(8, size * 0.08), weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Health score \(score) out of 100")
    }
}

// MARK: - Badges

struct SeverityBadge: View {
    let severity: Severity
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(severity.color)
                .frame(width: 6, height: 6)
            Text(compact ? severity.title.uppercased() : severity.title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(compact ? 0.5 : 0)
        }
        .foregroundStyle(severity.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(severity.color.opacity(0.12)))
    }
}

struct ScopeBadge: View {
    let scope: FindingScope
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scope.systemImage)
                .font(.system(size: 8.5, weight: .semibold))
            Text(compact ? scope.shortTitle : scope.title)
                .font(.system(size: 9.5, weight: .semibold))
        }
        .foregroundStyle(scope.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(scope.color.opacity(0.11)))
        .help(scope.detail)
    }
}

struct CategoryPill: View {
    let category: ScanCategory

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: category.systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(category.title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(category.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(category.color.opacity(0.12)))
    }
}

// MARK: - Meters

struct MeterBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(height, proxy.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

struct VitalRow: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let fraction: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            MeterBar(fraction: fraction, color: color)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - Finding row

struct FindingRow: View {
    let finding: Finding
    var isSelected = false
    var compact = false

    private var accent: Color { finding.severity.color }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(finding.title)
                        .font(.system(size: compact ? 12.5 : 13, weight: .semibold))
                        .lineLimit(compact ? 1 : 2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if let bytes = finding.reclaimableBytes, bytes > 0 {
                        Text(Format.bytes(bytes))
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(finding.category.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(finding.category.color.opacity(0.11)))
                    }
                }

                Text(finding.summary)
                    .font(.system(size: compact ? 10.5 : 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if !compact {
                    HStack(spacing: 6) {
                        SeverityBadge(severity: finding.severity)
                        ScopeBadge(scope: finding.scope)
                        CategoryPill(category: finding.category)
                    }
                    .padding(.top, 1)
                }
            }
        }
        .padding(.vertical, compact ? 9 : 11)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? finding.category.color.opacity(0.13) : Color.primary.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isSelected ? finding.category.color.opacity(0.45) : Color.primary.opacity(0.055),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
            Text(metric.value)
                .font(.system(size: 12.5, weight: .semibold, design: metric.isPrimary ? .rounded : .default))
                .foregroundStyle(metric.isPrimary ? Color.primary : Color.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .insetSurface()
    }
}

// MARK: - Command

struct CommandBlock: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("$")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                copy()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copied ? Palette.storage : .secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .help(copied ? "Copied" : "Copy command")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }
}

// MARK: - Empty states

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Scanning overlay

struct ScanningOverlay: View {
    let phase: String
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.4))

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Palette.memory.opacity(0.14))
                        .frame(width: 86, height: 86)
                        .scaleEffect(pulsing ? 1.12 : 0.9)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulsing)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.brandGradient)
                }
                .onAppear { pulsing = true }

                VStack(spacing: 4) {
                    Text("Scanning this Mac")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(phase.isEmpty ? "Looking for optimizations…" : phase)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }

                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 220)

                Text("Read-only. Nothing is deleted or changed.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(38)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        }
        .transition(.opacity)
    }
}
