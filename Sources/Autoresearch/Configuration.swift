import Foundation

public enum AutoresearchError: Error, CustomStringConvertible {
    case missingData(URL)
    case invalidConfiguration(String)
    case emptyCorpus
    case invalidEvaluation

    public var description: String {
        switch self {
        case .missingData(let url):
            return "Missing prepared data at \(url.path). Run `swift run autoresearch prepare --input <path>` first."
        case .invalidConfiguration(let message):
            return message
        case .emptyCorpus:
            return "The corpus did not contain any usable text."
        case .invalidEvaluation:
            return "Evaluation produced no byte targets."
        }
    }
}

public struct CachePaths: Sendable {
    public var root: URL

    public init(root: URL = CachePaths.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["AUTORESEARCH_CACHE_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: NSString(string: override).expandingTildeInPath)
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".cache/swift-autoresearch", isDirectory: true)
    }

    public var dataDirectory: URL {
        root.appendingPathComponent("data", isDirectory: true)
    }

    public var trainText: URL {
        dataDirectory.appendingPathComponent("train.txt")
    }

    public var validationText: URL {
        dataDirectory.appendingPathComponent("val.txt")
    }
}

public struct TrainingConfig: Sendable {
    public var backend: TrainingBackend
    public var sequenceLength: Int
    public var timeBudget: TimeInterval
    public var evalTokens: Int
    public var totalBatchSize: Int
    public var deviceBatchSize: Int
    public var learningRate: Double
    public var weightDecay: Double
    public var warmupRatio: Double
    public var warmdownRatio: Double
    public var finalLearningRateFraction: Double
    public var warmupStepsExcludedFromTiming: Int
    public var randomSeed: UInt64
    public var mlxModel: MLXModelConfig
    public var mlxDevice: MLXDevicePreference

    public init(
        backend: TrainingBackend = .bigram,
        sequenceLength: Int = 2048,
        timeBudget: TimeInterval = 300,
        evalTokens: Int = 40 * 524_288,
        totalBatchSize: Int = 1 << 19,
        deviceBatchSize: Int = 128,
        learningRate: Double = 0.25,
        weightDecay: Double = 0.0,
        warmupRatio: Double = 0.0,
        warmdownRatio: Double = 0.5,
        finalLearningRateFraction: Double = 0.0,
        warmupStepsExcludedFromTiming: Int = 10,
        randomSeed: UInt64 = 42,
        mlxModel: MLXModelConfig = MLXModelConfig(),
        mlxDevice: MLXDevicePreference = .cpu
    ) {
        self.backend = backend
        self.sequenceLength = sequenceLength
        self.timeBudget = timeBudget
        self.evalTokens = evalTokens
        self.totalBatchSize = totalBatchSize
        self.deviceBatchSize = deviceBatchSize
        self.learningRate = learningRate
        self.weightDecay = weightDecay
        self.warmupRatio = warmupRatio
        self.warmdownRatio = warmdownRatio
        self.finalLearningRateFraction = finalLearningRateFraction
        self.warmupStepsExcludedFromTiming = warmupStepsExcludedFromTiming
        self.randomSeed = randomSeed
        self.mlxModel = mlxModel
        self.mlxDevice = mlxDevice
    }

