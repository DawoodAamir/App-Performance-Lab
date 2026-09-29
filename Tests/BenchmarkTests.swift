import XCTest

@testable import PerformanceCore

final class BenchmarkTests: XCTestCase {
    func testEveryOptimizationPreservesOrderedOutput() throws {
        for experiment in Experiment.allCases {
            for count in [1, 7, 100] {
                XCTAssertEqual(
                    try Workload.perform(experiment, count: count, optimized: false),
                    try Workload.perform(experiment, count: count, optimized: true),
                    experiment.rawValue)
            }
        }
    }
    func testMedianHandlesEvenOddAndInvalidSamples() {
        XCTAssertEqual(Statistics.median([9, 1, 3]), 3)
        XCTAssertEqual(Statistics.median([9, 1, 3, 5]), 4)
        XCTAssertNil(Statistics.median([]))
        XCTAssertNil(Statistics.median([.nan]))
        XCTAssertNil(Statistics.median([-1]))
    }
    func testDatasetBoundsRejectUnreasonableWork() {
        XCTAssertThrowsError(try Workload.perform(.search, count: 0, optimized: true))
        XCTAssertThrowsError(try Workload.perform(.dates, count: 10_001, optimized: false))
    }
    func testExportRetainsEveryMeasuredSample() {
        let run = BenchmarkRun(
            experiment: .search, count: 10, baseline: [4, 2], optimized: [1, 1], outputCount: 10,
            environment: "Test")
        XCTAssertEqual(run.speedup, 3)
        XCTAssertEqual(run.csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 5)
        XCTAssertTrue(run.csv.contains(",baseline,2,2.0"))
    }
}
