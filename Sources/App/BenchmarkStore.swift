import SwiftUI
import os

private let performanceLog = OSLog(subsystem: "com.dd.performancelab", category: .pointsOfInterest)

@MainActor
final class BenchmarkStore: ObservableObject {
    @Published private(set) var runs: [BenchmarkRun] = []
    @Published private(set) var running = false
    @Published private(set) var progress = 0
    @Published var error: String?
    private var work: Task<BenchmarkRun, Error>?
    private var observer: Task<Void, Never>?
    private var generation = UUID()
    private var loadFailed = false
    private let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceLab/runs.json")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                runs = try JSONDecoder().decode([BenchmarkRun].self, from: Data(contentsOf: file))
            }
        } catch {
            loadFailed = true
            self.error =
                "Saved runs could not be loaded. Existing data has been preserved. \(error.localizedDescription)"
        }
    }

    func run(_ experiment: Experiment, count: Int) {
        guard !running, !loadFailed else { return }
        running = true
        progress = 0
        error = nil
        let runID = UUID()
        generation = runID
        let environment =
            "\(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        let job = Task.detached(priority: .userInitiated) { [weak self] in
            // Warm both paths and check equivalence before collecting timed samples.
            let expected = try Workload.perform(experiment, count: count, optimized: false)
            guard expected == (try Workload.perform(experiment, count: count, optimized: true))
            else { throw BenchmarkError.mismatchedOutput }
            var baseline: [Double] = []
            var optimized: [Double] = []
            for iteration in 0..<5 {
                // Alternate order to reduce the influence of warm caches and thermal drift.
                for fast in iteration.isMultiple(of: 2) ? [false, true] : [true, false] {
                    try Task.checkCancellation()
                    let signpost = OSSignpostID(log: performanceLog)
                    os_signpost(
                        .begin, log: performanceLog, name: "Benchmark batch", signpostID: signpost,
                        "%{public}s optimized=%{public}d", experiment.rawValue, fast ? 1 : 0)
                    let start = DispatchTime.now().uptimeNanoseconds
                    let output: [String]
                    do {
                        output = try Workload.perform(experiment, count: count, optimized: fast)
                    } catch {
                        os_signpost(
                            .end, log: performanceLog, name: "Benchmark batch", signpostID: signpost
                        )
                        throw error
                    }
                    let duration = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    os_signpost(
                        .end, log: performanceLog, name: "Benchmark batch", signpostID: signpost)
                    guard output == expected else { throw BenchmarkError.mismatchedOutput }
                    if fast { optimized.append(duration) } else { baseline.append(duration) }
                }
                await self?.updateProgress(iteration + 1, runID: runID)
            }
            return BenchmarkRun(
                experiment: experiment, count: count, baseline: baseline, optimized: optimized,
                outputCount: expected.count, environment: environment)
        }
        work = job
        observer = Task { [weak self] in
            do {
                let result = try await job.value
                guard let self, self.generation == runID else { return }
                self.save(result)
                self.running = false
                self.work = nil
            } catch {
                guard let self, self.generation == runID else { return }
                if !(error is CancellationError) { self.error = error.localizedDescription }
                self.running = false
                self.work = nil
            }
        }
    }
    private func updateProgress(_ value: Int, runID: UUID) {
        if generation == runID { progress = value }
    }
    func cancel() {
        work?.cancel()
        generation = UUID()
        observer?.cancel()
        work = nil
        observer = nil
        running = false
    }
    private func save(_ run: BenchmarkRun) {
        let next = Array(([run] + runs).prefix(30))
        do {
            try JSONEncoder().encode(next).write(to: file, options: .atomic)
            runs = next
        } catch {
            self.error = "The measured run could not be saved. \(error.localizedDescription)"
        }
    }
    deinit {
        work?.cancel()
        observer?.cancel()
    }
}
