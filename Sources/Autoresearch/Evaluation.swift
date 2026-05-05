import Dispatch
import Foundation
import Yams

public enum ObjectiveDirection: String, Codable, Sendable {
    case minimize
    case maximize
}

public struct ProblemSpec: Sendable {
    public var url: URL
    public var root: URL
    public var name: String
    public var metric: String
    public var direction: ObjectiveDirection
    public var evaluator: String
    public var timeoutSeconds: TimeInterval
    public var resultsPath: String
    public var mutablePaths: [String]

    public var resultsURL: URL {
        root.appendingPathComponent(resultsPath)
    }

    public static func load(from url: URL) throws -> ProblemSpec {
        let text = try String(contentsOf: url, encoding: .utf8)
        let metadata = try ProblemFrontMatter.decode(from: extractFrontMatter(from: text))
        let root = url.deletingLastPathComponent()
        if metadata.timeoutSeconds <= 0 {
            throw AutoresearchError.invalidConfiguration("timeout_seconds must be a positive number.")
        }
        if metadata.metric.isEmpty {
            throw AutoresearchError.invalidConfiguration("Problem document is missing required front matter key: metric")
        }
        if metadata.evaluator.isEmpty {
            throw AutoresearchError.invalidConfiguration("Problem document is missing required front matter key: evaluator")
        }

        let resultsPath: String
        if let results = metadata.results, !results.isEmpty {
            resultsPath = results
        } else {
            resultsPath = "results.tsv"
        }

        return ProblemSpec(
            url: url,
            root: root,
            name: metadata.name ?? url.deletingPathExtension().lastPathComponent,
            metric: metadata.metric,
            direction: metadata.direction,
            evaluator: metadata.evaluator,
            timeoutSeconds: metadata.timeoutSeconds,
            resultsPath: resultsPath,
            mutablePaths: metadata.mutable
        )
    }

    private static func extractFrontMatter(from text: String) throws -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let first = lines.popFirst(),
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            throw AutoresearchError.invalidConfiguration("Problem document must start with front matter delimited by --- lines.")
        }

        var yamlLines: [Substring] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                return yamlLines.joined(separator: "\n")
            }
            yamlLines.append(line)
        }

        throw AutoresearchError.invalidConfiguration("Problem document front matter is missing its closing --- delimiter.")
    }
}

private struct ProblemFrontMatter: Decodable {
    var name: String?
    var metric: String
    var direction: ObjectiveDirection
    var evaluator: String
    var timeoutSeconds: TimeInterval
    var results: String?
    var mutable: [String]

    enum CodingKeys: String, CodingKey {
        case name
        case metric
        case direction
        case evaluator
        case timeoutSeconds = "timeout_seconds"
        case timeout
        case results
        case mutable
        case mutablePaths = "mutable_paths"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        metric = try container.decode(String.self, forKey: .metric)
        direction = try container.decodeIfPresent(ObjectiveDirection.self, forKey: .direction) ?? .minimize
        evaluator = try container.decode(String.self, forKey: .evaluator)
        timeoutSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutSeconds)
            ?? container.decodeIfPresent(TimeInterval.self, forKey: .timeout)
            ?? 600
        results = try container.decodeIfPresent(String.self, forKey: .results)
        mutable = try container.decodeIfPresent([String].self, forKey: .mutable)
            ?? container.decodeIfPresent([String].self, forKey: .mutablePaths)
            ?? []
    }

    static func decode(from yaml: String) throws -> ProblemFrontMatter {
        do {
            return try YAMLDecoder().decode(ProblemFrontMatter.self, from: yaml)
        } catch {
            throw AutoresearchError.invalidConfiguration("Invalid problem document YAML front matter: \(error)")
        }
    }
}

public struct EvaluationResult: Sendable {
    public var passed: Bool
    public var timedOut: Bool
    public var exitCode: Int32
    public var score: Double?
    public var metric: String
    public var fields: [String: String]
    public var stdout: String
    public var stderr: String

    public var peakMemoryGB: Double {
        let memoryKeys = ["peak_vram_mb", "peak_memory_mb", "memory_mb"]
        for key in memoryKeys {
            if let value = fields[key].flatMap(Self.firstDouble) {
                return value / 1024.0
            }
        }
        return 0
    }

    public static func firstDouble(in text: String) -> Double? {
        text.split(whereSeparator: { $0.isWhitespace }).first.flatMap { Double($0) }
    }
}

public struct ProblemEvaluator {
    public init() {}

