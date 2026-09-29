import SwiftUI

@main
struct PerformanceLabApp: App {
    @StateObject private var store = BenchmarkStore()
    var body: some Scene {
        WindowGroup { LabView().environmentObject(store).tint(Color("AccentColor")) }
    }
}

struct LabView: View {
    @EnvironmentObject private var store: BenchmarkStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var experiment = Experiment.search
    @State private var size = 1_000
    var body: some View {
        NavigationView {
            List {
                Section {
                    Label("Measure before you optimize", systemImage: "stopwatch").font(.headline)
                    Text(
                        "Compare equivalent work on this device. Every result contains five measured samples per implementation."
                    ).foregroundColor(.secondary)
                }
                Section("Experiment") {
                    Picker("Workload", selection: $experiment) {
                        ForEach(Experiment.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Dataset", selection: $size) {
                        Text("1,000 items").tag(1_000)
                        Text("3,000 items").tag(3_000)
                        Text("6,000 items").tag(6_000)
                    }
                    Text(experiment.explanation).font(.subheadline).foregroundColor(.secondary)
                }.disabled(store.running)
                Section {
                    if store.running {
                        ProgressView(
                            "Measuring · \(store.progress) of 5 pairs",
                            value: Double(store.progress), total: 5)
                        Button("Cancel run", role: .cancel) { store.cancel() }
                    } else {
                        Button {
                            store.run(experiment, count: size)
                        } label: {
                            Label("Run comparison", systemImage: "play.fill")
                        }
                    }
                } footer: {
                    Text(
                        "For meaningful comparisons, use a physical device and a Release build. Debug builds and simulators affect timings. No performance improvement is guaranteed."
                    )
                }
                Section("Recent runs") {
                    if store.runs.isEmpty {
                        Text("Your first comparison will appear here.").foregroundColor(.secondary)
                    }
                    ForEach(store.runs) { run in
                        NavigationLink(destination: RunDetail(run: run)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(run.experiment.title).font(.headline)
                                Text(
                                    "\(run.count.formatted()) items · \(run.date.formatted(date: .abbreviated, time: .shortened))"
                                ).font(.caption).foregroundColor(.secondary)
                                HStack {
                                    Text(
                                        String(
                                            format: "%.2f ms → %.2f ms", run.baselineMedian,
                                            run.optimizedMedian)
                                    ).monospacedDigit()
                                    Spacer()
                                    Image(systemName: "chart.bar.xaxis")
                                }.font(.subheadline)
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.navigationTitle("Performance Lab")
        }.navigationViewStyle(.stack)
            .onAppear {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--run-benchmark"),
                        store.runs.isEmpty
                    {
                        store.run(.search, count: 3_000)
                    }
                #endif
            }
            .onChange(of: scenePhase) { if $0 != .active { store.cancel() } }
            .alert(
                "Benchmark",
                isPresented: Binding(
                    get: { store.error != nil }, set: { if !$0 { store.error = nil } })
            ) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
    }
}

struct RunDetail: View {
    let run: BenchmarkRun
    @State private var export: ExportFile?
    @State private var error: String?
    var body: some View {
        List {
            Section("Median elapsed time") {
                TimingBar(
                    name: "Baseline", value: run.baselineMedian,
                    maximum: max(run.baselineMedian, run.optimizedMedian), color: .secondary)
                TimingBar(
                    name: "Optimized", value: run.optimizedMedian,
                    maximum: max(run.baselineMedian, run.optimizedMedian), color: .accentColor)
                if let speedup = run.speedup {
                    Text(String(format: "Baseline / optimized: %.2f×", speedup)).font(.headline)
                }
            }
            Section("Method") {
                Text(run.experiment.explanation)
                Label("Outputs verified equal", systemImage: "checkmark.seal")
                Text("\(run.count.formatted()) inputs · \(run.outputCount.formatted()) outputs")
                Text(
                    "One warm-up per path. Five samples per path. Alternating execution order. Timings include preparation and result creation, but exclude output comparison and disk writes."
                ).foregroundColor(.secondary)
                Text(run.environment).font(.caption)
            }
            Section("Samples in milliseconds") {
                HStack {
                    Text("Pair")
                    Spacer()
                    Text("Baseline")
                    Spacer()
                    Text("Optimized")
                }.font(.caption).foregroundColor(.secondary)
                ForEach(Array(run.baseline.indices), id: \.self) { index in
                    HStack {
                        Text("\(index + 1)")
                        Spacer()
                        Text(String(format: "%.3f", run.baseline[index]))
                        Spacer()
                        Text(String(format: "%.3f", run.optimized[index]))
                    }.monospacedDigit()
                }
            }
            Section {
                Button("Export CSV") {
                    do {
                        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
                            "Benchmark-\(run.id).csv")
                        try run.csv.write(to: url, atomically: true, encoding: .utf8)
                        export = ExportFile(url: url)
                    } catch { self.error = error.localizedDescription }
                }
            }
        }.navigationTitle(run.experiment.title)
            .sheet(item: $export) { ActivitySheet(items: [$0.url]) }
            .alert(
                "Export failed",
                isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
            ) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
    }
}

struct TimingBar: View {
    let name: String
    let value: Double
    let maximum: Double
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                Spacer()
                Text(String(format: "%.3f ms", value)).monospacedDigit()
            }
            GeometryReader { geometry in
                Capsule().fill(color.opacity(0.15)).overlay(alignment: .leading) {
                    Capsule().fill(color).frame(
                        width: geometry.size.width * CGFloat(maximum > 0 ? value / maximum : 0))
                }
            }.frame(height: 8).accessibilityHidden(true)
        }.padding(.vertical, 6)
    }
}
struct ExportFile: Identifiable {
    let url: URL
    var id: URL { url }
}
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
