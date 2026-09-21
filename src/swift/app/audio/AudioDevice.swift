import Foundation
import PorydawAudioDeviceNative

/// Owns the output device and its renderer. Lifecycle/cold calls are serialized by
/// the facade on its control thread, never made from the audio callback.
final class AudioDevice {
    enum InitializationError: String, LocalizedError {
        case nullBackend = "Failed to initialize the null audio backend."
        case outputDevice = "Failed to initialize the audio output device."
        case startDevice = "Failed to start the audio output device."

        var errorDescription: String? { rawValue }
    }

    /// Programming invariant: the facade must not access the renderer after shutdown.
    var renderer: AudioRenderEngine {
        precondition(retainedRenderer != nil, "AudioDevice renderer accessed after shutdown")
        return retainedRenderer!
    }
    private(set) var sampleRate: Double = 0
    private(set) var backendName = ""
    private(set) var usingNullBackend = false
    let nullBackendForced: Bool
    private(set) var periodSizeFrames = 0
    private(set) var periodCount = 0

    init() throws {
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
            config.sampleRate = 0 // Negotiate the device's native rate.
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
            retainedRenderer = try AudioRenderEngine(
                sampleRate: sampleRate, periodFrames: periodSizeFrames)
            // The device is still stopped. Publish only after the renderer is complete;
            // retain it through uninit, including when start partially fails.
            device.pointee.pUserData = Unmanaged.passUnretained(renderer).toOpaque()
            guard ma_device_start(device) == MA_SUCCESS else {
                throw InitializationError.startDevice
            }
            deviceStarted = true
        } catch {
            shutdown()
            throw error
        }
    }

    /// Matches native cold operations: stop/resume results are deliberately ignored.
    /// Nested cold operations remain parked until the outer operation finishes.
    func withRenderingStopped<T>(_ body: () throws -> T) rethrows -> T {
        let resume = deviceStarted
        if resume, let device {
            _ = ma_device_stop(device)
            deviceStarted = false
        }
        defer {
            if resume, let device {
                _ = ma_device_start(device)
                deviceStarted = true
            }
        }
        return try body()
    }

    func shutdown() {
        if let device {
            if deviceInitialized {
                ma_device_uninit(device) // Joins/parks callbacks before releasing their borrower.
            }
            device.deallocate()
            self.device = nil
            deviceInitialized = false
            deviceStarted = false
        }
        retainedRenderer = nil
        if let context {
            _ = ma_context_uninit(context)
            context.deallocate()
            self.context = nil
        }
    }

    deinit { shutdown() }

    private var retainedRenderer: AudioRenderEngine?
    private var device: UnsafeMutablePointer<ma_device>?
    private var context: UnsafeMutablePointer<ma_context>?
    private var deviceInitialized = false
    private var deviceStarted = false

    private func initializeContext(backends: [ma_backend]) -> Bool {
        let context = UnsafeMutablePointer<ma_context>.allocate(capacity: 1)
        let result = backends.withUnsafeBufferPointer {
            ma_context_init($0.baseAddress, UInt32($0.count), nil, context)
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
              let magnitude = Int64(digits, radix: radix), magnitude >= 0 else { return nil }
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

/// Playback guarantees non-null output; pUserData borrows the renderer until uninit returns.
/// No captures, allocations, locks, reclamation, or dispatch in this trampoline.
private func audioDeviceRender(
    _ device: UnsafeMutablePointer<ma_device>?, _ output: UnsafeMutableRawPointer?,
    _ input: UnsafeRawPointer?, _ frames: UInt32
) {
    Unmanaged<AudioRenderEngine>.fromOpaque(device!.pointee.pUserData!)
        .takeUnretainedValue().render(output!.assumingMemoryBound(to: Float.self), frames: frames)
}
