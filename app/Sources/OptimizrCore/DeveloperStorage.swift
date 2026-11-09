import Foundation

// MARK: - Scan options

/// User-selectable scan behavior. The standard scan stays high-level; deeper
/// developer-artifact detail is opt-in because it costs more time and makes the
/// evidence list much longer.
public struct ScanOptions: Sendable, Hashable {
    /// When true, developer artifact evidence lists each nested project folder
    /// instead of collapsing to one row per repository. Artifact folders inside
    /// another artifact folder are always excluded, so node_modules is never
    /// counted twice.
    public var includeNestedDeveloperArtifacts: Bool

    public init(includeNestedDeveloperArtifacts: Bool = false) {
        self.includeNestedDeveloperArtifacts = includeNestedDeveloperArtifacts
    }

    public static let standard = ScanOptions()
}

// MARK: - Developer artifacts

/// Rebuildable folders produced by common developer toolchains.
public enum DevArtifactKind: String, Codable, Sendable, CaseIterable, Hashable {
    case nodeModules
    case pythonVirtualenv
    case rustTarget
    case mavenTarget
    case sbtTarget
    case dotnetBin
    case dotnetObj
    case cocoaPods
    case next
    case nuxt
    case svelteKit
    case turbo
    case parcelCache
    case swiftPMBuild
    case flutterBuild
    case gradleBuild
    case dartTool
    case expo
    case goVendor
    case composerVendor
    case elixirBuild
    case elixirDeps
    case zigCache
    case zigOut
    case haskellStack

    public var basename: String {
        switch self {
        case .nodeModules: return "node_modules"
        case .pythonVirtualenv: return ".venv"
        case .rustTarget, .mavenTarget, .sbtTarget: return "target"
        case .dotnetBin: return "bin"
        case .dotnetObj: return "obj"
        case .cocoaPods: return "Pods"
        case .next: return ".next"
        case .nuxt: return ".nuxt"
        case .svelteKit: return ".svelte-kit"
        case .turbo: return ".turbo"
        case .parcelCache: return ".parcel-cache"
        case .swiftPMBuild: return ".build"
        case .flutterBuild, .gradleBuild: return "build"
        case .dartTool: return ".dart_tool"
        case .expo: return ".expo"
        case .goVendor, .composerVendor: return "vendor"
        case .elixirBuild: return "_build"
        case .elixirDeps: return "deps"
        case .zigCache: return ".zig-cache"
        case .zigOut: return "zig-out"
        case .haskellStack: return ".stack-work"
        }
    }

    public var title: String {
        switch self {
        case .nodeModules: return "node_modules"
        case .pythonVirtualenv: return "Python virtualenv"
        case .rustTarget: return "Rust target"
        case .mavenTarget: return "Maven target"
        case .sbtTarget: return "sbt target"
        case .dotnetBin: return ".NET bin"
        case .dotnetObj: return ".NET obj"
        case .cocoaPods: return "CocoaPods Pods"
        case .next: return "Next.js build"
        case .nuxt: return "Nuxt build"
        case .svelteKit: return "SvelteKit build"
        case .turbo: return "Turborepo cache"
        case .parcelCache: return "Parcel cache"
        case .swiftPMBuild: return "Swift Package build"
        case .flutterBuild: return "Flutter build"
        case .gradleBuild: return "Gradle build"
        case .dartTool: return "Dart tool cache"
        case .expo: return "Expo cache"
        case .goVendor: return "Go vendor"
        case .composerVendor: return "Composer vendor"
        case .elixirBuild: return "Elixir build"
        case .elixirDeps: return "Elixir dependencies"
        case .zigCache: return "Zig cache"
        case .zigOut: return "Zig output"
        case .haskellStack: return "Haskell Stack work"
        }
    }

    /// Names that can resolve to more than one kind need validation. `target`,
    /// `build`, and `vendor` are shared across ecosystems, for example.
    public static func candidates(forBasename basename: String) -> [DevArtifactKind] {
        switch basename {
        case "node_modules":
            return [.nodeModules]
        case ".venv", "venv":
            return [.pythonVirtualenv]
        case "target":
            return [.rustTarget, .mavenTarget, .sbtTarget]
        case "bin":
            return [.dotnetBin]
        case "obj":
            return [.dotnetObj]
        case "Pods":
            return [.cocoaPods]
        case ".next":
            return [.next]
        case ".nuxt":
            return [.nuxt]
        case ".svelte-kit":
            return [.svelteKit]
        case ".turbo":
            return [.turbo]
        case ".parcel-cache":
            return [.parcelCache]
        case ".build":
            return [.swiftPMBuild]
        case "build":
            return [.flutterBuild, .gradleBuild]
        case ".dart_tool":
            return [.dartTool]
        case ".expo":
            return [.expo]
        case "vendor":
            return [.goVendor, .composerVendor]
        case "_build":
            return [.elixirBuild]
        case "deps":
            return [.elixirDeps]
        case ".zig-cache":
            return [.zigCache]
        case "zig-out":
            return [.zigOut]
        case ".stack-work":
            return [.haskellStack]
        default:
            return []
        }
    }

