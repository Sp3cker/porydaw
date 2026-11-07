import Foundation
import PorydawAudioDeviceNative
import PorydawPlayback
import Synchronization

/// Owns the output device and its renderer. Lifecycle/cold calls are serialized by
/// the facade on its control thread, never made from the audio callback.
public final class AudioDevice {
    enum InitializationError: String, LocalizedError {
        case nullBackend = "Failed to initialize the null audio backend."
        case outputDevice = "Failed to initialize the audio output device."
        case startDevice = "Failed to start the audio output device."

        var errorDescription: String? { rawValue }
    }

    /// Programming invariant: the facade must not access the renderer after shutdown.
    public var renderer: AudioRenderEngine {
        precondition(target != nil, "AudioDevice renderer accessed after shutdown")
        return target!.renderer
    }
    public private(set) var sampleRate: Double = 0
    public private(set) var backendName = ""
    public private(set) var usingNullBackend = false
    public let nullBackendForced: Bool
    public private(set) var periodSizeFrames = 0
    public private(set) var periodCount = 0
    public private(set) var isRunning = false
    public private(set) var lastStartError: String?

    public init(sampleFeedback: SampleAuditionFeedbackCell = .init()) throws {
        let environment = ProcessInfo.processInfo.environment
        nullBackendForced = environment["PORYDAW_AUDIO_BACKEND"] == "null"
        do {
            if nullBackendForced {
                guard initializeContext(backends: [ma_backend_null]) else {
                    throw InitializationError.nullBackend
                }
            }
            #if os(Linux)
                if !nullBackendForced {
                    // The original private ALSA variadic no-op handler cannot be supplied
                    // as a typed Swift C callback. ALSA stderr remains unsuppressed here.
                    // Failure deliberately leaves context nil for miniaudio's default policy.
                    _ = initializeContext(backends: [ma_backend_pulseaudio, ma_backend_alsa])
                }
            #endif

            let device = UnsafeMutablePointer<ma_device>.allocate(capacity: 1)
            self.device = device
            var config = ma_device_config_init(ma_device_type_playback)
            config.playback.format = ma_format_f32
            config.playback.channels = 2
            config.sampleRate = 0  // Negotiate the device's native rate.
            config.dataCallback = audioDeviceRender
            var period = Self.parsePeriod(environment["PORYDAW_AUDIO_PERIOD_MS"])
            #if os(Linux)
                if (period ?? 0) <= 0, Self.runningUnderWSL {
                    period = 30
                }
            #endif
            if let period, period > 0 {
                config.periodSizeInMilliseconds = UInt32(min(500, max(1, period)))
            }
            guard ma_device_init(context, &config, device) == MA_SUCCESS else {
                throw InitializationError.outputDevice
            }
            deviceInitialized = true
            sampleRate = Double(device.pointee.sampleRate)
            let backend = device.pointee.pContext!.pointee.backend
            backendName = String(cString: ma_get_backend_name(backend))
            usingNullBackend = backend == ma_backend_null
            periodSizeFrames = Int(device.pointee.playback.internalPeriodSizeInFrames)
            periodCount = Int(device.pointee.playback.internalPeriods)
            let target = AudioCallbackTarget(
                renderer: try AudioRenderEngine(
                    sampleRate: sampleRate, periodFrames: periodSizeFrames, sampleFeedback: sampleFeedback))
            self.target = target
            device.pointee.pUserData = Unmanaged.passUnretained(target).toOpaque()
        } catch {
            shutdown()
            throw error
        }
    }

