import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct AutoresearchTrainer {
    public var config: TrainingConfig
    public var paths: CachePaths

    public init(config: TrainingConfig = TrainingConfig(), paths: CachePaths = CachePaths()) {
        self.config = config
        self.paths = paths
    }

    public func run(
        log: (String) -> Void = { print($0) },
        progressLog: (String) -> Void = { message in
            print(message, terminator: "")
            fflush(stdout)
        }
    ) throws -> TrainingSummary {
        try config.validate()

        if config.backend == .mlx {
            return try MLXAutoresearchTrainer(config: config, paths: paths).run(
                log: log,
                progressLog: progressLog
            )
        }

        let totalStart = Date()
        let tokenizer = ByteTokenizer()
        let corpus = try TextCorpus.load(paths: paths)
        let model = BigramLanguageModel(vocabSize: tokenizer.vocabSize, seed: config.randomSeed)
        let optimizer = AdamWOptimizer(parameterCount: model.parameterCount)

        log("Vocab size: \(tokenizer.vocabSize)")
        log("Model config: byte-level bigram")
        log("Parameter counts:")
        log("  transition_logits       : \(model.parameterCount)")
        log("Estimated FLOPs per token: n/a")

        let tokensPerForwardBackward = config.deviceBatchSize * config.sequenceLength
        let gradientAccumulationSteps = config.totalBatchSize / tokensPerForwardBackward

        let trainLoader = try PackedBatchLoader(
            tokenizer: tokenizer,
            documents: corpus.trainDocuments,
            batchSize: config.deviceBatchSize,
            sequenceLength: config.sequenceLength
        )

        log("Time budget: \(String(format: "%.1f", config.timeBudget))s")
        log("Gradient accumulation steps: \(gradientAccumulationSteps)")

        var totalTrainingTime: TimeInterval = 0
        var smoothTrainLoss = 0.0
        var step = 0
        var epoch = 1

        while true {
            let stepStart = Date()
            var targetCounter = TargetCounter(vocabSize: tokenizer.vocabSize)
            var trainLoss = 0.0

            for _ in 0..<gradientAccumulationSteps {
                let batch = trainLoader.next()
                trainLoss = model.loss(on: batch)
                targetCounter.add(batch)
                epoch = batch.epoch
            }

            let progress = min(totalTrainingTime / config.timeBudget, 1.0)
            let learningRateMultiplier = learningRateMultiplier(progress: progress)
            let learningRate = config.learningRate * learningRateMultiplier
            let weightDecay = config.weightDecay * (1.0 - progress)

            model.update(
                targetCounter: targetCounter,
                optimizer: optimizer,
                learningRate: learningRate,
                weightDecay: weightDecay
            )

            guard trainLoss.isFinite, trainLoss <= 100 else {
                throw AutoresearchError.invalidConfiguration("Training failed: loss became \(trainLoss).")
            }

            let elapsed = Date().timeIntervalSince(stepStart)
            if step > config.warmupStepsExcludedFromTiming {
                totalTrainingTime += elapsed
            }

            let emaBeta = 0.9
            smoothTrainLoss = emaBeta * smoothTrainLoss + (1.0 - emaBeta) * trainLoss
            let debiasedLoss = smoothTrainLoss / (1.0 - pow(emaBeta, Double(step + 1)))
            let percentDone = 100.0 * progress
            let tokensPerSecond = Int(Double(config.totalBatchSize) / max(elapsed, 1e-9))
            let remaining = max(0.0, config.timeBudget - totalTrainingTime)

            progressLog(
                "\rstep \(String(format: "%05d", step)) (\(String(format: "%.1f", percentDone))%) | " +
                "loss: \(String(format: "%.6f", debiasedLoss)) | " +
                "lrm: \(String(format: "%.2f", learningRateMultiplier)) | " +
                "dt: \(String(format: "%.0f", elapsed * 1000))ms | " +
                "tok/sec: \(tokensPerSecond) | " +
                "mfu: 0.0% | epoch: \(epoch) | remaining: \(String(format: "%.0f", remaining))s    "
            )

            step += 1

            if step > config.warmupStepsExcludedFromTiming, totalTrainingTime >= config.timeBudget {
                break
            }
        }

        log("")

        let validationBPB = try Self.evaluateBPB(
            model: model,
            tokenizer: tokenizer,
            documents: corpus.validationDocuments,
            batchSize: config.deviceBatchSize,
            sequenceLength: config.sequenceLength,
            evalTokens: config.evalTokens
        )

        let totalEnd = Date()
        let summary = TrainingSummary(
            validationBPB: validationBPB,
            trainingSeconds: totalTrainingTime,
            totalSeconds: totalEnd.timeIntervalSince(totalStart),
            peakMemoryMB: currentPeakResidentMB(),
            mfuPercent: 0,
            totalTokens: step * config.totalBatchSize,
            steps: step,
            parameterCount: model.parameterCount,
            depth: 1
        )

        log(summary.report)
        return summary
    }

    public func learningRateMultiplier(progress: Double) -> Double {
        if progress < config.warmupRatio {
            return config.warmupRatio > 0 ? progress / config.warmupRatio : 1.0
        } else if progress < 1.0 - config.warmdownRatio {
            return 1.0
        } else {
            let cooldown = config.warmdownRatio > 0 ? (1.0 - progress) / config.warmdownRatio : 0.0
            return cooldown + (1.0 - cooldown) * config.finalLearningRateFraction
        }
    }

    public static func evaluateBPB(
        model: BigramLanguageModel,
        tokenizer: ByteTokenizer,
        documents: [String],
        batchSize: Int,
        sequenceLength: Int,
        evalTokens: Int
    ) throws -> Double {
        let validationLoader = try PackedBatchLoader(
            tokenizer: tokenizer,
            documents: documents,
            batchSize: batchSize,
            sequenceLength: sequenceLength
        )

        let steps = max(1, evalTokens / max(1, batchSize * sequenceLength))
        var totalNats = 0.0
        var totalBytes = 0

        for _ in 0..<steps {
            let batch = validationLoader.next()
            let result = model.lossSumAndBytes(on: batch, tokenizer: tokenizer)
            totalNats += result.nats
            totalBytes += result.bytes
        }

        guard totalBytes > 0 else {
            throw AutoresearchError.invalidEvaluation
        }

        return totalNats / (log(2.0) * Double(totalBytes))
    }

    private func currentPeakResidentMB() -> Double {
        #if canImport(Darwin) || canImport(Glibc)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        #if canImport(Darwin)
        return Double(usage.ru_maxrss) / 1024.0 / 1024.0
        #else
        return Double(usage.ru_maxrss) / 1024.0
        #endif
        #else
        return 0
        #endif
    }
}
