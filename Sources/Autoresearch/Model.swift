import Foundation

public struct SeededRandomNumberGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func uniform(in range: ClosedRange<Double>) -> Double {
        let value = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + (range.upperBound - range.lowerBound) * value
    }
}

public struct TargetCounter: Sendable {
    public private(set) var counts: [Int]
    public private(set) var totalTokens: Int
    public let vocabSize: Int

    public init(vocabSize: Int) {
        self.vocabSize = vocabSize
        self.counts = [Int](repeating: 0, count: vocabSize * vocabSize)
        self.totalTokens = 0
    }

    public mutating func add(_ batch: TokenBatch) {
        precondition(batch.inputs.count == batch.targets.count)

        for index in batch.inputs.indices {
            let input = batch.inputs[index]
            let target = batch.targets[index]
            counts[input * vocabSize + target] += 1
        }
        totalTokens += batch.inputs.count
    }
}

public final class AdamWOptimizer {
    private var firstMoment: [Double]
    private var secondMoment: [Double]
    private var stepCount = 0
    private let beta1: Double
    private let beta2: Double
    private let epsilon: Double

    public init(parameterCount: Int, beta1: Double = 0.9, beta2: Double = 0.95, epsilon: Double = 1e-8) {
        self.firstMoment = [Double](repeating: 0, count: parameterCount)
        self.secondMoment = [Double](repeating: 0, count: parameterCount)
        self.beta1 = beta1
        self.beta2 = beta2
        self.epsilon = epsilon
    }

    public func step(parameters: inout [Double], gradient: [Double], learningRate: Double, weightDecay: Double) {
        precondition(parameters.count == gradient.count)
        precondition(firstMoment.count == gradient.count)

        stepCount += 1
        let biasCorrection1 = 1.0 - pow(beta1, Double(stepCount))
        let biasCorrection2 = 1.0 - pow(beta2, Double(stepCount))

        for index in parameters.indices {
            if weightDecay != 0 {
                parameters[index] *= 1.0 - learningRate * weightDecay
            }

            let grad = gradient[index]
            firstMoment[index] = beta1 * firstMoment[index] + (1.0 - beta1) * grad
            secondMoment[index] = beta2 * secondMoment[index] + (1.0 - beta2) * grad * grad

            let correctedFirst = firstMoment[index] / biasCorrection1
            let correctedSecond = secondMoment[index] / biasCorrection2
            parameters[index] -= learningRate * correctedFirst / (sqrt(correctedSecond) + epsilon)
        }
    }
}

public final class BigramLanguageModel {
    public let vocabSize: Int
    private var logits: [Double]
    private var logProbabilities: [Double]
    private var isLogProbabilityCacheValid = false

    public var parameterCount: Int {
        logits.count
    }

    public init(vocabSize: Int, seed: UInt64 = 42) {
        self.vocabSize = vocabSize
        var rng = SeededRandomNumberGenerator(seed: seed)
        self.logits = (0..<(vocabSize * vocabSize)).map { _ in
            rng.uniform(in: -0.01...0.01)
        }
        self.logProbabilities = [Double](repeating: 0, count: vocabSize * vocabSize)
    }

    public func loss(on batch: TokenBatch) -> Double {
        ensureLogProbabilities()
        var total = 0.0
        for index in batch.inputs.indices {
            total -= logProbabilities[batch.inputs[index] * vocabSize + batch.targets[index]]
        }
        return total / Double(batch.inputs.count)
    }

    public func lossSumAndBytes(on batch: TokenBatch, tokenizer: any LanguageTokenizer) -> (nats: Double, bytes: Int) {
        ensureLogProbabilities()
        var nats = 0.0
        var bytes = 0

        for index in batch.inputs.indices {
            let target = batch.targets[index]
            let byteLength = tokenizer.byteLength(of: target)
            guard byteLength > 0 else { continue }
            nats -= logProbabilities[batch.inputs[index] * vocabSize + target]
            bytes += byteLength
        }

        return (nats, bytes)
    }

    public func update(
        targetCounter: TargetCounter,
        optimizer: AdamWOptimizer,
        learningRate: Double,
        weightDecay: Double
    ) {
        guard targetCounter.totalTokens > 0 else { return }
        precondition(targetCounter.vocabSize == vocabSize)

        var gradient = [Double](repeating: 0, count: logits.count)
        var exponentials = [Double](repeating: 0, count: vocabSize)
        let denominator = Double(targetCounter.totalTokens)

        for row in 0..<vocabSize {
            let rowStart = row * vocabSize
            var rowTargetCount = 0
            var maxLogit = -Double.infinity

            for column in 0..<vocabSize {
                let index = rowStart + column
                rowTargetCount += targetCounter.counts[index]
                maxLogit = max(maxLogit, logits[index])
            }

            guard rowTargetCount > 0 else { continue }

            var sumExp = 0.0
            for column in 0..<vocabSize {
                let value = exp(logits[rowStart + column] - maxLogit)
                exponentials[column] = value
                sumExp += value
            }

            let rowScale = Double(rowTargetCount)
            for column in 0..<vocabSize {
                let index = rowStart + column
                let probability = exponentials[column] / sumExp
                let count = Double(targetCounter.counts[index])
                gradient[index] = (rowScale * probability - count) / denominator
            }
        }

        optimizer.step(
            parameters: &logits,
            gradient: gradient,
            learningRate: learningRate,
            weightDecay: weightDecay
        )
        isLogProbabilityCacheValid = false
    }

    private func ensureLogProbabilities() {
        guard !isLogProbabilityCacheValid else { return }

        for row in 0..<vocabSize {
            let rowStart = row * vocabSize
            var maxLogit = -Double.infinity
            for column in 0..<vocabSize {
                maxLogit = max(maxLogit, logits[rowStart + column])
            }

            var sumExp = 0.0
            for column in 0..<vocabSize {
                sumExp += exp(logits[rowStart + column] - maxLogit)
            }

            let logNormalizer = maxLogit + log(sumExp)
            for column in 0..<vocabSize {
                let index = rowStart + column
                logProbabilities[index] = logits[index] - logNormalizer
            }
        }

        isLogProbabilityCacheValid = true
    }
}