    /// Confirms that a matching folder really belongs to this toolchain. This
    /// keeps generic names such as `target` and `venv` from producing noise.
    public func isValid(at url: URL, fileManager: FileManager = .default) -> Bool {
        let parent = url.deletingLastPathComponent()

        func exists(_ url: URL) -> Bool {
            fileManager.fileExists(atPath: url.path)
        }

        let grandparent = parent.deletingLastPathComponent()

        func has(_ name: String, in directory: URL) -> Bool {
            exists(directory.appendingPathComponent(name))
        }

        func hasAny(_ names: [String], in directory: URL) -> Bool {
            names.contains { has($0, in: directory) }
        }

        switch self {
        case .nodeModules:
            return true
        case .pythonVirtualenv:
            return exists(url.appendingPathComponent("pyvenv.cfg"))
        case .rustTarget:
            return has("Cargo.toml", in: parent)
        case .mavenTarget:
            return has("pom.xml", in: parent)
        case .sbtTarget:
            return has("build.sbt", in: parent)
        case .dotnetBin, .dotnetObj:
            guard let contents = try? fileManager.contentsOfDirectory(atPath: parent.path) else {
                return false
            }
            return contents.contains {
                let lower = $0.lowercased()
                return lower.hasSuffix(".csproj")
                    || lower.hasSuffix(".fsproj")
                    || lower.hasSuffix(".vbproj")
                    || lower.hasSuffix(".sln")
            }
        case .cocoaPods:
            return has("Podfile", in: parent) || has("Podfile.lock", in: parent)
        case .next, .nuxt, .svelteKit, .parcelCache, .expo:
            return has("package.json", in: parent) || has("package.json", in: grandparent)
        case .turbo:
            return has("package.json", in: parent)
                || has("package.json", in: grandparent)
                || has("turbo.json", in: parent)
                || has("turbo.json", in: grandparent)
        case .swiftPMBuild:
            return has("Package.swift", in: parent)
        case .flutterBuild, .dartTool:
            return has("pubspec.yaml", in: parent)
        case .gradleBuild:
            return hasAny(["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], in: parent)
                || hasAny(["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"], in: grandparent)
        case .goVendor:
            return has("go.mod", in: parent)
        case .composerVendor:
            return has("composer.json", in: parent)
        case .elixirBuild, .elixirDeps:
            return has("mix.exs", in: parent)
        case .zigCache, .zigOut:
            return has("build.zig", in: parent)
        case .haskellStack:
            return has("stack.yaml", in: parent)
        }
    }
}

/// A discovered, measured developer artifact folder.
public struct DevArtifact: Identifiable, Codable, Sendable, Hashable {
    public let path: String
    public let kind: DevArtifactKind
    public let bytes: Int64
    /// The high-level project used for grouping. This is the nearest repository
    /// root, or the artifact's parent when the project is not a repository.
    public let projectPath: String
    /// True when the artifact belongs to a subproject below the repository root.
    public let isNested: Bool

    public var id: String { path }

    public init(
        path: String,
        kind: DevArtifactKind,
        bytes: Int64,
        projectPath: String,
        isNested: Bool
    ) {
        self.path = path
        self.kind = kind
        self.bytes = bytes
        self.projectPath = projectPath
        self.isNested = isNested
    }
}

/// One row of evidence in a developer-artifact finding.
public struct DevArtifactRow: Identifiable, Sendable, Hashable {
    public let path: String
    public let bytes: Int64
    public let isNested: Bool

    public var id: String { path }

    public init(path: String, bytes: Int64, isNested: Bool) {
        self.path = path
        self.bytes = bytes
        self.isNested = isNested
    }
}

public struct DevArtifactSummary: Sendable, Hashable {
    public let totalBytes: Int64
    public let artifactCount: Int
    public let nestedCount: Int
    public let projectCount: Int
    public let rows: [DevArtifactRow]

    public init(totalBytes: Int64, artifactCount: Int, nestedCount: Int, projectCount: Int, rows: [DevArtifactRow]) {
        self.totalBytes = totalBytes
        self.artifactCount = artifactCount
        self.nestedCount = nestedCount
        self.projectCount = projectCount
        self.rows = rows
    }
}

// MARK: - Discovery and grouping

public enum DevArtifactInventory {
    /// Common places developers keep checkouts. Keeping the list small makes
    /// the scan predictable and avoids walking entire volumes.
    public static let defaultRootNames = [
        "Developer",
        "Projects",
        "Code",
        "code",
        "src",
        "Sources",
        "repos",
        "Repos",
        "git",
        "Git",
        "workspace",
        "Workspace",
        "Documents/GitHub",
        "Documents/Projects",
        "Desktop"
    ]

    public static let trackedBasenames = [
        "node_modules",
        ".venv",
        "venv",
        "target",
        "bin",
        "obj",
        "Pods",
        ".next",
        ".nuxt",
        ".svelte-kit",
        ".turbo",
        ".parcel-cache",
        ".build",
        "build",
        ".dart_tool",
        ".expo",
        "vendor",
        "_build",
        "deps",
        ".zig-cache",
        "zig-out",
        ".stack-work"
    ]

    public static func roots(
        home: URL = Paths.home,
        fileManager: FileManager = .default
    ) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for name in defaultRootNames {
            let url = home.appendingPathComponent(name).standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            result.append(url)
        }
        return result
    }

    public static func findArguments(roots: [URL], maxDepth: Int) -> [String] {
        var arguments: [String] = roots.map(\.path)
        arguments.append(contentsOf: ["-maxdepth", "\(max(1, maxDepth))"])

        // Never descend into version control metadata.
        arguments.append(contentsOf: ["(", "-name", ".git", "-o", "-name", ".hg", "-o", "-name", ".svn", ")", "-prune", "-o"])

        // Match artifact folders, prune them, and print only the match. Pruning
        // is what prevents nested node_modules installs from being counted twice.
        arguments.append(contentsOf: ["(", "-type", "d", "("])
        for (index, name) in trackedBasenames.enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments.append(contentsOf: ["-name", name])
        }
        arguments.append(contentsOf: [")", "-prune", "-print", ")"])

        return arguments
    }