    public func evaluate(
        _ spec: ProblemSpec,
        logFile: URL? = nil,
        streamOutput: Bool = false
    ) throws -> EvaluationResult {
        let command = spec.evaluator
        let completed = try runShell(
            command,
            workingDirectory: spec.root,
            timeoutSeconds: spec.timeoutSeconds,
            streamOutput: streamOutput,
            environment: [
                "AUTORESEARCH_PROBLEM": spec.url.path,
                "AUTORESEARCH_PROBLEM_ROOT": spec.root.path,
                "AUTORESEARCH_METRIC": spec.metric,
            ]
        )

        let fields = Self.parseFields(completed.stdout + "\n" + completed.stderr)
        let score = fields[spec.metric].flatMap(EvaluationResult.firstDouble)
            ?? fields["score"].flatMap(EvaluationResult.firstDouble)
        let passed = completed.exitCode == 0 && !completed.timedOut && score != nil
        let result = EvaluationResult(
            passed: passed,
            timedOut: completed.timedOut,
            exitCode: completed.exitCode,
            score: score,
            metric: spec.metric,
            fields: fields,
            stdout: completed.stdout,
            stderr: completed.stderr
        )

        if let logFile {
            try writeLog(command: command, result: result, to: logFile)
        }

        return result
    }

    public static func parseFields(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "---" {
                continue
            }
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            let key = String(parts[0])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
            let value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        return fields
    }

    private func writeLog(command: String, result: EvaluationResult, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let contents = [
            "$ \(command)",
            "",
            "--- stdout ---",
            result.stdout,
            "",
            "--- stderr ---",
            result.stderr,
        ].joined(separator: "\n")
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func runShell(
        _ command: String,
        workingDirectory: URL,
        timeoutSeconds: TimeInterval,
        streamOutput: Bool,
        environment: [String: String]
    ) throws -> ShellResult {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdoutCapture = StreamCapture(forwardTo: streamOutput ? FileHandle.standardOutput : nil)
        let stderrCapture = StreamCapture(forwardTo: streamOutput ? FileHandle.standardError : nil)
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutCapture.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrCapture.append(handle.availableData)
        }

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        try process.run()
        var timedOut = false
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            timedOut = true
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 5)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutCapture.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
        stderrCapture.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())

        return ShellResult(
            stdout: stdoutCapture.string(),
            stderr: stderrCapture.string(),
            exitCode: timedOut ? -1 : process.terminationStatus,
            timedOut: timedOut
        )
    }
}

private final class StreamCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let target: FileHandle?

    init(forwardTo target: FileHandle?) {
        self.target = target
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        data.append(chunk)
        lock.unlock()
        target?.write(chunk)
    }

    func string() -> String {
        lock.lock()
        let captured = data
        lock.unlock()
        return String(decoding: captured, as: UTF8.self)
    }
}

public enum ExperimentStatus: String, Sendable {
    case keep
    case discard
    case crash
}

public struct ExperimentRecord: Sendable {
    public var commit: String
    public var score: Double
    public var memoryGB: Double
    public var status: ExperimentStatus
    public var description: String
}

public struct ResultsLog {
    public var spec: ProblemSpec

    public init(spec: ProblemSpec) {
        self.spec = spec
    }

    public func append(result: EvaluationResult, description: String) throws -> ExperimentRecord {
        let previousBest = try bestScore()
        let status = status(for: result, previousBest: previousBest)
        let record = ExperimentRecord(
            commit: Self.currentCommit(workingDirectory: spec.root),
            score: result.score ?? 0,
            memoryGB: result.peakMemoryGB,
            status: status,
            description: description
        )

        try ensureHeader()
        let line = [
            record.commit,
            String(format: "%.6f", record.score),
            String(format: "%.1f", record.memoryGB),
            record.status.rawValue,
            sanitizeTSV(record.description),
        ].joined(separator: "\t") + "\n"
        let handle = try FileHandle(forWritingTo: spec.resultsURL)
        defer {
            try? handle.close()
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(line.utf8))
        return record
    }

    private func status(for result: EvaluationResult, previousBest: Double?) -> ExperimentStatus {
        guard result.passed, let score = result.score else {
            return .crash
        }
        guard let previousBest else {
            return .keep
        }
        switch spec.direction {
        case .minimize:
            return score < previousBest ? .keep : .discard
        case .maximize:
            return score > previousBest ? .keep : .discard
        }
    }

    private func bestScore() throws -> Double? {
        guard FileManager.default.fileExists(atPath: spec.resultsURL.path) else {
            return nil
        }
        let text = try String(contentsOf: spec.resultsURL, encoding: .utf8)
        var best: Double?
        for line in text.components(separatedBy: .newlines).dropFirst() where !line.isEmpty {
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 4, columns[3] == ExperimentStatus.keep.rawValue,
                  let score = Double(columns[1]) else {
                continue
            }
            if let current = best {
                switch spec.direction {
                case .minimize where score < current:
                    best = score
                case .maximize where score > current:
                    best = score
                default:
                    break
                }
            } else {
                best = score
            }
        }
        return best
    }

    private func ensureHeader() throws {
        if FileManager.default.fileExists(atPath: spec.resultsURL.path) {
            return
        }
        try FileManager.default.createDirectory(
            at: spec.resultsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let header = ["commit", spec.metric, "memory_gb", "status", "description"].joined(separator: "\t") + "\n"
        try header.write(to: spec.resultsURL, atomically: true, encoding: .utf8)
    }

    private func sanitizeTSV(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func currentCommit(workingDirectory: URL) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--short", "HEAD"]
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return "unknown"
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "unknown"
        }
    }
}

private struct ShellResult {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var timedOut: Bool
}
