import XCTest
@testable import OptimizrCore

private struct FakeDevRunner: CommandRunning {
    let findOutput: String
    let sizes: [String: Int64]

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        if executable == "/usr/bin/find" {
            return result(executable, arguments, stdout: findOutput)
        }
        if executable == "/usr/bin/du", let path = arguments.last, let bytes = sizes[path] {
            return result(executable, arguments, stdout: "\(bytes / 1_024)\t\(path)\n")
        }
        return result(executable, arguments, stdout: "")
    }

    private func result(_ executable: String, _ arguments: [String], stdout: String) -> CommandResult {
        CommandResult(
            executable: executable,
            arguments: arguments,
            stdout: stdout,
            stderr: "",
            terminationStatus: 0,
            timedOut: false,
            duration: 0
        )
    }
}

final class DeveloperStorageTests: XCTestCase {
    private var temporaryRoots: [URL] = []

    override func tearDown() {
        for url in temporaryRoots {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    private func makeTemporaryHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("optimizr-dev-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }

    private func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func createFile(_ url: URL) throws {
        try Data().write(to: url)
    }

    // MARK: Classification

    func testClassifiesArtifactBasenames() {
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "node_modules"), [.nodeModules])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: ".next"), [.next])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "target"), [.rustTarget, .mavenTarget, .sbtTarget])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "bin"), [.dotnetBin])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "obj"), [.dotnetObj])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "build"), [.flutterBuild, .gradleBuild])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: "vendor"), [.goVendor, .composerVendor])
        XCTAssertEqual(DevArtifactKind.candidates(forBasename: ".build"), [.swiftPMBuild])
        XCTAssertTrue(DevArtifactKind.candidates(forBasename: "src").isEmpty)
    }

    func testValidatesAmbiguousArtifactFolders() throws {
        let project = try makeTemporaryHome().appendingPathComponent("project", isDirectory: true)
        let target = project.appendingPathComponent("target", isDirectory: true)
        let virtualenv = project.appendingPathComponent(".venv", isDirectory: true)
        let next = project.appendingPathComponent(".next", isDirectory: true)
        try createDirectory(target)
        try createDirectory(virtualenv)
        try createDirectory(next)

        XCTAssertFalse(DevArtifactKind.rustTarget.isValid(at: target))
        XCTAssertFalse(DevArtifactKind.pythonVirtualenv.isValid(at: virtualenv))
        XCTAssertFalse(DevArtifactKind.next.isValid(at: next))

        try createFile(project.appendingPathComponent("Cargo.toml"))
        try createFile(virtualenv.appendingPathComponent("pyvenv.cfg"))
        try createFile(project.appendingPathComponent("package.json"))

        XCTAssertTrue(DevArtifactKind.rustTarget.isValid(at: target))
        XCTAssertTrue(DevArtifactKind.pythonVirtualenv.isValid(at: virtualenv))
        XCTAssertTrue(DevArtifactKind.next.isValid(at: next))
        XCTAssertFalse(DevArtifactKind.mavenTarget.isValid(at: target))
    }

    func testValidatesEcosystemSpecificArtifactFolders() throws {
        let home = try makeTemporaryHome()
        let flutter = home.appendingPathComponent("flutter-app", isDirectory: true)
        let gradle = home.appendingPathComponent("gradle-app", isDirectory: true)
        let go = home.appendingPathComponent("go-app", isDirectory: true)
        let swift = home.appendingPathComponent("swift-app", isDirectory: true)

        try createDirectory(flutter.appendingPathComponent("build"))
        try createDirectory(gradle.appendingPathComponent("build"))
        try createDirectory(go.appendingPathComponent("vendor"))
        try createDirectory(swift.appendingPathComponent(".build"))

        try createFile(flutter.appendingPathComponent("pubspec.yaml"))
        try createFile(gradle.appendingPathComponent("build.gradle"))
        try createFile(go.appendingPathComponent("go.mod"))
        try createFile(swift.appendingPathComponent("Package.swift"))

        XCTAssertTrue(DevArtifactKind.flutterBuild.isValid(at: flutter.appendingPathComponent("build")))
        XCTAssertFalse(DevArtifactKind.gradleBuild.isValid(at: flutter.appendingPathComponent("build")))
        XCTAssertTrue(DevArtifactKind.gradleBuild.isValid(at: gradle.appendingPathComponent("build")))
        XCTAssertTrue(DevArtifactKind.goVendor.isValid(at: go.appendingPathComponent("vendor")))
        XCTAssertFalse(DevArtifactKind.composerVendor.isValid(at: go.appendingPathComponent("vendor")))
        XCTAssertTrue(DevArtifactKind.swiftPMBuild.isValid(at: swift.appendingPathComponent(".build")))

        let dotnet = home.appendingPathComponent("dotnet-app", isDirectory: true)
        try createDirectory(dotnet.appendingPathComponent("bin"))
        XCTAssertFalse(DevArtifactKind.dotnetBin.isValid(at: dotnet.appendingPathComponent("bin")))
        try createFile(dotnet.appendingPathComponent("App.csproj"))
        XCTAssertTrue(DevArtifactKind.dotnetBin.isValid(at: dotnet.appendingPathComponent("bin")))
    }

    func testFindArgumentsPruneMetadataAndArtifacts() {
        let roots = [URL(fileURLWithPath: "/Users/example/Developer")]
        let arguments = DevArtifactInventory.findArguments(roots: roots, maxDepth: 5)

        XCTAssertTrue(arguments.contains("/Users/example/Developer"))
        XCTAssertTrue(arguments.contains("-maxdepth"))
        XCTAssertTrue(arguments.contains("5"))
        XCTAssertTrue(arguments.contains(".git"))
        XCTAssertTrue(arguments.contains("node_modules"))
        XCTAssertTrue(arguments.contains(".venv"))
        XCTAssertTrue(arguments.contains("-prune"))
    }

    // MARK: Grouping

    func testResolvesHighLevelProjectRoots() throws {
        let home = try makeTemporaryHome()
        let developer = home.appendingPathComponent("Developer", isDirectory: true)
        let repo = developer.appendingPathComponent("repo", isDirectory: true)
        let monorepo = developer.appendingPathComponent("monorepo", isDirectory: true)
        let app = monorepo.appendingPathComponent("packages/app", isDirectory: true)

        try createDirectory(repo.appendingPathComponent(".git"))
        try createDirectory(monorepo.appendingPathComponent(".git"))
        try createDirectory(app)

        let simple = DevArtifactInventory.projectRoot(
            for: repo.appendingPathComponent("node_modules").path,
            roots: [developer],
            home: home
        )
        XCTAssertEqual(simple.path, repo.standardizedFileURL.path)
        XCTAssertFalse(simple.nested)

        let nested = DevArtifactInventory.projectRoot(
            for: app.appendingPathComponent("node_modules").path,
            roots: [developer],
            home: home
        )
        XCTAssertEqual(nested.path, monorepo.standardizedFileURL.path)
        XCTAssertTrue(nested.nested)
    }

    func testParsesFindOutputAndSkipsInvalidMatches() throws {
        let home = try makeTemporaryHome()
        let developer = home.appendingPathComponent("Developer", isDirectory: true)
        let repo = developer.appendingPathComponent("repo", isDirectory: true)
        let nodeModules = repo.appendingPathComponent("node_modules", isDirectory: true)
        let target = repo.appendingPathComponent("target", isDirectory: true)

        try createDirectory(repo.appendingPathComponent(".git"))
        try createDirectory(nodeModules)
        try createDirectory(target)

        let output = """
        \(nodeModules.path)
        \(target.path)
        /Users/example/Developer/repo/src
        """

        let artifacts = DevArtifactInventory.parse(output, roots: [developer], home: home)
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.kind, .nodeModules)
        XCTAssertEqual(artifacts.first?.projectPath, repo.standardizedFileURL.path)
        XCTAssertFalse(artifacts.first?.isNested ?? true)
    }

    func testSummaryGroupsNestedArtifactsByDefault() {
        let repository = "/Users/example/Developer/monorepo"
        let artifacts = [
            DevArtifact(
                path: repository + "/node_modules",
                kind: .nodeModules,
                bytes: 100,
                projectPath: repository,
                isNested: false
            ),
            DevArtifact(
                path: repository + "/packages/app/node_modules",
                kind: .nodeModules,
                bytes: 200,
                projectPath: repository,
                isNested: true
            ),
            DevArtifact(
                path: "/Users/example/Developer/other/node_modules",
                kind: .nodeModules,
                bytes: 100,
                projectPath: "/Users/example/Developer/other",
                isNested: false
            )
        ]

        let grouped = DevArtifactInventory.summarize(artifacts, includeNested: false)
        XCTAssertEqual(grouped.totalBytes, 400)
        XCTAssertEqual(grouped.artifactCount, 3)
        XCTAssertEqual(grouped.nestedCount, 1)
        XCTAssertEqual(grouped.projectCount, 2)
        XCTAssertEqual(grouped.rows.map(\.path), [repository, "/Users/example/Developer/other"])
        XCTAssertEqual(grouped.rows.map(\.bytes), [300, 100])

        let expanded = DevArtifactInventory.summarize(artifacts, includeNested: true)
        XCTAssertEqual(expanded.totalBytes, 400)
        XCTAssertEqual(expanded.rows.count, 3)
        XCTAssertEqual(expanded.rows.first?.path, repository + "/packages/app/node_modules")
        XCTAssertTrue(expanded.rows.first?.isNested ?? false)
    }

    func testScannerUsesEveryRelevantRootInCleanupCommands() throws {
        let home = try makeTemporaryHome()
        let developer = home.appendingPathComponent("Developer", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let developerModules = developer.appendingPathComponent("repo/node_modules", isDirectory: true)
        let desktopModules = desktop.appendingPathComponent("app/node_modules", isDirectory: true)

        try createDirectory(developerModules)
        try createDirectory(desktopModules)

        let size: Int64 = 300 * 1_024 * 1_024
        let runner = FakeDevRunner(
            findOutput: "\(developerModules.path)\n\(desktopModules.path)\n",
            sizes: [developerModules.path: size, desktopModules.path: size]
        )
        let findings = DevArtifactScanner(runner: runner, home: home).scan()
        let finding = try XCTUnwrap(findings.first { $0.id == "storage.dev-node-modules" })

        XCTAssertEqual(finding.reclaimableBytes, size * 2)
        XCTAssertTrue(finding.remediation.contains { $0.command?.contains(developer.path) == true })
        XCTAssertTrue(finding.remediation.contains { $0.command?.contains(desktop.path) == true })
        XCTAssertFalse(finding.remediation.contains { $0.command?.contains("'~/") == true })
    }

    func testBulkCleanupCommandsRunInZsh() throws {
        let home = try makeTemporaryHome()
        let developer = home.appendingPathComponent("Developer", isDirectory: true)
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let folders = [
            developer.appendingPathComponent("repo/node_modules", isDirectory: true),
            desktop.appendingPathComponent("app/node_modules", isDirectory: true)
        ]
        for folder in folders {
            try createDirectory(folder)
        }

        let size: Int64 = 300 * 1_024 * 1_024
        let runner = FakeDevRunner(
            findOutput: folders.map(\.path).joined(separator: "\n") + "\n",
            sizes: Dictionary(uniqueKeysWithValues: folders.map { ($0.path, size) })
        )
        let findings = DevArtifactScanner(runner: runner, home: home).scan()
        let finding = try XCTUnwrap(findings.first { $0.id == "storage.dev-node-modules" })
        let commands = finding.remediation.compactMap(\.command)

        XCTAssertTrue(commands.contains { $0.contains("\\( -name") }, commands.joined(separator: " ||| "))

        let preview = try XCTUnwrap(finding.remediation.first { $0.title == "Preview a bulk cleanup" }?.command)
        let result = runInZsh(preview)
        XCTAssertEqual(result.status, 0, "zsh rejected the command: \(result.stderr)")
        XCTAssertEqual(
            Set(result.stdout.split(separator: "\n").map(String.init)),
            Set(folders.map(\.path))
        )
    }

    private func runInZsh(_ command: String) -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try? process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    // MARK: Package caches

    func testPackageCacheFindingGroupsManagers() {
        let sizes = [
            "dev.npm.cacache": 400 * ByteMath.megabyte,
            "dev.pnpm.store.local": 300 * ByteMath.megabyte,
            "dev.pnpm.store.library": 100 * ByteMath.megabyte,
            "dev.pip": 200 * ByteMath.megabyte
        ]

        let finding = DevCacheFindingBuilder.finding(sizes: sizes)
        XCTAssertNotNil(finding)
        guard let finding else { return }

        XCTAssertEqual(finding.id, "storage.dev-package-caches")
        XCTAssertEqual(finding.category, .storage)
        XCTAssertEqual(finding.scope, .thirdParty)
        XCTAssertEqual(finding.reclaimableBytes, 1_000 * ByteMath.megabyte)
        XCTAssertEqual(finding.severity, .medium)
        XCTAssertTrue(finding.metrics.contains { $0.label == "npm" && $0.value == Format.bytes(400 * ByteMath.megabyte) })
        XCTAssertTrue(finding.metrics.contains { $0.label == "pnpm" && $0.value == Format.bytes(400 * ByteMath.megabyte) })
        XCTAssertTrue(finding.metrics.contains { $0.label == "pip" && $0.value == Format.bytes(200 * ByteMath.megabyte) })
        XCTAssertTrue(finding.remediation.contains { $0.command == "npm cache clean --force" })
        XCTAssertTrue(finding.remediation.contains { $0.command == "pip cache purge" })
    }

    func testPackageCacheFindingSkipsSmallTotals() {
        let sizes = ["dev.npm.cacache": 100 * ByteMath.megabyte]
        XCTAssertNil(DevCacheFindingBuilder.finding(sizes: sizes))
    }

    func testPackageCacheCatalogHasUniqueEntries() {
        let ids = DevCacheCatalog.entries.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertTrue(DevCacheCatalog.entries.allSatisfy { !$0.cleanupCommand.isEmpty })
    }
}
