import Foundation
import PorydawPluginBridge
import Synchronization

struct BridgeReply: Equatable, Sendable {
    enum Outcome: Equatable, Sendable { case replied, missed, crashed }
    let outcome: Outcome
    let status: Int32
    let written: Int
    let total: Int
}

struct BridgeSnapshot: Sendable {
    let request: UInt32
    let reply: UInt32
    let heartbeat: UInt64
}

// Transfer this non-Sendable producer only after detaching/joining its previous worker.
// HelperProcess uses a separate mapping for monitoring and never retains this producer.
final class BridgeChannel {
    private static let nextInstance = Atomic<UInt32>(0)
    let name: String
    private let handle: OpaquePointer
    private var helperPID: UInt32 = 0

    init() throws {
        let instance = Self.nextInstance.wrappingAdd(1, ordering: .relaxed).newValue
        precondition(instance != 0, "Plugin bridge instance counter exhausted.")
        #if os(Windows)
            name = "Local\\porydaw-\(ProcessInfo.processInfo.processIdentifier)-\(instance)"
        #else
            name = "/porydaw-\(ProcessInfo.processInfo.processIdentifier)-\(instance)"
        #endif
        var channel: OpaquePointer?
        guard pdpb_channel_create(name, &channel) == PDPB_OK, let channel else {
            throw HelperProcessError.channelCreation
        }
        handle = channel
    }

    deinit { pdpb_channel_close(handle) }

    func bindHelper(pid: Int32) {
        precondition(helperPID == 0 && pid > 0)
        helperPID = UInt32(pid)
    }

    var snapshot: BridgeSnapshot {
        BridgeSnapshot(
            request: pdpb_request_sequence(handle), reply: pdpb_reply_sequence(handle),
            heartbeat: pdpb_heartbeat(handle))
    }

    private func exchange(
        frames: Int32, context: pdph_process_context, input: borrowing Span<pdph_midi_event>,
        output: inout MutableSpan<pdph_midi_event>, timeoutMicroseconds: UInt32, render: Bool
    ) -> BridgeReply {
        guard pdpb_reply_sequence(handle) == pdpb_request_sequence(handle) else {
            return BridgeReply(outcome: .missed, status: 0, written: 0, total: 0)
        }
        precondition(frames > 0 && frames <= PDPB_MAX_CHUNK && input.count <= PDPB_MAX_EVENTS)
        pdpb_request_context(handle).pointee = context
        input.withUnsafeBufferPointer { (source: UnsafeBufferPointer<pdph_midi_event>) in
            if let address = source.baseAddress, !source.isEmpty {
                pdpb_request_events(handle).update(from: address, count: source.count)
            }
        }
        pdpb_set_request(handle, frames, Int32(input.count))
        var sequence: UInt32 = 0
        guard pdpb_post_request(handle, &sequence) == PDPB_OK else {
            return BridgeReply(outcome: .missed, status: 0, written: 0, total: 0)
        }
        let wait = pdpb_wait_reply(handle, sequence, timeoutMicroseconds)
        guard wait == PDPB_OK, pdpb_reply_sequence(handle) == sequence else {
            if render {
                if helperPID != 0 { _ = pdpb_terminate_process(helperPID) }
                return BridgeReply(outcome: .crashed, status: Int32(PDPB_ERROR), written: 0, total: 0)
            }
            return BridgeReply(outcome: .missed, status: 0, written: 0, total: 0)
        }
        let written = Int(pdpb_reply_written(handle))
        let total = Int(pdpb_reply_total(handle))
        guard written >= 0, written <= PDPB_MAX_EVENTS, total >= written else {
            return BridgeReply(outcome: .crashed, status: Int32(PDPB_ERROR), written: 0, total: 0)
        }
        let copied = min(written, output.count)
        output.withUnsafeMutableBufferPointer { (destination: UnsafeMutableBufferPointer<pdph_midi_event>) in
            if let address = destination.baseAddress, copied > 0 {
                address.update(from: pdpb_reply_events(handle), count: copied)
            }
        }
        return BridgeReply(outcome: .replied, status: pdpb_reply_status(handle), written: copied, total: total)
    }

    func processLive(
        frames: Int32, context: pdph_process_context, input: borrowing Span<pdph_midi_event>,
        output: inout MutableSpan<pdph_midi_event>
    ) -> BridgeReply {
        precondition(context.sample_rate.isFinite && context.sample_rate > 0)
        let halfChunkMicroseconds = Double(frames) * 500_000 / context.sample_rate
        let timeout = UInt32(min(Double(UInt32.max), max(1_000, halfChunkMicroseconds)))
        return exchange(
            frames: frames, context: context, input: input, output: &output,
            timeoutMicroseconds: timeout, render: false)
    }

    func processRender(
        frames: Int32, context: pdph_process_context, input: borrowing Span<pdph_midi_event>,
        output: inout MutableSpan<pdph_midi_event>
    ) -> BridgeReply {
        precondition(helperPID != 0, "Bind the helper before transferring the Render producer.")
        return exchange(
            frames: frames, context: context, input: input, output: &output,
            timeoutMicroseconds: 10_000_000, render: true)
    }
}