    /// Resolves a high-level project path. The nearest repository metadata wins;
    /// otherwise the artifact's parent is the project.
    public static func projectRoot(
        for artifactPath: String,
        roots: [URL],
        home: URL = Paths.home,
        fileManager: FileManager = .default
    ) -> (path: String, nested: Bool) {
        let artifactURL = URL(fileURLWithPath: artifactPath)
        let parent = artifactURL.deletingLastPathComponent().standardizedFileURL
        let rootPaths = Set(roots.map { $0.standardizedFileURL.path })

        var directory = parent
        var repository: URL?

        while true {
            let git = directory.appendingPathComponent(".git")
            let hg = directory.appendingPathComponent(".hg")
            if fileManager.fileExists(atPath: git.path) || fileManager.fileExists(atPath: hg.path) {
                repository = directory
                break
            }
            if rootPaths.contains(directory.path) || directory.path == home.standardizedFileURL.path {
                break
            }
            let next = directory.deletingLastPathComponent().standardizedFileURL
            if next.path == directory.path { break }
            directory = next
        }

        let project = (repository ?? parent).standardizedFileURL
        return (project.path, project.path != parent.path)
    }

    /// Parses `find` output, validates ambiguous folder names, and resolves each
    /// artifact to its high-level project.
    public static func parse(
        _ output: String,
        roots: [URL],
        home: URL = Paths.home,
        fileManager: FileManager = .default
    ) -> [DiscoveredDevArtifact] {
        var seen = Set<String>()
        var artifacts: [DiscoveredDevArtifact] = []

        for line in output.split(separator: "\n") {
            let path = String(line)
            guard path.hasPrefix("/"), seen.insert(path).inserted else { continue }

            let url = URL(fileURLWithPath: path)
            let basename = url.lastPathComponent
            guard let kind = DevArtifactKind.candidates(forBasename: basename)
                .first(where: { $0.isValid(at: url, fileManager: fileManager) }) else {
                continue
            }

            let project = projectRoot(for: path, roots: roots, home: home, fileManager: fileManager)
            artifacts.append(DiscoveredDevArtifact(
                path: url.standardizedFileURL.path,
                kind: kind,
                projectPath: project.path,
                isNested: project.nested
            ))
        }

        return artifacts.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Collapses artifacts to one row per project by default. With `includeNested`,
    /// each artifact is listed instead, so monorepo package folders become visible.
    /// The total always includes every measurement exactly once.
    public static func summarize(_ artifacts: [DevArtifact], includeNested: Bool) -> DevArtifactSummary {
        let total = artifacts.reduce(Int64(0)) { $0 + $1.bytes }
        let nestedCount = artifacts.lazy.filter(\.isNested).count

        let grouped = Dictionary(grouping: artifacts, by: \.projectPath)
            .map { projectPath, items in
                DevArtifactRow(
                    path: projectPath,
                    bytes: items.reduce(Int64(0)) { $0 + $1.bytes },
                    isNested: false
                )
            }
            .sorted { lhs, rhs in
                if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }

        let rows: [DevArtifactRow]
        if includeNested {
            rows = artifacts
                .map { DevArtifactRow(path: $0.path, bytes: $0.bytes, isNested: $0.isNested) }
                .sorted { lhs, rhs in
                    if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
                    return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
                }
        } else {
            rows = grouped
        }

        return DevArtifactSummary(
            totalBytes: total,
            artifactCount: artifacts.count,
            nestedCount: nestedCount,
            projectCount: grouped.count,
            rows: rows
        )
    }
}

public struct DiscoveredDevArtifact: Identifiable, Sendable, Hashable {
    public let path: String
    public let kind: DevArtifactKind
    public let projectPath: String
    public let isNested: Bool

    public var id: String { path }

    public init(path: String, kind: DevArtifactKind, projectPath: String, isNested: Bool) {
        self.path = path
        self.kind = kind
        self.projectPath = projectPath
        self.isNested = isNested
    }
}

// MARK: - Scanner

/// Finds rebuildable project folders such as node_modules and aggregates them
/// into a small number of high-level storage findings.
public struct DevArtifactScanner: OptimizrScanner {
    public let category: ScanCategory = .storage
    private let runner: any CommandRunning
    private let options: ScanOptions
    private let home: URL

    private static let reportThreshold = 500 * ByteMath.megabyte
    private static let highThreshold = 3 * ByteMath.gigabyte
    private static let criticalThreshold = 10 * ByteMath.gigabyte
    private static let maxArtifacts = 500

    public init(
        runner: any CommandRunning = ShellCommandRunner(),
        options: ScanOptions = .standard,
        home: URL = Paths.home
    ) {
        self.runner = runner
        self.options = options
        self.home = home
    }

