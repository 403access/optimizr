import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers
import OptimizrCore

enum SidebarSelection: Hashable {
    case overview
    case category(ScanCategory)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var report: ScanReport = .empty
    @Published var hasScanned = false
    @Published var isScanning = false
    @Published var selection: SidebarSelection = .overview
    @Published var selectedFindingID: String?
    @Published var severityFilter: Severity?
    @Published var searchText = ""
    @Published var scanPhase = ""
    @Published var lastError: String?

    private let engine = ScanEngine()

    var lastScanDate: Date? {
        hasScanned ? report.finishedAt : nil
    }

    var activeCategory: ScanCategory? {
        if case let .category(category) = selection { return category }
        return nil
    }

    var filteredFindings: [Finding] {
        guard let category = activeCategory else { return [] }
        var items = report.findings(for: category)
        if let severityFilter {
            items = items.filter { $0.severity == severityFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            items = items.filter { finding in
                finding.title.localizedCaseInsensitiveContains(query)
                    || finding.summary.localizedCaseInsensitiveContains(query)
                    || finding.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return items
    }

    var selectedFinding: Finding? {
        let items = filteredFindings
        if let selectedFindingID, let match = items.first(where: { $0.id == selectedFindingID }) {
            return match
        }
        return items.first
    }

    // MARK: Navigation

    func showOverview() {
        selection = .overview
    }

    func selectCategory(_ category: ScanCategory) {
        selection = .category(category)
        severityFilter = nil
        searchText = ""
        selectedFindingID = report.findings(for: category).first?.id
    }

    func selectFinding(_ finding: Finding) {
        selection = .category(finding.category)
        selectedFindingID = finding.id
    }

    func clearFilters() {
        severityFilter = nil
        searchText = ""
        selectedFindingID = filteredFindings.first?.id
    }

    // MARK: Scanning

    func scanIfNeeded() {
        guard !hasScanned, !isScanning else { return }
        scan()
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        lastError = nil
        scanPhase = "Reading memory pressure"

        Task { [weak self] in
            guard let self else { return }
            let fresh = await self.engine.scan()
            self.report = fresh
            self.hasScanned = true
            self.isScanning = false
            self.scanPhase = ""
            if case let .category(category) = self.selection {
                if let current = self.selectedFindingID,
                   fresh.findings(for: category).contains(where: { $0.id == current }) {
                    // Keep the user's place.
                } else if let first = fresh.findings(for: category).first?.id {
                    self.selectedFindingID = first
                }
            }
        }
    }

    // MARK: Actions

    func reveal(_ path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func exportReport() {
        guard hasScanned else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Optimizr-Report.md"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.title = "Export Optimizr report"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.markdown().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
        }
    }
}
