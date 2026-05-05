import Foundation
import MLX
import MLXNN
import MLXOptimizers
import MLXRandom

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class MLXAutoresearchBlock: Module {
    let norm1: RMSNorm
    let attention: MultiHeadAttention
    let norm2: RMSNorm
    let mlpIn: Linear
    let mlpOut: Linear

    init(modelDimension: Int, headCount: Int, mlpDimension: Int) {
        self.norm1 = RMSNorm(dimensions: modelDimension)
        self.attention = MultiHeadAttention(dimensions: modelDimension, numHeads: headCount)
        self.norm2 = RMSNorm(dimensions: modelDimension)
        self.mlpIn = Linear(modelDimension, mlpDimension, bias: false)
        self.mlpOut = Linear(mlpDimension, modelDimension, bias: false)
        super.init()
    }

    func callAsFunction(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        var y = norm1(x)
        y = attention(y, keys: y, values: y, mask: mask)
        var x = x + y

        y = norm2(x)
        y = relu(mlpIn(y)).square()
        y = mlpOut(y)
        x = x + y

        return x
    }
}

final class MLXAutoresearchModel: Module {
    let tokenEmbedding: Embedding
    let positionEmbedding: Embedding
    let blocks: [MLXAutoresearchBlock]
    let norm: RMSNorm
    let head: Linear
    let config: MLXModelConfig
    let vocabSize: Int
    let sequenceLength: Int

    init(vocabSize: Int, sequenceLength: Int, config: MLXModelConfig) {
        self.vocabSize = vocabSize
        self.sequenceLength = sequenceLength
        self.config = config
        self.tokenEmbedding = Embedding(embeddingCount: vocabSize, dimensions: config.modelDimension)
        self.positionEmbedding = Embedding(embeddingCount: sequenceLength, dimensions: config.modelDimension)
        self.blocks = (0..<config.layerCount).map { _ in
            MLXAutoresearchBlock(
                modelDimension: config.modelDimension,
                headCount: config.headCount,
                mlpDimension: config.mlpDimension
            )
        }
        self.norm = RMSNorm(dimensions: config.modelDimension)
        self.head = Linear(config.modelDimension, vocabSize, bias: false)
        super.init()
    }

    var parameterCount: Int {
        parameters().flattened().reduce(0) { count, item in
            count + item.1.size
        }
    }

    func callAsFunction(_ tokens: MLXArray) -> MLXArray {
        let tokenCount = tokens.dim(1)
        precondition(tokenCount <= sequenceLength)

        let positions = MLXArray(0..<tokenCount).expandedDimensions(axis: 0)
        var x = tokenEmbedding(tokens) + positionEmbedding(positions)
        let mask = MultiHeadAttention.createAdditiveCausalMask(tokenCount, dtype: .float32)

        for block in blocks {
            x = block(x, mask: mask)
        }

        return head(norm(x))
    }
}

struct MLXAutoresearchTrainer {
    var config: TrainingConfig
    var paths: CachePaths

    func run(
        log: (String) -> Void,
        progressLog: (String) -> Void
    ) throws -> TrainingSummary {
        let device: Device = config.mlxDevice == .gpu ? .gpu : .cpu
        return try Device.withDefaultDevice(device) {
            try runOnCurrentDevice(log: log, progressLog: progressLog)
        }
    }

