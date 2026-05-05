import AutoresearchCore
import ArgumentParser
import Foundation

@main
struct AutoresearchCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autoresearch",
        abstract: "Run Swift-native autoresearch experiments.",
        subcommands: [Prepare.self, Train.self, Evaluate.self],
        defaultSubcommand: Train.self
    )
}

struct Prepare: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create train/validation text files in the cache."
    )

    @Option(help: "Required UTF-8 text file or directory of .txt files to prepare.")
    var input: String

    @Option(name: .customLong("cache-dir"), help: "Cache directory. Defaults to AUTORESEARCH_CACHE_DIR or ~/.cache/swift-autoresearch.")
    var cacheDirectory: String?

    @Option(name: .customLong("validation-fraction"), help: "Fraction of documents reserved for validation.")
    var validationFraction = 0.1

    mutating func run() throws {
        let paths = CachePaths(root: cacheDirectory.map(expandedFileURL) ?? CachePaths.defaultRoot())

        do {
            let summary = try DatasetPreparer().prepare(
                input: expandedFileURL(input),
                validationFraction: validationFraction,
                paths: paths
            )

            print("Cache directory: \(summary.cacheDirectory.path)")
            print("train_documents: \(summary.trainDocuments)")
            print("validation_documents: \(summary.validationDocuments)")
            print("train_bytes: \(summary.trainBytes)")
            print("validation_bytes: \(summary.validationBytes)")
            print("Done. Ready to train with `swift run autoresearch train`.")
        } catch let error as AutoresearchError {
            throw ValidationError(error.description)
        }
    }
}

struct Train: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run the fixed-time Swift autoresearch baseline."
    )

    @Option(name: .customLong("cache-dir"), help: "Cache directory. Defaults to AUTORESEARCH_CACHE_DIR or ~/.cache/swift-autoresearch.")
    var cacheDirectory: String?

    @Option(name: .customLong("backend"), help: "Training backend: bigram or mlx.")
    var backend: Backend = .bigram

    @Option(name: .customLong("time-budget"), help: "Training time budget in seconds.")
    var timeBudget: Double = 300

    @Option(name: .customLong("max-seq-len"), help: "Sequence length in tokens.")
    var maxSequenceLength = 2048

    @Option(name: .customLong("device-batch-size"), help: "Rows per training batch.")
    var deviceBatchSize = 128

    @Option(name: .customLong("total-batch-size"), help: "Tokens per optimizer step.")
    var totalBatchSize = 1 << 19

    @Option(name: .customLong("eval-tokens"), help: "Validation tokens to evaluate.")
    var evalTokens = 40 * 524_288

    @Option(name: .customLong("learning-rate"), help: "Optimizer learning rate. Defaults to 0.25 for bigram and 0.001 for MLX.")
    var learningRate: Double?

    @Option(name: .customLong("weight-decay"), help: "Optimizer weight decay.")
    var weightDecay = 0.0

    @Option(name: .customLong("mlx-layers"), help: "MLX transformer layer count.")
    var mlxLayerCount = 2

    @Option(name: .customLong("mlx-dim"), help: "MLX transformer model dimension.")
    var mlxModelDimension = 128

    @Option(name: .customLong("mlx-heads"), help: "MLX transformer attention head count.")
    var mlxHeadCount = 4

    @Option(name: .customLong("mlx-mlp-dim"), help: "MLX transformer MLP dimension.")
    var mlxMLPDimension = 512

    @Option(name: .customLong("mlx-device"), help: "MLX device: cpu or gpu.")
    var mlxDevice: MLXDevice = .cpu

    mutating func run() throws {
        let paths = CachePaths(root: cacheDirectory.map(expandedFileURL) ?? CachePaths.defaultRoot())
        let resolvedBackend = TrainingBackend(rawValue: backend.rawValue) ?? .bigram
        let config = TrainingConfig(
            backend: resolvedBackend,
            sequenceLength: maxSequenceLength,
            timeBudget: timeBudget,
            evalTokens: evalTokens,
            totalBatchSize: totalBatchSize,
            deviceBatchSize: deviceBatchSize,
            learningRate: learningRate ?? backend.defaultLearningRate,
            weightDecay: weightDecay,
            mlxModel: MLXModelConfig(
                layerCount: mlxLayerCount,
                modelDimension: mlxModelDimension,
                headCount: mlxHeadCount,
                mlpDimension: mlxMLPDimension
            ),
            mlxDevice: MLXDevicePreference(rawValue: mlxDevice.rawValue) ?? .cpu
        )

        do {
            if resolvedBackend == .mlx {
                try MLXMetallib.installIfNeeded()
            }
            _ = try AutoresearchTrainer(config: config, paths: paths).run()
        } catch let error as AutoresearchError {
            throw ValidationError(error.description)
        }
    }
}

struct Evaluate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a fixed evaluator from an immutable problem document."
    )

    @Option(help: "Markdown problem document with front matter.")
    var problem: String = "problem.md"

    @Option(help: "Short description for results.tsv.")
    var description: String = "evaluation"

    @Option(name: .customLong("log-file"), help: "Evaluator log path. Defaults to run.log next to the problem document.")
    var logFile: String?

    @Flag(name: .customLong("no-results"), help: "Do not append to the problem results TSV.")
    var noResults = false

    @Flag(name: .customLong("quiet"), help: "Do not stream evaluator output to the console.")
    var quiet = false

    mutating func run() throws {
        do {
            console("[1/4] loading problem: \(problem)")
            let problemURL = expandedFileURL(problem)
            let spec = try ProblemSpec.load(from: problemURL)
            let resolvedLogFile = logFile.map(expandedFileURL)
                ?? spec.root.appendingPathComponent("run.log")

            console("[2/4] cooking evaluator: \(spec.evaluator)")
            if !quiet {
                console("----- evaluator output -----")
            }
            let result = try ProblemEvaluator().evaluate(
                spec,
                logFile: resolvedLogFile,
                streamOutput: !quiet
            )
            if !quiet {
                console("\n----- end evaluator output -----")
            }

            let status: ExperimentStatus
            console("[3/4] scoring \(spec.metric)")
            if noResults {
                status = result.passed ? .keep : .crash
            } else {
                status = try ResultsLog(spec: spec)
                    .append(result: result, description: description)
                    .status
            }

            console("[4/4] recording result")
            console("problem: \(spec.name)")
            console("metric: \(spec.metric)")
            console("score: \(String(format: "%.6f", result.score ?? 0))")
            console("status: \(status.rawValue)")
            console("log: \(resolvedLogFile.path)")
            if !noResults {
                console("results: \(spec.resultsURL.path)")
            }
            if result.timedOut {
                console("timed_out: true")
            } else if result.exitCode != 0 {
                console("exit_code: \(result.exitCode)")
            }
        } catch let error as AutoresearchError {
            throw ValidationError(error.description)
        }
    }
}

private func expandedFileURL(_ path: String) -> URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
}

private func console(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}

enum Backend: String, ExpressibleByArgument {
    case bigram
    case mlx

    var defaultLearningRate: Double {
        switch self {
        case .bigram: 0.25
        case .mlx: 0.001
        }
    }
}

enum MLXDevice: String, ExpressibleByArgument {
    case cpu
    case gpu
}