    /// Control runs cold changes between callback blocks; the device keeps running and a
    /// block that arrives meanwhile renders silence instead of waiting.
    public func withRenderingExcluded<T>(_ body: () throws -> T) rethrows -> T {
        guard let target else { return try body() }
        while !target.gate.compareExchange(expected: .open, desired: .excluded, ordering: .acquiring).exchanged {
            Thread.sleep(forTimeInterval: 0.000_05)
        }
        defer { target.gate.store(.open, ordering: .releasing) }
        return try body()
    }

    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }
        guard let device, ma_device_start(device) == MA_SUCCESS else {
            lastStartError = InitializationError.startDevice.localizedDescription
            return false
        }
        isRunning = true
        lastStartError = nil
        return true
    }

    public func shutdown() {
        if let device {
            if deviceInitialized {
                ma_device_uninit(device)  // Joins/parks callbacks before releasing their borrower.
            }
            device.deallocate()
            self.device = nil
            deviceInitialized = false
            isRunning = false
        }
        target = nil
        if let context {
            _ = ma_context_uninit(context)
            context.deallocate()
            self.context = nil
        }
    }

    deinit { shutdown() }

    private var target: AudioCallbackTarget?
    private var device: UnsafeMutablePointer<ma_device>?
    private var context: UnsafeMutablePointer<ma_context>?
    private var deviceInitialized = false

    private func initializeContext(backends: [ma_backend]) -> Bool {
        let context = UnsafeMutablePointer<ma_context>.allocate(capacity: 1)
        let result = backends.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<ma_backend>) in
            ma_context_init(buffer.baseAddress, UInt32(buffer.count), nil, context)
        }
        guard result == MA_SUCCESS else {
            context.deallocate()
            return false
        }
        self.context = context
        return true
    }

    /// Qt's environment integer conversion uses base 0, ASCII whitespace and a C int range.
    private static func parsePeriod(_ value: String?) -> Int32? {
        guard let value else { return nil }
        var digits = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))[...]
        let negative = digits.first == "-"
        if negative || digits.first == "+" { digits = digits.dropFirst() }
        let radix: Int
        if digits.hasPrefix("0x") || digits.hasPrefix("0X") {
            radix = 16
            digits = digits.dropFirst(2)
        } else if digits.hasPrefix("0b") || digits.hasPrefix("0B") {
            radix = 2
            digits = digits.dropFirst(2)
        } else {
            radix = digits.first == "0" ? 8 : 10
        }
        guard let first = digits.utf8.first,
            (48...57).contains(first) || (radix == 16 && ((65...70).contains(first) || (97...102).contains(first))),
            let magnitude = Int64(digits, radix: radix), magnitude >= 0
        else { return nil }
        return Int32(exactly: negative ? -magnitude : magnitude)
    }

    #if os(Linux)
        private static var runningUnderWSL: Bool {
            guard let release = try? String(contentsOfFile: "/proc/sys/kernel/osrelease", encoding: .utf8) else {
                return false
            }
            return release.lowercased().contains("microsoft")
        }
    #endif
}

/// The callback's borrowed renderer and the gate control closes around cold changes.
private final class AudioCallbackTarget {
    enum Gate: UInt8, AtomicRepresentable { case open, rendering, excluded }
    let renderer: AudioRenderEngine
    let gate = Atomic<Gate>(.open)

    init(renderer: AudioRenderEngine) { self.renderer = renderer }
}

/// Playback guarantees non-null output; pUserData borrows the target until uninit returns.
/// No captures, allocations, locks, reclamation, or dispatch in this trampoline.
private func audioDeviceRender(
    _ device: UnsafeMutablePointer<ma_device>?, _ output: UnsafeMutableRawPointer?,
    _ input: UnsafeRawPointer?, _ frames: UInt32
) {
    let target = Unmanaged<AudioCallbackTarget>.fromOpaque(device!.pointee.pUserData!).takeUnretainedValue()
    let samples = output!.assumingMemoryBound(to: Float.self)
    guard target.gate.compareExchange(expected: .open, desired: .rendering, ordering: .acquiring).exchanged else {
        samples.update(repeating: 0, count: Int(frames) * 2)
        return
    }
    target.renderer.render(samples, frames: frames)
    target.gate.store(.open, ordering: .releasing)
}
