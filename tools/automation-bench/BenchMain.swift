import Dispatch
import Foundation
import PorydawCore
import os

@testable import PorydawApp

@_silgen_name("automation_bench_finish")
private func finishBenchmark(_ code: Int32)
@_silgen_name("automation_bench_drain")
func drainNotifications()

private struct Options {
    var nodes = [128]
    var samples = 16
    var iterations = 100
    var warmup = 5
    var seconds = 0.0
    var filter = ""
    var lane = "all"
    var list = false
    var signposts = true
    var workload = BenchWorkload()

    static let help = """
        automation-bench [--list] [--filter substring] [--lane all|pan|volume|xcmd|bend|tempo]
          --nodes 32,128,1024  nodes per lane (default 128; minimum 4)
          --samples N         pointer-move samples per gesture (default 16)
          --iterations N      measured repetitions per scenario/lane/size (default 100)
          --warmup N          untimed repetitions (default 5)
          --seconds N         minimum wall duration per scenario, in addition to iterations
          --no-signposts      disable Instruments interval markers
          --notes N           paired notes per track, independent of --nodes (default 1)
          --tracks N          MIDI/engine tracks, 1...16 (default 1)
          --selected-nodes N  group preview targets, capped to --nodes (default 1)
          --visible-nodes N   beat slots in 480px viewport, 1...100; 0 keeps native zoom
          --duplicate-occupants N  occupants overwritten at the destination (default 2)
          --bulk-points N     points per start/end paste, capped to --nodes - 1 (default 32)
          --history-depth N   untimed prior edits in sustained cases (default 0)
          --edits N           timed batch length in sustained cases (default 100)
        Setup, preparation, validation, and teardown are outside reported edit timing.
        Swift publication and queued QtBridge flush are included. No QML or audio output.
        """

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let key = arguments[index]
            index += 1
            if key == "--list" {
                list = true
                continue
            }
            if key == "--no-signposts" {
                signposts = false
                continue
            }
            guard index < arguments.count else { throw BenchFailure(description: "Missing value for \(key)") }
            let value = arguments[index]
            index += 1
            if try workload.consume(option: key, value: value) { continue }
            switch key {
            case "--filter": filter = value
            case "--lane": lane = value
            case "--nodes":
                let parts = value.split(separator: ",", omittingEmptySubsequences: false)
                let parsed = parts.compactMap { Int($0) }
                guard parsed.count == parts.count, !parsed.isEmpty,
                    parsed.allSatisfy({ (4...100_000).contains($0) })
                else {
                    throw BenchFailure(description: "--nodes requires integers from 4 through 100000")
                }
                nodes = parsed
            case "--samples", "--iterations", "--warmup":
                guard let count = Int(value), (key == "--warmup" ? 0 : 1)...1_000_000 ~= count,
                    key != "--samples" || count <= 256
                else {
                    throw BenchFailure(description: "Invalid count for \(key)")
                }
                switch key {
                case "--samples": samples = count
                case "--iterations": iterations = count
                default: warmup = count
                }
            case "--seconds":
                guard let parsed = Double(value), parsed.isFinite, (0...3600).contains(parsed) else {
                    throw BenchFailure(description: "--seconds must be from 0 through 3600")
                }
                seconds = parsed
            default: throw BenchFailure(description: "Unknown option \(key)")
            }
        }
        guard ["all", "pan", "volume", "xcmd", "bend", "tempo"].contains(lane) else {
            throw BenchFailure(description: "Unknown lane \(lane)")
        }
    }

    var lanes: [(String, AutomationParameter)] {
        let all: [(String, AutomationParameter)] = [
            ("pan", .controlChange(track: 0, controller: TimeDefaults.ccPan)),
            ("volume", .controlChange(track: 0, controller: TimeDefaults.ccVolume)),
            ("xcmd", .controlChange(track: 0, controller: Xcmd.echoVolumeLane)),
            ("bend", .pitchBend(track: 0)), ("tempo", .tempo),
        ]
        return lane == "all" ? all : all.filter { $0.0 == lane }
    }
}

