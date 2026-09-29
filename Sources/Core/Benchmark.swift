import Foundation

public enum Experiment: String, Codable, CaseIterable, Identifiable {
    case search, dates, deduplication
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .search: return "Catalog search"
        case .dates: return "Date formatting"
        case .deduplication: return "Duplicate removal"
        }
    }
    public var explanation: String {
        switch self {
        case .search:
            return
                "Normalize every title for every query, then compare with normalizing once per batch. Preparation is included in the measured time."
        case .dates:
            return
                "Create a DateFormatter for each date, then compare with reusing one formatter for the batch."
        case .deduplication:
            return
                "Find duplicates with Array.contains, then compare with a Set while preserving input order."
        }
    }
}

public enum Workload {
    public static func perform(_ experiment: Experiment, count: Int, optimized: Bool) throws
        -> [String]
    {
        guard (1...10_000).contains(count) else { throw BenchmarkError.invalidSize }
        switch experiment {
        case .search:
            let names = (0..<count).map {
                "Product \($0) \($0.isMultiple(of: 3) ? "Oak Desk" : "Steel Lamp")"
            }
            let queries = ["desk", "lamp", "product 12", "missing", "steel", "oak"]
            let prepared = optimized ? names.map { $0.lowercased() } : []
            var result: [String] = []
            for query in queries {
                try Task.checkCancellation()
                for index in names.indices
                where (optimized ? prepared[index] : names[index].lowercased()).contains(query) {
                    result.append("\(query):\(index)")
                }
            }
            return result
        case .dates:
            func formatter() -> DateFormatter {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.timeZone = TimeZone(secondsFromGMT: 0)
                f.calendar = Calendar(identifier: .gregorian)
                f.dateFormat = "yyyy-MM-dd HH:mm"
                return f
            }
            let shared = optimized ? formatter() : nil
            return try (0..<count).map { index in
                try Task.checkCancellation()
                return (shared ?? formatter()).string(
                    from: Date(timeIntervalSince1970: Double(index) * 3600))
            }
        case .deduplication:
            var output: [String] = []
            var seen: Set<String> = []
            for index in 0..<count {
                if index.isMultiple(of: 100) { try Task.checkCancellation() }
                let value = "item-\(index % max(1, count / 2))"
                if optimized ? seen.insert(value).inserted : !output.contains(value) {
                    output.append(value)
                }
            }
            return output
        }
    }
}

public enum BenchmarkError: LocalizedError {
    case invalidSize, mismatchedOutput
    public var errorDescription: String? {
        switch self {
        case .invalidSize: return "Choose a dataset between 1 and 10,000 items."
        case .mismatchedOutput:
            return "The implementations returned different results. This run was discarded."
        }
    }
}

public enum Statistics {
    public static func median(_ samples: [Double]) -> Double? {
        guard !samples.isEmpty, samples.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

public struct BenchmarkRun: Codable, Identifiable {
    public var id = UUID()
    public let date: Date
    public let experiment: Experiment
    public let count: Int
    public let baseline: [Double]
    public let optimized: [Double]
    public let outputCount: Int
    public let environment: String
    public var baselineMedian: Double { Statistics.median(baseline) ?? 0 }
    public var optimizedMedian: Double { Statistics.median(optimized) ?? 0 }
    public var speedup: Double? { optimizedMedian > 0 ? baselineMedian / optimizedMedian : nil }
    public init(
        date: Date = Date(), experiment: Experiment, count: Int, baseline: [Double],
        optimized: [Double], outputCount: Int, environment: String
    ) {
        self.date = date
        self.experiment = experiment
        self.count = count
        self.baseline = baseline
        self.optimized = optimized
        self.outputCount = outputCount
        self.environment = environment
    }
    public var csv: String {
        let header = "run_id,experiment,items,variant,iteration,milliseconds\r\n"
        return header
            + [("baseline", baseline), ("optimized", optimized)].flatMap { variant, values in
                values.enumerated().map { index, value in
                    "\(id.uuidString),\(experiment.rawValue),\(count),\(variant),\(index + 1),\(value)"
                }
            }.joined(separator: "\r\n") + "\r\n"
    }
}
