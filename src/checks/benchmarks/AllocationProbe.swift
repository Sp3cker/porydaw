import Foundation

#if os(macOS)
    import Darwin
#endif

struct AllocationBenchmarkOptions {
    let warmup: Int
    let iterations: Int

    static var requestedScenario: String? {
        ProcessInfo.processInfo.environment["PORYDAW_ALLOCATION_SCENARIO"]
    }

    static func load(for scenario: String) throws -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PORYDAW_ALLOCATION_SCENARIO"] == scenario else { return nil }
        func count(_ name: String, default fallback: Int, minimum: Int) throws -> Int {
            guard let text = environment[name] else { return fallback }
            guard let value = Int(text), value >= minimum else {
                throw AllocationProbeError.invalidOption(name)
            }
            return value
        }
        return try Self(
            warmup: count("PORYDAW_ALLOCATION_WARMUP", default: 64, minimum: 0),
            iterations: count("PORYDAW_ALLOCATION_ITERATIONS", default: 1000, minimum: 1))
    }
}

enum AllocationProbeError: Error, CustomStringConvertible {
    case unsupportedPlatform
    case missingLibrary
    case loadFailed(String)
    case missingSymbol(String)
    case invalidOption(String)

    var description: String {
        switch self {
        case .unsupportedPlatform: "Allocation macrobenchmarks require macOS"
        case .missingLibrary: "PORYDAW_ALLOCATION_DYLIB is required for allocation macrobenchmarks"
        case .loadFailed(let detail): "Could not load allocation recorder: \(detail)"
        case .missingSymbol(let name): "Allocation recorder is missing \(name)"
        case .invalidOption(let name): "Invalid allocation macrobenchmark count: \(name)"
        }
    }
}

// Checks-only interface. Each segment captures only the calling thread.
// Load/setup/report outside capture; keep the recorder loaded until process exit.
struct AllocationProbe {
    private typealias VoidFunction = @convention(c) () -> Void
    private typealias ReportFunction = @convention(c) (UnsafePointer<CChar>?, UInt64) -> Void
    private let resetFunction: VoidFunction
    private let beginFunction: VoidFunction
    private let pauseFunction: VoidFunction
    private let reportFunction: ReportFunction

    func reset() { resetFunction() }
    func begin() { beginFunction() }
    func pause() { pauseFunction() }

    func report(label: String, operations: UInt64) {
        pause()
        label.withCString { reportFunction($0, operations) }
    }

    static func load() throws -> Self {
        #if os(macOS)
            guard let path = ProcessInfo.processInfo.environment["PORYDAW_ALLOCATION_DYLIB"],
                !path.isEmpty
            else { throw AllocationProbeError.missingLibrary }
            guard let handle = dlopen(path, RTLD_NOW) else {
                let detail = dlerror().map { String(cString: $0) } ?? "unknown dynamic-loader error"
                throw AllocationProbeError.loadFailed(detail)
            }
            func symbol<T>(_ name: String, as type: T.Type) throws -> T {
                guard let address = dlsym(handle, name) else {
                    throw AllocationProbeError.missingSymbol(name)
                }
                return unsafeBitCast(address, to: type)
            }
            return try Self(
                resetFunction: symbol("pda_profile_reset", as: VoidFunction.self),
                beginFunction: symbol("pda_profile_begin", as: VoidFunction.self),
                pauseFunction: symbol("pda_profile_pause", as: VoidFunction.self),
                reportFunction: symbol("pda_profile_report", as: ReportFunction.self))
        #else
            throw AllocationProbeError.unsupportedPlatform
        #endif
    }
}