@MainActor
private enum Benchmark {
    static let signposter = OSSignposter(subsystem: "org.porydaw.automation-bench", category: "PointsOfInterest")

    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") || args.contains("-h") {
            print(Options.help)
            return
        }
        let options = try Options(args)
        let scenarios =
            (nodeScenarios() + nodeHistoryScenarios() + drawingScenarios()
            + nodeScalingScenarios() + bulkScalingScenarios() + sustainedHistoryScenarios()).filter {
                options.filter.isEmpty || $0.name.contains(options.filter)
            }
        guard !scenarios.isEmpty else { throw BenchFailure(description: "No matching scenarios") }
        if options.list {
            for scenario in scenarios { print(scenario.name) }
            return
        }
        let environment = try await BenchEnvironment.open()
        do {
            print(
                "scenario,lane,nodes,pointer_samples,repetitions,min_us,p50_us,p95_us,max_us,mean_us,"
                    + "notes_per_track,tracks,selected_nodes,visible_nodes,pixels_per_beat,duplicate_occupants,"
                    + "bulk_points,history_depth,edits,operations,p50_amortized_us,p95_amortized_us")
            for count in options.nodes {
                for (laneName, parameter) in options.lanes {
                    for scenario in scenarios {
                        let configuration = { () -> (applies: Bool, operations: Int, pixelsPerBeat: Double) in
                            let probe = BenchFixture(
                                environment: environment, parameter: parameter,
                                nodes: count, samples: options.samples, workload: options.workload)
                            return (
                                scenario.applies(probe), scenario.operations(probe),
                                probe.session.camera.snapshot.pixelsPerBeat
                            )
                        }()
                        drainNotifications()
                        guard configuration.applies else { continue }
                        let operations = configuration.operations
                        guard operations > 0 else { throw BenchFailure(description: "Invalid operation count") }
                        var measurements: [UInt64] = []
                        measurements.reserveCapacity(options.iterations)
                        for _ in 0..<options.warmup {
                            _ = try await sample(
                                scenario, environment: environment, parameter: parameter,
                                count: count, options: options, measured: false)
                        }
                        let start = DispatchTime.now().uptimeNanoseconds
                        repeat {
                            measurements.append(
                                try await sample(
                                    scenario, environment: environment, parameter: parameter,
                                    count: count, options: options, measured: true))
                        } while measurements.count < options.iterations
                            || Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9 < options.seconds
                        measurements.sort()
                        let mean = measurements.reduce(0.0) { $0 + Double($1) } / Double(measurements.count) / 1000
                        let p50 = Double(measurements[(measurements.count - 1) / 2]) / 1000
                        let p95 = Double(measurements[Int(ceil(Double(measurements.count) * 0.95)) - 1]) / 1000
                        guard let minimum = measurements.first, let maximum = measurements.last else {
                            throw BenchFailure(description: "No measurements")
                        }
                        let dimensions = options.workload
                        print(
                            String(
                                format: "%@,%@,%d,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f",
                                scenario.name, laneName, count, options.samples, measurements.count,
                                Double(minimum) / 1000, p50, p95, Double(maximum) / 1000, mean)
                                + ",\(dimensions.notesPerTrack),\(dimensions.trackCount),"
                                + "\(min(dimensions.selectedNodes, count)),\(dimensions.visibleNodes),"
                                + "\(configuration.pixelsPerBeat),\(dimensions.duplicateOccupants),"
                                + "\(min(dimensions.bulkPoints, count - 1)),\(dimensions.historyDepth),"
                                + "\(dimensions.editCount),\(operations),"
                                + String(format: "%.3f,%.3f", p50 / Double(operations), p95 / Double(operations)))
                    }
                }
            }
        } catch {
            try await environment.close()
            throw error
        }
        try await environment.close()
    }

    @inline(never)
    private static func sample(
        _ scenario: BenchScenario, environment: BenchEnvironment,
        parameter: AutomationParameter, count: Int, options: Options,
        measured: Bool
    ) async throws -> UInt64 {
        let fixture = BenchFixture(
            environment: environment, parameter: parameter,
            nodes: count, samples: options.samples, workload: options.workload)
        do {
            try fixture.validateDensity()
            try await scenario.prepare(fixture)
        } catch {
            throw BenchFailure(
                description:
                    "\(scenario.name) / \(AutomationCatalog.title(parameter)) / nodes=\(count) prepare: \(error)")
        }
        drainNotifications()
        let interval =
            measured && options.signposts
            ? signposter.beginInterval(
                "Automation edit", id: signposter.makeSignpostID(), "\(scenario.name, privacy: .public)")
            : nil
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            try await scenario.run(fixture)
            drainNotifications()
        } catch {
            if let interval { signposter.endInterval("Automation edit", interval) }
            throw error
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        if let interval { signposter.endInterval("Automation edit", interval) }
        do {
            try scenario.validate(fixture)
        } catch {
            throw BenchFailure(
                description: "\(scenario.name) / \(AutomationCatalog.title(parameter)) / nodes=\(count): \(error)")
        }
        return elapsed
    }
}

@_cdecl("automation_bench_start")
func startBenchmark() {
    Task { @MainActor in
        do {
            try await Benchmark.run()
            finishBenchmark(0)
        } catch {
            FileHandle.standardError.write(Data("automation-bench: \(error)\n".utf8))
            finishBenchmark(1)
        }
    }
}
