import Foundation

// MARK: - Command result

public struct CommandResult: Sendable, Hashable {
    public let executable: String
    public let arguments: [String]
    public let stdout: String
    public let stderr: String
    public let terminationStatus: Int32
    public let timedOut: Bool
    public let duration: TimeInterval

    public var succeeded: Bool { terminationStatus == 0 && !timedOut }
    public var output: String { stdout.trimmingCharacters(in: .whitespacesAndNewlines) }

    public static func failure(_ executable: String, _ arguments: [String], message: String) -> CommandResult {
        CommandResult(
            executable: executable,
            arguments: arguments,
            stdout: "",
            stderr: message,
            terminationStatus: -1,
            timedOut: false,
            duration: 0
        )
    }
}

// MARK: - Runner

/// Injection point for tests and for keeping scanners free of process plumbing.
public protocol CommandRunning: Sendable {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
}

public extension CommandRunning {
    func run(_ executable: String, arguments: [String]) -> CommandResult {
        run(executable, arguments: arguments, timeout: 10)
    }
}

/// Runs read-only system utilities without a shell.
///
/// No scanning command is ever passed through `/bin/sh`, which keeps user-controlled
/// paths out of a command language. Standard output and error are captured through
/// temporary files so a chatty process cannot fill a pipe and deadlock.
public struct ShellCommandRunner: CommandRunning {
    public let environment: [String: String]

    public init(environment: [String: String]? = nil) {
        var merged = ProcessInfo.processInfo.environment
        merged["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        merged["LANG"] = "en_US.UTF-8"
        merged["LC_ALL"] = "en_US.UTF-8"
        if let environment {
            merged.merge(environment) { _, new in new }
        }
        self.environment = merged
    }

    public func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        let fileManager = FileManager.default
        let token = UUID().uuidString
        let outURL = fileManager.temporaryDirectory.appendingPathComponent("optimizr-\(token).out")
        let errURL = fileManager.temporaryDirectory.appendingPathComponent("optimizr-\(token).err")

        guard fileManager.createFile(atPath: outURL.path, contents: nil),
              fileManager.createFile(atPath: errURL.path, contents: nil) else {
            return .failure(executable, arguments, message: "Could not create capture files")
        }

        defer {
            try? fileManager.removeItem(at: outURL)
            try? fileManager.removeItem(at: errURL)
        }

        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            return .failure(executable, arguments, message: "Could not open capture files")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle

        let started = Date()
        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            return .failure(executable, arguments, message: error.localizedDescription)
        }

        let deadline = started.addingTimeInterval(max(0.1, timeout))
        while process.isRunning && Date() < deadline {
            usleep(15_000)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            usleep(120_000)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()

        let stdout = (try? Data(contentsOf: outURL)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let stderr = (try? Data(contentsOf: errURL)).flatMap { String(data: $0, encoding: .utf8) } ?? ""

        return CommandResult(
            executable: executable,
            arguments: arguments,
            stdout: stdout,
            stderr: stderr,
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            duration: Date().timeIntervalSince(started)
        )
    }
}

// MARK: - Common paths

public enum Paths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    public static func home(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    public static func display(_ url: URL) -> String {
        let path = url.path
        let homePath = home.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") {
            return "~/" + String(path.dropFirst(homePath.count + 1))
        }
        return path
    }
}