    public func scan() -> [Finding] {
        let roots = DevArtifactInventory.roots(home: home)
        guard !roots.isEmpty else { return [] }

        let maxDepth = options.includeNestedDeveloperArtifacts ? 8 : 5
        let findResult = runner.run(
            "/usr/bin/find",
            arguments: DevArtifactInventory.findArguments(roots: roots, maxDepth: maxDepth),
            timeout: 15
        )
        guard !findResult.stdout.isEmpty else { return [] }

        let discovered = Array(
            DevArtifactInventory.parse(
                findResult.stdout,
                roots: roots,
                home: home
            )
            .prefix(Self.maxArtifacts)
        )
        guard !discovered.isEmpty else { return [] }

        let sizes = measure(discovered)
        let measured = discovered.compactMap { artifact -> DevArtifact? in
            guard let bytes = sizes[artifact.path], bytes > 0 else { return nil }
            return DevArtifact(
                path: artifact.path,
                kind: artifact.kind,
                bytes: bytes,
                projectPath: artifact.projectPath,
                isNested: artifact.isNested
            )
        }
        guard !measured.isEmpty else { return [] }

        var findings: [Finding] = []
        let nodeModules = measured.filter { $0.kind == .nodeModules }
        if let finding = finding(
            for: nodeModules,
            group: .nodeModules,
            roots: roots,
            truncated: discovered.count >= Self.maxArtifacts
        ) {
            findings.append(finding)
        }

        let buildArtifacts = measured.filter { $0.kind != .nodeModules }
        if let finding = finding(
            for: buildArtifacts,
            group: .buildArtifacts,
            roots: roots,
            truncated: discovered.count >= Self.maxArtifacts
        ) {
            findings.append(finding)
        }

        return findings
    }

    private func measure(_ artifacts: [DiscoveredDevArtifact]) -> [String: Int64] {
        let lock = NSLock()
        var sizes: [String: Int64] = [:]
        let runner = self.runner

        // Process a small batch at a time. A single du over every folder is
        // faster in theory, but it buffers output and loses everything if the
        // whole run hits the deadline on a large dependency tree.
        let batchSize = 6
        var index = 0
        while index < artifacts.count {
            let end = min(index + batchSize, artifacts.count)
            let batch = Array(artifacts[index..<end])
            DispatchQueue.concurrentPerform(iterations: batch.count) { offset in
                let artifact = batch[offset]
                let result = runner.run(
                    "/usr/bin/du",
                    arguments: ["-sk", artifact.path],
                    timeout: 20
                )
                guard let bytes = DuParser.bytes(result.stdout) else { return }
                lock.lock()
                sizes[artifact.path] = bytes
                lock.unlock()
            }
            index = end
        }

        return sizes
    }

    private enum FindingGroup: Equatable {
        case nodeModules
        case buildArtifacts

        var id: String {
            switch self {
            case .nodeModules: return "storage.dev-node-modules"
            case .buildArtifacts: return "storage.dev-build-artifacts"
            }
        }

        var titlePrefix: String {
            switch self {
            case .nodeModules: return "node_modules folders"
            case .buildArtifacts: return "Developer build artifacts"
            }
        }

        var summary: String {
            switch self {
            case .nodeModules:
                return "They are installed JavaScript dependencies, and every folder can be recreated from the project's lockfile — a safe, high-value cleanup target."
            case .buildArtifacts:
                return "They are rebuildable output from JavaScript, Python, Rust, Java, .NET, Swift, Flutter, CocoaPods, Go, Elixir, Zig, and Haskell toolchains. The source and project files stay in place; the next build recreates these folders."
            }
        }

        var detail: String {
            switch self {
            case .nodeModules:
                return "node_modules contains a project-local copy of every installed dependency for npm, pnpm, Yarn, and Bun projects. Removing it does not touch source files or the lockfile, but the next install needs network access and time. The scan prunes matched folders, so a node_modules inside another node_modules is never counted twice. Evidence is grouped by repository root by default; enable “Show nested dev folders” in the sidebar to list each monorepo package separately."
            case .buildArtifacts:
                return "These folders are outputs: Python virtualenvs, Rust/Maven/sbt/Gradle target and build directories, .NET bin/obj folders, CocoaPods Pods, SwiftPM and Flutter builds, Expo and Dart caches, vendored Go or Composer dependencies, and Elixir/Zig/Haskell build folders. They are recreated by the normal build or install command. Removing them does not touch source files, but the next build is slower and may need network access. Evidence is grouped by repository root by default; enable “Show nested dev folders” in the sidebar to list each nested project separately."
            }
        }
    }