    public func validate() throws {
        guard sequenceLength > 0 else {
            throw AutoresearchError.invalidConfiguration("sequenceLength must be greater than zero.")
        }
        guard timeBudget > 0 else {
            throw AutoresearchError.invalidConfiguration("timeBudget must be greater than zero.")
        }
        guard evalTokens > 0 else {
            throw AutoresearchError.invalidConfiguration("evalTokens must be greater than zero.")
        }
        guard deviceBatchSize > 0 else {
            throw AutoresearchError.invalidConfiguration("deviceBatchSize must be greater than zero.")
        }
        guard totalBatchSize > 0 else {
            throw AutoresearchError.invalidConfiguration("totalBatchSize must be greater than zero.")
        }
        let tokensPerBatch = deviceBatchSize * sequenceLength
        guard totalBatchSize >= tokensPerBatch else {
            throw AutoresearchError.invalidConfiguration(
                "totalBatchSize must be at least deviceBatchSize * sequenceLength (\(tokensPerBatch))."
            )
        }
        guard totalBatchSize % tokensPerBatch == 0 else {
            throw AutoresearchError.invalidConfiguration(
                "totalBatchSize must be divisible by deviceBatchSize * sequenceLength (\(tokensPerBatch))."
            )
        }
        guard learningRate > 0 else {
            throw AutoresearchError.invalidConfiguration("learningRate must be greater than zero.")
        }
        guard weightDecay >= 0 else {
            throw AutoresearchError.invalidConfiguration("weightDecay must not be negative.")
        }
        guard warmupRatio >= 0, warmdownRatio >= 0, warmupRatio + warmdownRatio <= 1 else {
            throw AutoresearchError.invalidConfiguration("Warmup and warmdown ratios must be non-negative and sum to at most 1.")
        }
        guard finalLearningRateFraction >= 0 else {
            throw AutoresearchError.invalidConfiguration("finalLearningRateFraction must not be negative.")
        }
        guard warmupStepsExcludedFromTiming >= 0 else {
            throw AutoresearchError.invalidConfiguration("warmupStepsExcludedFromTiming must not be negative.")
        }
        try mlxModel.validate()
    }
}

public enum TrainingBackend: String, CaseIterable, Sendable {
    case bigram
    case mlx
}

public enum MLXDevicePreference: String, CaseIterable, Sendable {
    case cpu
    case gpu
}

public struct MLXModelConfig: Sendable {
    public var layerCount: Int
    public var modelDimension: Int
    public var headCount: Int
    public var mlpDimension: Int

    public init(
        layerCount: Int = 2,
        modelDimension: Int = 128,
        headCount: Int = 4,
        mlpDimension: Int = 512
    ) {
        self.layerCount = layerCount
        self.modelDimension = modelDimension
        self.headCount = headCount
        self.mlpDimension = mlpDimension
    }

    public func validate() throws {
        guard layerCount > 0 else {
            throw AutoresearchError.invalidConfiguration("MLX layer count must be greater than zero.")
        }
        guard modelDimension > 0 else {
            throw AutoresearchError.invalidConfiguration("MLX model dimension must be greater than zero.")
        }
        guard headCount > 0 else {
            throw AutoresearchError.invalidConfiguration("MLX head count must be greater than zero.")
        }
        guard modelDimension % headCount == 0 else {
            throw AutoresearchError.invalidConfiguration("MLX model dimension must be divisible by head count.")
        }
        guard mlpDimension > 0 else {
            throw AutoresearchError.invalidConfiguration("MLX MLP dimension must be greater than zero.")
        }
    }
}

public struct TrainingSummary: Sendable {
    public var validationBPB: Double
    public var trainingSeconds: TimeInterval
    public var totalSeconds: TimeInterval
    public var peakMemoryMB: Double
    public var mfuPercent: Double
    public var totalTokens: Int
    public var steps: Int
    public var parameterCount: Int
    public var depth: Int

    public var report: String {
        [
            "---",
            "val_bpb:          \(String(format: "%.6f", validationBPB))",
            "training_seconds: \(String(format: "%.1f", trainingSeconds))",
            "total_seconds:    \(String(format: "%.1f", totalSeconds))",
            "peak_vram_mb:     \(String(format: "%.1f", peakMemoryMB))",
            "mfu_percent:      \(String(format: "%.2f", mfuPercent))",
            "total_tokens_M:   \(String(format: "%.1f", Double(totalTokens) / 1_000_000.0))",
            "num_steps:        \(steps)",
            "num_params_M:     \(String(format: "%.1f", Double(parameterCount) / 1_000_000.0))",
            "depth:            \(depth)",
        ].joined(separator: "\n")
    }
}