    private func runOnCurrentDevice(
        log: (String) -> Void,
        progressLog: (String) -> Void
    ) throws -> TrainingSummary {
        let totalStart = Date()
        let tokenizer = ByteTokenizer()
        let corpus = try TextCorpus.load(paths: paths)

        MLXRandom.seed(config.randomSeed)
        let model = MLXAutoresearchModel(
            vocabSize: tokenizer.vocabSize,
            sequenceLength: config.sequenceLength,
            config: config.mlxModel
        )
        eval(model)

        let optimizer = AdamW(
            learningRate: Float(config.learningRate),
            betas: (0.9, 0.95),
            weightDecay: Float(config.weightDecay)
        )

        log("Vocab size: \(tokenizer.vocabSize)")
        log(
            "Model config: MLX causal transformer " +
            "layers=\(config.mlxModel.layerCount) " +
            "dim=\(config.mlxModel.modelDimension) " +
            "heads=\(config.mlxModel.headCount) " +
            "mlp_dim=\(config.mlxModel.mlpDimension) " +
            "device=\(config.mlxDevice.rawValue)"
        )
        log("Parameter counts:")
        log("  mlx_transformer         : \(model.parameterCount)")
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

        func loss(model: MLXAutoresearchModel, inputs: MLXArray, targets: MLXArray) -> MLXArray {
            let logits = model(inputs).reshaped(-1, tokenizer.vocabSize)
            let targets = targets.reshaped(-1)
            return crossEntropy(logits: logits, targets: targets, reduction: .mean)
        }

        let lossAndGrad = valueAndGrad(model: model, loss)

        var totalTrainingTime: TimeInterval = 0
        var smoothTrainLoss = 0.0
        var step = 0
        var epoch = 1

        while true {
            let stepStart = Date()
            var trainLoss = 0.0

            let progress = min(totalTrainingTime / config.timeBudget, 1.0)
            let learningRateMultiplier = learningRateMultiplier(progress: progress)
            optimizer.learningRate = Float(config.learningRate * learningRateMultiplier)
            optimizer.weightDecay = Float(config.weightDecay * (1.0 - progress))

            for _ in 0..<gradientAccumulationSteps {
                let batch = trainLoader.next()
                epoch = batch.epoch
                let inputs = mlxArray(batch.inputs, batchSize: config.deviceBatchSize, sequenceLength: config.sequenceLength)
                let targets = mlxArray(batch.targets, batchSize: config.deviceBatchSize, sequenceLength: config.sequenceLength)

                let (loss, gradients) = lossAndGrad(model, inputs, targets)
                optimizer.update(model: model, gradients: gradients)
                eval(model, optimizer)
                trainLoss = Double(loss.item(Float.self))
            }

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

        let validationBPB = try evaluateBPB(
            model: model,
            tokenizer: tokenizer,
            documents: corpus.validationDocuments
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
            depth: config.mlxModel.layerCount
        )

        log(summary.report)
        return summary
    }

    private func evaluateBPB(
        model: MLXAutoresearchModel,
        tokenizer: ByteTokenizer,
        documents: [String]
    ) throws -> Double {
        let validationLoader = try PackedBatchLoader(
            tokenizer: tokenizer,
            documents: documents,
            batchSize: config.deviceBatchSize,
            sequenceLength: config.sequenceLength
        )

        let steps = max(1, config.evalTokens / max(1, config.deviceBatchSize * config.sequenceLength))
        var totalNats = 0.0
        var totalBytes = 0.0

        for _ in 0..<steps {
            let batch = validationLoader.next()
            let inputs = mlxArray(batch.inputs, batchSize: config.deviceBatchSize, sequenceLength: config.sequenceLength)
            let targets = mlxArray(batch.targets, batchSize: config.deviceBatchSize, sequenceLength: config.sequenceLength)
            let flatTargets = targets.reshaped(-1)
            let logits = model(inputs).reshaped(-1, tokenizer.vocabSize)
            let loss = crossEntropy(logits: logits, targets: flatTargets, reduction: .none)
            let mask = (flatTargets .!= tokenizer.bosTokenID).asType(.float32)

            totalNats += Double((loss * mask).sum().item(Float.self))
            totalBytes += Double(mask.sum().item(Float.self))
        }

        guard totalBytes > 0 else {
            throw AutoresearchError.invalidEvaluation
        }

        return totalNats / (log(2.0) * totalBytes)
    }

    private func learningRateMultiplier(progress: Double) -> Double {
        if progress < config.warmupRatio {
            return config.warmupRatio > 0 ? progress / config.warmupRatio : 1.0
        } else if progress < 1.0 - config.warmdownRatio {
            return 1.0
        } else {
            let cooldown = config.warmdownRatio > 0 ? (1.0 - progress) / config.warmdownRatio : 0.0
            return cooldown + (1.0 - cooldown) * config.finalLearningRateFraction
        }
    }

    private func mlxArray(_ values: [Int], batchSize: Int, sequenceLength: Int) -> MLXArray {
        MLXArray(values, [batchSize, sequenceLength])
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
