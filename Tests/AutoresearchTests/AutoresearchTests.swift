import Foundation
import Testing
@testable import AutoresearchCore

@Test func byteTokenizerRoundTripsUTF8() {
    let tokenizer = ByteTokenizer()
    let text = "Hello, Swift autoresearch."
    let ids = tokenizer.encode(text, prependBOS: true)

    #expect(ids.first == tokenizer.bosTokenID)
    #expect(tokenizer.decode(ids) == text)
    #expect(tokenizer.byteLength(of: tokenizer.bosTokenID) == 0)
    #expect(tokenizer.byteLength(of: Int(UInt8(ascii: "A"))) == 1)
}

@Test func packedLoaderProducesFullInputAndTargetRows() throws {
    let tokenizer = ByteTokenizer()
    let loader = try PackedBatchLoader(
        tokenizer: tokenizer,
        documents: ["alpha beta", "gamma delta", "epsilon"],
        batchSize: 3,
        sequenceLength: 8,
        bufferSize: 2
    )

    let batch = loader.next()
    #expect(batch.inputs.count == 24)
    #expect(batch.targets.count == 24)
    #expect(batch.epoch >= 1)
}

@Test func bigramUpdateImprovesBatchLoss() throws {
    let tokenizer = ByteTokenizer()
    let loader = try PackedBatchLoader(
        tokenizer: tokenizer,
        documents: Array(repeating: "aaaaaaaaaaaaaaaaaaaaaaaa", count: 8),
        batchSize: 4,
        sequenceLength: 12,
        bufferSize: 4
    )
    let batch = loader.next()
    let model = BigramLanguageModel(vocabSize: tokenizer.vocabSize, seed: 1)
    let optimizer = AdamWOptimizer(parameterCount: model.parameterCount)

    let before = model.loss(on: batch)
    var counter = TargetCounter(vocabSize: tokenizer.vocabSize)
    counter.add(batch)
    model.update(targetCounter: counter, optimizer: optimizer, learningRate: 0.2, weightDecay: 0)
    let after = model.loss(on: batch)

    #expect(after < before)
}

@Test func datasetPrepareCreatesTrainAndValidationFiles() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-autoresearch-tests-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let input = root.appendingPathComponent("corpus.txt")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try """
    alpha beta gamma

    delta epsilon zeta

    eta theta iota

    kappa lambda mu
    """.write(to: input, atomically: true, encoding: .utf8)

    let paths = CachePaths(root: root)
    let summary = try DatasetPreparer().prepare(input: input, paths: paths)

    #expect(summary.trainDocuments > 0)
    #expect(summary.validationDocuments > 0)
    #expect(FileManager.default.fileExists(atPath: paths.trainText.path))
    #expect(FileManager.default.fileExists(atPath: paths.validationText.path))
}

@Test func learningRateScheduleWarmsDown() {
    let config = TrainingConfig(
        timeBudget: 10,
        totalBatchSize: 16,
        deviceBatchSize: 1,
        warmdownRatio: 0.5,
        finalLearningRateFraction: 0.0
    )
    let trainer = AutoresearchTrainer(config: config)

    #expect(trainer.learningRateMultiplier(progress: 0.25) == 1.0)
    #expect(trainer.learningRateMultiplier(progress: 1.0) == 0.0)
    #expect(abs(trainer.learningRateMultiplier(progress: 0.75) - 0.5) < 1e-9)
}

@Test func problemEvaluatorParsesFrontMatterAndMetricOutput() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("swift-autoresearch-problem-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let problem = root.appendingPathComponent("problem.md")
    try """
    ---
    name: sample
    metric: p50_ms
    direction: minimize
    evaluator: |
      printf -- '---\\np50_ms: 12.500\\npeak_vram_mb: 1024\\n'
    timeout_seconds: 5
    results: results.tsv
    mutable:
      - Sources/App
      - Benchmarks
    ---

    # Sample Problem
    """.write(to: problem, atomically: true, encoding: .utf8)

    let spec = try ProblemSpec.load(from: problem)
    let result = try ProblemEvaluator().evaluate(spec)
    let record = try ResultsLog(spec: spec).append(result: result, description: "baseline")

    #expect(spec.name == "sample")
    #expect(spec.metric == "p50_ms")
    #expect(spec.mutablePaths == ["Sources/App", "Benchmarks"])
    #expect(result.passed)
    #expect(result.score == 12.5)
    #expect(abs(result.peakMemoryGB - 1.0) < 1e-9)
    #expect(record.status == .keep)
    #expect(FileManager.default.fileExists(atPath: spec.resultsURL.path))
}
