import Foundation

// MARK: - Installed apps

/// Why an app bundle cannot be removed with normal user actions.
public enum AppProtection: String, Codable, Sendable, CaseIterable, Hashable {
    /// The bundle lives under `/System`, so System Integrity Protection owns it.
    case system
    /// The bundle carries the `restricted` file flag outside `/System`
    /// (for example, Apple's Safari symlink in `/Applications`).
    case restricted

    public var title: String {
        switch self {
        case .system: return "macOS system app"
        case .restricted: return "Restricted by macOS"
        }
    }

    public var shortTitle: String {
        switch self {
        case .system: return "System"
        case .restricted: return "Restricted"
        }
    }
}

public struct InstalledApp: Identifiable, Codable, Sendable, Hashable {
    public let name: String
    public let path: String
    public let bytes: Int64
    public let protection: AppProtection

    public var id: String { path }

    public init(name: String, path: String, bytes: Int64, protection: AppProtection) {
        self.name = name
        self.path = path
        self.bytes = bytes
        self.protection = protection
    }
}

public enum AppInventory {
    /// App bundles that macOS will not let the user remove through normal means.
    ///
    /// The inventory is intentionally narrow: it measures only bundles that are
    /// already known to be protected, rather than every installed app. That keeps
    /// the scan fast and avoids turning a read-only audit into an app survey.
    public static func protectedApps(
        runner: any CommandRunning = ShellCommandRunner(),
        fileManager: FileManager = .default
    ) -> [InstalledApp] {
        var candidates: [Candidate] = []
        var seen = Set<String>()

        // Apps shipped inside /System are protected by construction.
        for directory in ["/System/Applications", "/System/Applications/Utilities"] {
            for url in appBundles(in: directory, fileManager: fileManager) {
                let resolved = url.resolvingSymlinksInPath()
                let key = resolved.path
                guard seen.insert(key).inserted else { continue }
                candidates.append(Candidate(name: displayName(for: resolved), path: key, protection: .system))
            }
        }

        // /Applications can also contain restricted bundles, usually symlinks
        // into /System/Cryptexes. Check the flag once for the whole directory.
        let applicationURLs = appBundles(in: "/Applications", fileManager: fileManager)
        var unflagged: [URL] = []
        for url in applicationURLs {
            let resolved = url.resolvingSymlinksInPath()
            let key = resolved.path
            if key.hasPrefix("/System/") {
                guard seen.insert(key).inserted else { continue }
                candidates.append(Candidate(name: displayName(for: resolved), path: key, protection: .system))
            } else {
                unflagged.append(url)
            }
        }

        let restricted = restrictedPaths(unflagged, runner: runner)
        for url in unflagged {
            let resolved = url.resolvingSymlinksInPath()
            let key = resolved.path
            let isRestricted = restricted.contains(url.path) || restricted.contains(key)
            guard let protection = protection(forPath: key, restricted: isRestricted) else { continue }
            guard seen.insert(key).inserted else { continue }
            candidates.append(Candidate(name: displayName(for: resolved), path: key, protection: protection))
        }

        guard !candidates.isEmpty else { return [] }

        let sizes = measure(candidates.map(\.path), runner: runner)
        return candidates.compactMap { candidate in
            guard let bytes = sizes[candidate.path], bytes > 0 else { return nil }
            return InstalledApp(
                name: candidate.name,
                path: candidate.path,
                bytes: bytes,
                protection: candidate.protection
            )
        }
        .sorted {
            if $0.bytes != $1.bytes { return $0.bytes > $1.bytes }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// The protection policy for an app bundle. Pure so it can be tested
    /// without enumerating the real file system.
    public static func protection(forPath path: String, restricted: Bool) -> AppProtection? {
        if path.hasPrefix("/System/") { return .system }
        if restricted { return .restricted }
        return nil
    }

    // MARK: Helpers

    private struct Candidate {
        let name: String
        let path: String
        let protection: AppProtection
    }

    private static func appBundles(in directory: String, fileManager: FileManager) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }
        return entries
            .filter { $0.lowercased().hasSuffix(".app") }
            .map { URL(fileURLWithPath: directory).appendingPathComponent($0) }
    }

    private static func displayName(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Returns the app paths whose `restricted` file flag is set.
    private static func restrictedPaths(_ urls: [URL], runner: any CommandRunning) -> Set<String> {
        guard !urls.isEmpty else { return [] }
        let result = runner.run(
            "/bin/ls",
            arguments: ["-ldO"] + urls.map(\.path),
            timeout: 8
        )
        guard !result.stdout.isEmpty else { return [] }

        var restricted = Set<String>()
        for line in result.stdout.split(separator: "\n") {
            let text = String(line)
            guard text.contains(" restricted") else { continue }
            for url in urls where text.hasSuffix(url.path) {
                restricted.insert(url.path)
            }
        }
        return restricted
    }

    private static func measure(_ paths: [String], runner: any CommandRunning) -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        let result = runner.run(
            "/usr/bin/du",
            arguments: ["-sk"] + paths,
            timeout: 20
        )
        return DuListingParser.sizes(result.stdout)
    }
}
