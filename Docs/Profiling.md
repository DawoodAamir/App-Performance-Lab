# Profiling an experiment

1. Select a physical iPhone and the App Performance Lab scheme.
2. Use Product → Profile. The shared scheme uses Release for profiling.
3. Choose Time Profiler, then add Points of Interest / os_signpost if it is not shown.
4. Start recording and run one experiment inside the app.
5. Find the `Benchmark batch` intervals in subsystem `com.dd.performancelab`.
6. Select baseline and optimized intervals and compare their call trees. Verify that the work moved or disappeared as expected.

Signpost metadata identifies the workload and optimized flag. Every timed call includes dataset creation and output creation; equality comparison happens afterward. This makes the comparison observable but does not isolate every allocation or normalize for OS scheduling.

## What to look for

| Workload | Baseline | Optimized | Tradeoff |
| --- | --- | --- | --- |
| Catalog search | Lowercase titles for each query | Lowercase once, reuse for six queries | Extra prepared array |
| Date formatting | New formatter per date | One formatter per batch | Safe only within this isolated batch |
| Duplicate removal | Linear membership scan | Set membership with ordered output | Additional Set storage |

Run several sessions under comparable conditions. Do not publish a universal speedup from one device. Memory and power tradeoffs need separate Instruments measurements.

Apple reference: [Recording performance data](https://developer.apple.com/documentation/os/recording-performance-data).