    private func finding(
        for artifacts: [DevArtifact],
        group: FindingGroup,
        roots: [URL],
        truncated: Bool
    ) -> Finding? {
        guard !artifacts.isEmpty else { return nil }

        let summary = DevArtifactInventory.summarize(
            artifacts,
            includeNested: options.includeNestedDeveloperArtifacts
        )
        guard let severity = ByteMath.severity(
            for: summary.totalBytes,
            reportThreshold: Self.reportThreshold,
            highThreshold: Self.highThreshold,
            criticalThreshold: Self.criticalThreshold
        ) else {
            return nil
        }

        var metrics: [Metric] = [
            Metric(label: "Reclaimable", value: Format.bytes(summary.totalBytes), isPrimary: true),
            Metric(label: "Projects", value: "\(summary.projectCount)"),
            Metric(label: "Folders", value: "\(summary.artifactCount)")
        ]
        if summary.nestedCount > 0 {
            metrics.append(Metric(
                label: "Nested folders",
                value: options.includeNestedDeveloperArtifacts
                    ? "\(summary.nestedCount) listed"
                    : "\(summary.nestedCount) grouped"
            ))
        }
        for row in summary.rows.prefix(8) {
            metrics.append(Metric(
                label: displayPath(row.path),
                value: Format.bytes(row.bytes)
            ))
        }
        if truncated {
            metrics.append(Metric(label: "Scan limit", value: "First \(Self.maxArtifacts) folders measured"))
        }

        let folderWord = summary.artifactCount == 1 ? "folder" : "folders"
        let projectWord = summary.projectCount == 1 ? "project" : "projects"
        let nestedNote = summary.nestedCount > 0 && !options.includeNestedDeveloperArtifacts
            ? " \(summary.nestedCount) nested \(summary.nestedCount == 1 ? "folder is" : "folders are") grouped under their repository."
            : ""

        let rootsText = roots.map { displayPath($0.path) }.joined(separator: ", ")
        let detail = group.detail + " Scanned \(rootsText)." + nestedNote
        let presentNames = Array(Set(artifacts.map(\.kind.basename))).sorted()
        let cleanupRoots = roots.filter { root in
            artifacts.contains { $0.path.hasPrefix(root.path + "/") }
        }

        return Finding(
            id: group.id,
            category: .storage,
            title: "\(group.titlePrefix): \(Format.bytes(summary.totalBytes))",
            summary: "\(summary.artifactCount) \(folderWord) across \(summary.projectCount) \(projectWord) hold \(Format.bytes(summary.totalBytes)). \(group.summary)",
            detail: detail,
            severity: severity,
            scope: .thirdParty,
            reclaimableBytes: summary.totalBytes,
            metrics: metrics,
            remediation: remediation(
                for: group,
                summary: summary,
                roots: cleanupRoots,
                presentNames: presentNames
            ),
            paths: Array(summary.rows.prefix(50).map(\.path)),
            tags: group == .nodeModules
                ? ["developer", "node", "node_modules", "dependencies"]
                : ["developer", "build-artifacts", "caches"]
        )
    }

    private func remediation(
        for group: FindingGroup,
        summary: DevArtifactSummary,
        roots: [URL],
        presentNames: [String]
    ) -> [RemediationStep] {
        let firstPath = summary.rows.first?.path
        let rootDisplay = roots.map { displayPath($0.path) }.joined(separator: ", ")
        let rootArguments = roots.map { shellQuoted($0.path) }.joined(separator: " ")

        var steps: [RemediationStep] = []

        if let firstPath {
            steps.append(RemediationStep(
                title: "Review the largest folder",
                detail: "Open the project in Finder and confirm it is a build artifact, not source you need to keep.",
                command: "open \(shellQuoted(firstPath))",
                kind: .command
            ))
        }

        switch group {
        case .nodeModules:
            steps.append(RemediationStep(
                title: "Remove one project at a time",
                detail: "Run this from the project root, or replace the path with the project you reviewed. Keep package.json and the lockfile.",
                command: "rm -rf node_modules",
                kind: .command
            ))
            steps.append(RemediationStep(
                title: "Reinstall when you need the project",
                detail: "Use the package manager that owns the lockfile: npm ci, pnpm install, yarn install, or bun install. This downloads dependencies again.",
                kind: .manual
            ))
        case .buildArtifacts:
            steps.append(RemediationStep(
                title: "Rebuild with the project's normal command",
                detail: "Use cargo build, python -m venv .venv, pod install, or the project's npm script after removing a folder. The toolchain recreates it.",
                kind: .manual
            ))
        }

        if !roots.isEmpty {
            let names = group == .nodeModules
                ? ["node_modules"]
                : presentNames
            let nameExpression = names
                .map { "-name \($0)" }
                .joined(separator: " -o ")
            // Escape the grouping parentheses: the command is copied into an
            // interactive shell, and zsh treats a bare `(` as a glob qualifier
            // ("unknown file attribute").
            let expression = "\\( \(nameExpression) \\) -type d -prune"

            steps.append(RemediationStep(
                title: "Preview a bulk cleanup",
                detail: "This lists matching folders under \(rootDisplay) without deleting anything. Check that every match is a rebuildable artifact.",
                command: "find \(rootArguments) \(expression) -print",
                kind: .command
            ))
            steps.append(RemediationStep(
                title: "Remove the reviewed folders",
                detail: "Destructive: this deletes every listed folder under \(rootDisplay). Run the preview first, keep source and lockfiles, and expect the next build or install to be slower.",
                command: "find \(rootArguments) \(expression) -exec rm -rf {} +",
                kind: .command
            ))
        }

        return steps
    }

    private func displayPath(_ path: String) -> String {
        Paths.display(URL(fileURLWithPath: path))
    }

    private func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Global package caches

/// Download caches owned by developer package managers. They are global (not
/// project-local), re-downloadable, and often several gigabytes.
public enum DevCacheCatalog {
    public struct Entry: Sendable, Hashable {
        public let id: String
        public let managerID: String
        public let managerTitle: String
        public let relativePath: String
        public let cleanupCommand: String
        public let cleanupDetail: String

        public var url: URL { Paths.home(relativePath) }
    }

