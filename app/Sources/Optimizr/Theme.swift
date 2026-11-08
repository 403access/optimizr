import SwiftUI
import OptimizrCore

// MARK: - Palette

enum Palette {
    static let memory = Color(red: 0.47, green: 0.42, blue: 0.96)
    static let cpu = Color(red: 0.96, green: 0.52, blue: 0.20)
    static let storage = Color(red: 0.16, green: 0.72, blue: 0.64)

    static let critical = Color(red: 0.94, green: 0.25, blue: 0.28)
    static let high = Color(red: 0.98, green: 0.44, blue: 0.18)
    static let medium = Color(red: 0.94, green: 0.70, blue: 0.14)
    static let low = Color(red: 0.27, green: 0.57, blue: 0.96)
    static let info = Color.secondary

    static let brandGradient = LinearGradient(
        colors: [memory, storage],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension ScanCategory {
    var color: Color {
        switch self {
        case .memory: return Palette.memory
        case .cpu: return Palette.cpu
        case .storage: return Palette.storage
        }
    }
}

extension FindingScope {
    var color: Color {
        switch self {
        case .native: return Palette.storage
        case .thirdParty: return Palette.cpu
        case .mixed: return Palette.medium
        case .userData: return Palette.memory
        }
    }
}

extension Severity {
    var color: Color {
        switch self {
        case .critical: return Palette.critical
        case .high: return Palette.high
        case .medium: return Palette.medium
        case .low: return Palette.low
        case .info: return Palette.info
        }
    }
}

func scoreColor(_ score: Int) -> Color {
    switch score {
    case 80...: return Palette.storage
    case 60..<80: return Color(red: 0.55, green: 0.78, blue: 0.30)
    case 40..<60: return Palette.medium
    case 20..<40: return Palette.high
    default: return Palette.critical
    }
}

// MARK: - Background

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Palette.memory.opacity(0.18), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 760
            )
            RadialGradient(
                colors: [Palette.storage.opacity(0.12), .clear],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 700
            )
            RadialGradient(
                colors: [Palette.cpu.opacity(0.06), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Card surface

extension View {
    func cardSurface(padding: CGFloat = 18, cornerRadius: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
    }

    func insetSurface(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Small building blocks

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.3)
            .foregroundStyle(.tertiary)
    }
}

struct CategoryGlyph: View {
    let category: ScanCategory
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(category.color.opacity(0.16))
            Image(systemName: category.systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(category.color)
        }
        .frame(width: size, height: size)
    }
}