    public static let reportThreshold = 500 * ByteMath.megabyte
    public static let highThreshold = 3 * ByteMath.gigabyte
    public static let criticalThreshold = 10 * ByteMath.gigabyte

    public static let entries: [Entry] = [
        Entry(
            id: "dev.npm.cacache",
            managerID: "npm",
            managerTitle: "npm",
            relativePath: ".npm/_cacache",
            cleanupCommand: "npm cache clean --force",
            cleanupDetail: "Removes npm's content-addressable download cache. Installed projects are untouched."
        ),
        Entry(
            id: "dev.pnpm.store.local",
            managerID: "pnpm",
            managerTitle: "pnpm",
            relativePath: ".local/share/pnpm/store",
            cleanupCommand: "pnpm store prune",
            cleanupDetail: "Removes unreferenced packages from the pnpm store. Projects keep their installed links."
        ),
        Entry(
            id: "dev.pnpm.store.library",
            managerID: "pnpm",
            managerTitle: "pnpm",
            relativePath: "Library/pnpm/store",
            cleanupCommand: "pnpm store prune",
            cleanupDetail: "Removes unreferenced packages from the pnpm store. Projects keep their installed links."
        ),
        Entry(
            id: "dev.pnpm.store.legacy",
            managerID: "pnpm",
            managerTitle: "pnpm",
            relativePath: ".pnpm-store",
            cleanupCommand: "pnpm store prune",
            cleanupDetail: "Removes unreferenced packages from the pnpm store. Projects keep their installed links."
        ),
        Entry(
            id: "dev.yarn.classic",
            managerID: "yarn",
            managerTitle: "Yarn",
            relativePath: "Library/Caches/Yarn",
            cleanupCommand: "yarn cache clean",
            cleanupDetail: "Removes Yarn's download cache. The next install downloads packages again."
        ),
        Entry(
            id: "dev.yarn.berry",
            managerID: "yarn",
            managerTitle: "Yarn",
            relativePath: ".yarn/berry/cache",
            cleanupCommand: "yarn cache clean",
            cleanupDetail: "Removes Yarn Berry's download cache. The next install downloads packages again."
        ),
        Entry(
            id: "dev.bun.install",
            managerID: "bun",
            managerTitle: "Bun",
            relativePath: ".bun/install/cache",
            cleanupCommand: "bun pm cache rm",
            cleanupDetail: "Removes Bun's package cache. The next install downloads packages again."
        ),
        Entry(
            id: "dev.pip",
            managerID: "pip",
            managerTitle: "pip",
            relativePath: "Library/Caches/pip",
            cleanupCommand: "pip cache purge",
            cleanupDetail: "Removes pip's wheel and HTTP cache. The next install may rebuild or re-download packages."
        ),
        Entry(
            id: "dev.uv",
            managerID: "uv",
            managerTitle: "uv",
            relativePath: "Library/Caches/uv",
            cleanupCommand: "uv cache clean",
            cleanupDetail: "Removes uv's package cache. The next sync downloads packages again."
        ),
        Entry(
            id: "dev.cargo.registry",
            managerID: "cargo",
            managerTitle: "Cargo",
            relativePath: ".cargo/registry/cache",
            cleanupCommand: "rm -rf ~/.cargo/registry/cache/* ~/.cargo/git/db/*",
            cleanupDetail: "Removes downloaded crate archives and bare Git dependency checkouts. The next build fetches them again."
        ),
        Entry(
            id: "dev.cargo.git",
            managerID: "cargo",
            managerTitle: "Cargo",
            relativePath: ".cargo/git/db",
            cleanupCommand: "rm -rf ~/.cargo/registry/cache/* ~/.cargo/git/db/*",
            cleanupDetail: "Removes downloaded crate archives and bare Git dependency checkouts. The next build fetches them again."
        ),
        Entry(
            id: "dev.go.modules",
            managerID: "go",
            managerTitle: "Go",
            relativePath: "go/pkg/mod",
            cleanupCommand: "go clean -modcache && go clean -cache",
            cleanupDetail: "Removes the Go module and build caches. The next build downloads modules again and is slower."
        ),
        Entry(
            id: "dev.go.build",
            managerID: "go",
            managerTitle: "Go",
            relativePath: "Library/Caches/go-build",
            cleanupCommand: "go clean -modcache && go clean -cache",
            cleanupDetail: "Removes the Go module and build caches. The next build downloads modules again and is slower."
        ),
        Entry(
            id: "dev.gradle",
            managerID: "gradle",
            managerTitle: "Gradle",
            relativePath: ".gradle/caches",
            cleanupCommand: "rm -rf ~/.gradle/caches",
            cleanupDetail: "Removes Gradle's dependency and build caches. The next build re-downloads dependencies."
        ),
        Entry(
            id: "dev.maven",
            managerID: "maven",
            managerTitle: "Maven",
            relativePath: ".m2/repository",
            cleanupCommand: "rm -rf ~/.m2/repository",
            cleanupDetail: "Removes every artifact in the local Maven repository. The next build re-downloads them; keep this if you work offline."
        ),
        Entry(
            id: "dev.cocoapods",
            managerID: "cocoapods",
            managerTitle: "CocoaPods",
            relativePath: "Library/Caches/CocoaPods",
            cleanupCommand: "pod cache clean --all",
            cleanupDetail: "Removes CocoaPods' downloaded pod cache. The next pod install downloads pods again."
        ),
        Entry(
            id: "dev.swiftpm",
            managerID: "swiftpm",
            managerTitle: "Swift Package Manager",
            relativePath: "Library/Caches/org.swift.swiftpm",
            cleanupCommand: "rm -rf ~/Library/Caches/org.swift.swiftpm",
            cleanupDetail: "Removes SwiftPM's shared dependency cache. Xcode and Swift builds re-fetch packages."
        ),
        Entry(
            id: "dev.jetbrains.caches",
            managerID: "jetbrains",
            managerTitle: "JetBrains IDEs",
            relativePath: "Library/Caches/JetBrains",
            cleanupCommand: "rm -rf ~/Library/Caches/JetBrains/* ~/Library/Logs/JetBrains/*",
            cleanupDetail: "Removes IDE indexes, caches, and logs. Projects re-index on the next open."
        ),
        Entry(
            id: "dev.jetbrains.logs",
            managerID: "jetbrains",
            managerTitle: "JetBrains IDEs",
            relativePath: "Library/Logs/JetBrains",
            cleanupCommand: "rm -rf ~/Library/Caches/JetBrains/* ~/Library/Logs/JetBrains/*",
            cleanupDetail: "Removes IDE indexes, caches, and logs. Projects re-index on the next open."
        ),
        Entry(
            id: "dev.composer",
            managerID: "composer",
            managerTitle: "Composer",
            relativePath: "Library/Caches/composer",
            cleanupCommand: "composer clear-cache",
            cleanupDetail: "Removes Composer's package cache. The next install downloads packages again."
        ),
        Entry(
            id: "dev.conda.miniconda",
            managerID: "conda",
            managerTitle: "Conda",
            relativePath: "miniconda3/pkgs",
            cleanupCommand: "conda clean --all",
            cleanupDetail: "Removes downloaded and extracted Conda packages. Environments keep working."
        ),
        Entry(
            id: "dev.conda.anaconda",
            managerID: "conda",
            managerTitle: "Conda",
            relativePath: "anaconda3/pkgs",
            cleanupCommand: "conda clean --all",
            cleanupDetail: "Removes downloaded and extracted Conda packages. Environments keep working."
        ),
        Entry(
            id: "dev.conda.optanaconda",
            managerID: "conda",
            managerTitle: "Conda",
            relativePath: "opt/anaconda3/pkgs",
            cleanupCommand: "conda clean --all",
            cleanupDetail: "Removes downloaded and extracted Conda packages. Environments keep working."
        ),
        Entry(
            id: "dev.terraform",
            managerID: "terraform",
            managerTitle: "Terraform",
            relativePath: ".terraform.d/plugin-cache",
            cleanupCommand: "rm -rf ~/.terraform.d/plugin-cache/*",
            cleanupDetail: "Removes cached provider plugins. Terraform downloads them again when needed."
        ),
        Entry(
            id: "dev.pub",
            managerID: "dart",
            managerTitle: "Dart / Flutter",
            relativePath: ".pub-cache",
            cleanupCommand: "dart pub cache clean",
            cleanupDetail: "Removes the shared pub package cache. The next pub get downloads packages again."
        ),
        Entry(
            id: "dev.nuget",
            managerID: "nuget",
            managerTitle: "NuGet",
            relativePath: ".nuget/packages",
            cleanupCommand: "dotnet nuget locals all --clear",
            cleanupDetail: "Removes downloaded NuGet packages and HTTP caches. The next restore downloads them again."
        ),
        Entry(
            id: "dev.playwright",
            managerID: "playwright",
            managerTitle: "Playwright",
            relativePath: "Library/Caches/ms-playwright",
            cleanupCommand: "rm -rf ~/Library/Caches/ms-playwright",
            cleanupDetail: "Removes downloaded browser binaries. Playwright downloads them again on install or first run."
        ),
        Entry(
            id: "dev.cypress",
            managerID: "cypress",
            managerTitle: "Cypress",
            relativePath: "Library/Caches/Cypress",
            cleanupCommand: "cypress cache clear",
            cleanupDetail: "Removes the Cypress binary cache. The next install downloads the binary again."
        ),
        Entry(
            id: "dev.puppeteer",
            managerID: "puppeteer",
            managerTitle: "Puppeteer",
            relativePath: ".cache/puppeteer",
            cleanupCommand: "rm -rf ~/.cache/puppeteer ~/Library/Caches/puppeteer",
            cleanupDetail: "Removes downloaded browser binaries. Puppeteer downloads them again when needed."
        ),
        Entry(
            id: "dev.puppeteer.library",
            managerID: "puppeteer",
            managerTitle: "Puppeteer",
            relativePath: "Library/Caches/puppeteer",
            cleanupCommand: "rm -rf ~/.cache/puppeteer ~/Library/Caches/puppeteer",
            cleanupDetail: "Removes downloaded browser binaries. Puppeteer downloads them again when needed."
        ),
        Entry(
            id: "dev.electron",
            managerID: "electron",
            managerTitle: "Electron",
            relativePath: "Library/Caches/electron",
            cleanupCommand: "rm -rf ~/Library/Caches/electron",
            cleanupDetail: "Removes the Electron binary download cache. The next install downloads it again."
        ),
        Entry(
            id: "dev.deno",
            managerID: "deno",
            managerTitle: "Deno",
            relativePath: "Library/Caches/deno",
            cleanupCommand: "rm -rf ~/Library/Caches/deno ~/.cache/deno",
            cleanupDetail: "Removes Deno's module and build caches. The next run fetches dependencies again."
        ),
        Entry(
            id: "dev.deno.cache",
            managerID: "deno",
            managerTitle: "Deno",
            relativePath: ".cache/deno",
            cleanupCommand: "rm -rf ~/Library/Caches/deno ~/.cache/deno",
            cleanupDetail: "Removes Deno's module and build caches. The next run fetches dependencies again."
        ),
        Entry(
            id: "dev.huggingface",
            managerID: "huggingface",
            managerTitle: "Hugging Face",
            relativePath: ".cache/huggingface",
            cleanupCommand: "rm -rf ~/.cache/huggingface/*",
            cleanupDetail: "Removes downloaded models and datasets. They are re-downloaded when needed and can be large."
        ),
        Entry(
            id: "dev.torch",
            managerID: "torch",
            managerTitle: "PyTorch",
            relativePath: ".cache/torch",
            cleanupCommand: "rm -rf ~/.cache/torch/*",
            cleanupDetail: "Removes downloaded model weights and compiled extensions. They are rebuilt or re-downloaded."
        ),
        Entry(
            id: "dev.ivy",
            managerID: "ivy",
            managerTitle: "sbt / Ivy",
            relativePath: ".ivy2/cache",
            cleanupCommand: "rm -rf ~/.ivy2/cache",
            cleanupDetail: "Removes cached Ivy artifacts. The next sbt build re-resolves dependencies."
        )
    ]
}

public enum DevCacheFindingBuilder {
    public static func finding(sizes: [String: Int64]) -> Finding? {
        let measured = DevCacheCatalog.entries.compactMap { entry -> (DevCacheCatalog.Entry, Int64)? in
            guard let bytes = sizes[entry.id], bytes > 0 else { return nil }
            return (entry, bytes)
        }
        guard !measured.isEmpty else { return nil }

        let total = measured.reduce(Int64(0)) { $0 + $1.1 }
        guard let severity = ByteMath.severity(
            for: total,
            reportThreshold: DevCacheCatalog.reportThreshold,
            highThreshold: DevCacheCatalog.highThreshold,
            criticalThreshold: DevCacheCatalog.criticalThreshold
        ) else {
            return nil
        }

        struct ManagerTotal {
            var id: String
            var title: String
            var bytes: Int64
            var paths: [String]
            var command: String
            var detail: String
        }

        var managers: [String: ManagerTotal] = [:]
        for (entry, bytes) in measured {
            if var current = managers[entry.managerID] {
                current.bytes += bytes
                current.paths.append(entry.url.path)
                managers[entry.managerID] = current
            } else {
                managers[entry.managerID] = ManagerTotal(
                    id: entry.managerID,
                    title: entry.managerTitle,
                    bytes: bytes,
                    paths: [entry.url.path],
                    command: entry.cleanupCommand,
                    detail: entry.cleanupDetail
                )
            }
        }

        let ordered = managers.values.sorted { lhs, rhs in
            if lhs.bytes != rhs.bytes { return lhs.bytes > rhs.bytes }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }

        var metrics: [Metric] = [
            Metric(label: "Reclaimable", value: Format.bytes(total), isPrimary: true),
            Metric(label: "Package managers", value: "\(ordered.count)"),
            Metric(label: "Cache folders", value: "\(measured.count)")
        ]
        for manager in ordered.prefix(8) {
            metrics.append(Metric(label: manager.title, value: Format.bytes(manager.bytes)))
        }

        var steps: [RemediationStep] = [
            RemediationStep(
                title: "Review the cache locations",
                detail: "Caches are re-downloadable. Open the folders in the evidence to see which tools you still use before cleaning them.",
                kind: .manual
            )
        ]
        var seenCommands = Set<String>()
        for manager in ordered.prefix(6) where seenCommands.insert(manager.command).inserted {
            steps.append(RemediationStep(
                title: "Clean \(manager.title)",
                detail: manager.detail,
                command: manager.command,
                kind: .command
            ))
        }
        steps.append(RemediationStep(
            title: "Keep caches for tools you use offline",
            detail: "Maven, Gradle, Cargo, and Go caches are valuable when you work without a network. Clean only the caches you can re-download comfortably.",
            kind: .manual
        ))

        let managerNames = ordered.prefix(6).map(\.title).joined(separator: ", ")
        return Finding(
            id: "storage.dev-package-caches",
            category: .storage,
            title: "Developer package caches: \(Format.bytes(total))",
            summary: "\(ordered.count) developer package managers are holding \(Format.bytes(total)) in download caches. The caches are re-downloadable and are not needed after packages are installed.",
            detail: "Optimizr measured the download and build caches of \(managerNames). These folders make reinstalls fast, but they grow without being tied to a specific project. Cleaning them does not change installed projects; the next install or build may need network access and more time. Optimizr never deletes anything itself.",
            severity: severity,
            scope: .thirdParty,
            reclaimableBytes: total,
            metrics: metrics,
            remediation: steps,
            paths: Array(measured.sorted { $0.1 > $1.1 }.prefix(12).map { $0.0.url.path }),
            tags: ["developer", "caches", "package-managers"]
        )
    }
}
