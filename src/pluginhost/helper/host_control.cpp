#include "host.h"
#include "pluginhost_internal.h"
#include <QCoreApplication>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <utility>
#include <vector>

namespace pdph::helper {
namespace {
void append32(QByteArray& bytes, uint32_t value) {
    for (unsigned shift = 0; shift < 32; shift += 8) bytes.append(static_cast<char>(value >> shift));
}
void append64(QByteArray& bytes, uint64_t value) {
    for (unsigned shift = 0; shift < 64; shift += 8) bytes.append(static_cast<char>(value >> shift));
}
void appendBytes(QByteArray& bytes, const QByteArray& value) {
    append32(bytes, static_cast<uint32_t>(value.size())); bytes.append(value);
}
struct Payload {
    const QByteArray& bytes;
    qsizetype position = 0;
    bool valid = true;
    uint32_t u32() {
        if (bytes.size() - position < 4) { valid = false; return 0; }
        uint32_t value = 0;
        for (unsigned shift = 0; shift < 32; shift += 8) value |= uint32_t(static_cast<unsigned char>(bytes[position++])) << shift;
        return value;
    }
    double f64() {
        const uint64_t low = u32(), high = u32();
        const uint64_t bits = low | (high << 32);
        double value; std::memcpy(&value, &bits, sizeof(value)); return value;
    }
    QByteArray raw(uint32_t size) {
        if (static_cast<uint64_t>(bytes.size() - position) < size) { valid = false; return {}; }
        auto value = bytes.mid(position, size); position += size; return value;
    }
    QByteArray data() { const auto size = u32(); return valid ? raw(size) : QByteArray{}; }
    bool done() const { return valid && position == bytes.size(); }
};
QString sdkError(int32_t result) { return QStringLiteral("Plugin operation failed (%1)").arg(result); }
void reply(Host& host, const Frame& frame, const QByteArray& data, const QString& error) {
    QByteArray payload;
    append32(payload, error.isEmpty() ? 0 : 1);
    if (error.isEmpty()) payload.append(data); else appendBytes(payload, error.toUtf8());
    if (!sendFrame(PDPB_REPLY, frame.request, payload)) host.stop(1);
}
void endEdit(void* user, uint32_t id) { static_cast<Host*>(user)->enqueue(PDPB_END_EDIT, id); }
void restart(void* user, int32_t flags) { static_cast<Host*>(user)->enqueue(PDPB_RESTART_COMPONENT, static_cast<uint32_t>(flags)); }
void dirty(void* user, int32_t on) { static_cast<Host*>(user)->enqueue(PDPB_SET_DIRTY, on != 0); }
void editorClosed(void* user) { static_cast<Host*>(user)->enqueue(PDPB_EDITOR_CLOSED, 0); }
void shortcut(void* user, int32_t index) { static_cast<Host*>(user)->enqueue(PDPB_SHORTCUT, uint32_t(index)); }
bool state(pdph_plugin plugin, int32_t which, QByteArray& bytes, QString& error) {
    uint8_t* raw = nullptr; int64_t size = 0;
    const auto result = pdph_plugin_get_state(plugin, which, &raw, &size);
    std::unique_ptr<uint8_t, decltype(&pdph_free_buffer)> owned(raw, pdph_free_buffer);
    if (result != PDPH_OK) { error = sdkError(result); return false; }
    if (size < 0 || size > PDPB_MAX_CONTROL_BYTES - 8 || (size && !raw)) {
        error = QStringLiteral("Plugin state exceeds the bridge limit"); return false;
    }
    bytes = QByteArray(reinterpret_cast<const char*>(raw), static_cast<qsizetype>(size));
    return true;
}
}
bool sendFrame(uint32_t type, uint32_t request, const QByteArray& payload) {
    if (payload.size() > PDPB_MAX_CONTROL_BYTES) return false;
    char header[12];
    const uint32_t fields[] = {type, request, static_cast<uint32_t>(payload.size())};
    for (unsigned field = 0; field < 3; ++field)
        for (unsigned byte = 0; byte < 4; ++byte) header[field * 4 + byte] = static_cast<char>(fields[field] >> (byte * 8));
    return std::fwrite(header, 1, sizeof(header), stdout) == sizeof(header) &&
        std::fwrite(payload.constData(), 1, payload.size(), stdout) == static_cast<size_t>(payload.size()) && std::fflush(stdout) == 0;
}
bool Host::quiesce() {
    controlPending.store(true, std::memory_order_release);
    for (;;) {
        uint32_t owner = 0;
        if (processingOwner.compare_exchange_strong(owner, 2, std::memory_order_acquire) || owner == 2) return true;
        if (stopping.load(std::memory_order_acquire)) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
}
void Host::resume() {
    controlPending.store(false, std::memory_order_release);
    processingOwner.store(0, std::memory_order_release);
}
bool Host::flushParameters() {
    if (!plugin || !plugin->handler->hasPendingEdits()) return true;
    parameterFlushRequested.store(true, std::memory_order_release);
    processingOwner.store(0, std::memory_order_release);
    while (parameterFlushRequested.load(std::memory_order_acquire)) {
        if (stopping.load(std::memory_order_acquire)) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    return parameterFlushResult == PDPH_OK;
}
void Host::enqueue(uint32_t type, uint32_t value) {
    uint32_t position = callbackWrite.load(std::memory_order_relaxed);
    for (uint32_t attempt = 0; attempt < PDPB_MAX_EVENTS; ++attempt) {
        auto& slot = callbackSlots[position % PDPB_MAX_EVENTS];
        const uint32_t sequence = slot.sequence.load(std::memory_order_acquire);
        const int32_t difference = static_cast<int32_t>(sequence - position);
        if (difference < 0) break;
        if (difference == 0 && callbackWrite.compare_exchange_weak(position, position + 1, std::memory_order_relaxed)) {
            slot.event = {type, value}; slot.sequence.store(position + 1, std::memory_order_release); return;
        }
        position = callbackWrite.load(std::memory_order_relaxed);
    }
    callbacksOverflowed.store(true, std::memory_order_relaxed);
}
void Host::drainCallbacks() {
    if (stopping.load(std::memory_order_acquire)) { QCoreApplication::quit(); return; }
    if (callbacksOverflowed.load(std::memory_order_relaxed)) {
        std::fprintf(stderr, "Plugin callback queue overflow: stream integrity lost\n");
        stop(1); return;
    }
    const auto& next = callbackSlots[callbackRead % PDPB_MAX_EVENTS];
    if (plugin && next.sequence.load(std::memory_order_acquire) == callbackRead + 1) {
        if (!quiesce()) return;
        const bool flushed = flushParameters();
        resume();
        if (!flushed) { stop(1); return; }
    }
    for (uint32_t count = 0; count < PDPB_MAX_EVENTS; ++count) {
        auto& slot = callbackSlots[callbackRead % PDPB_MAX_EVENTS];
        if (slot.sequence.load(std::memory_order_acquire) != callbackRead + 1) break;
        const auto event = slot.event;
        slot.sequence.store(callbackRead + PDPB_MAX_EVENTS, std::memory_order_release); ++callbackRead;
        QByteArray payload;
        if (event.type != PDPB_EDITOR_CLOSED) append32(payload, event.value);
        if (!sendFrame(event.type, 0, payload)) { stop(1); return; }
    }
}
void dispatch(Host& host, Frame frame) {
    if (!host.quiesce()) return;
    struct Resume { Host& host; ~Resume() { host.resume(); } } resume{host};
    Payload input = {frame.payload}; QByteArray output; QString error;
    auto operation = [&](int32_t result) { if (result != PDPH_OK) error = sdkError(result); return result == PDPH_OK; };
    const auto malformed = [&] { error = QStringLiteral("Malformed control payload"); };
    if (frame.type != PDPB_CREATE_PLUGIN && frame.type != PDPB_QUIT && frame.type != PDPB_SET_SHORTCUTS && !host.plugin) {
        reply(host, frame, {}, QStringLiteral("No plugin has been created")); return;
    }
    if ((frame.type == PDPB_GET_STATE || frame.type == PDPB_GET_STATE_DIGEST || frame.type == PDPB_SET_STATE) && !host.flushParameters()) {
        reply(host, frame, {}, QStringLiteral("Could not flush plugin parameter edits")); return;
    }
    switch (frame.type) {
    case PDPB_CREATE_PLUGIN: {
        const auto path = input.data(), uid = input.raw(16);
        if (!input.done() || path.isEmpty() || path.contains('\0')) { malformed(); break; }
        if (host.plugin || host.module) { error = QStringLiteral("This helper already hosts a plugin"); break; }
        pdph_error reason = {};
        if (pdph_module_open(path.constData(), &host.module, &reason) != PDPH_OK) { error = QString::fromUtf8(reason.message); break; }
        const pdph_host_callbacks callbacks{&host, endEdit, restart, dirty, editorClosed};
        if (pdph_plugin_create(host.module, reinterpret_cast<const uint8_t*>(uid.constData()), callbacks, &host.plugin, &reason) != PDPH_OK) {
            error = QString::fromUtf8(reason.message); pdph_module_close(host.module); host.module = nullptr; break;
        }
        pdph_bus_counts buses = {};
        if (operation(pdph_plugin_buses(host.plugin, &buses))) {
            append32(output, buses.event_in); append32(output, buses.event_out);
            append32(output, buses.audio_in); append32(output, buses.audio_out);
        }
        break;
    }
    case PDPB_SETUP_PROCESSING: {
        const auto realtime = input.u32(); const double rate = input.f64();
        const auto block = input.u32(), period = input.u32();
        if (!input.done() || realtime > 1 || !std::isfinite(rate) || rate <= 0 || !block || !period) { malformed(); break; }
        const uint32_t pluginBlock = (std::min)(block, 1024u);
        if (operation(pdph_plugin_setup_processing(host.plugin, realtime, rate, pluginBlock))) {
            host.sampleRate = rate; host.periodFrames = period;
        }
        break;
    }
    case PDPB_SET_ACTIVE:
    case PDPB_SET_PROCESSING: {
        const auto on = input.u32();
        if (!input.done() || on > 1) { malformed(); break; }
        if (frame.type == PDPB_SET_ACTIVE) operation(pdph_plugin_set_active(host.plugin, on));
        else operation(pdph_plugin_set_processing(host.plugin, on));
        break;
    }
    case PDPB_GET_STATE: {
        const auto which = input.u32();
        if (!input.done() || which > 1) { malformed(); break; }
        QByteArray bytes; if (state(host.plugin, which, bytes, error)) appendBytes(output, bytes);
        break;
    }
    case PDPB_SET_STATE: {
        const auto which = input.u32(); const auto bytes = input.data();
        if (!input.done() || which > 1) { malformed(); break; }
        operation(pdph_plugin_set_state(host.plugin, which, reinterpret_cast<const uint8_t*>(bytes.constData()), bytes.size()));
        break;
    }
    case PDPB_GET_STATE_DIGEST: {
        if (!input.done()) { malformed(); break; }
        uint64_t digest = 14695981039346656037ull;
        QByteArray bytes;
        if (state(host.plugin, 0, bytes, error)) {
            for (const auto byte : std::as_const(bytes)) { digest ^= static_cast<unsigned char>(byte); digest *= 1099511628211ull; }
        }
        if (error.isEmpty()) append64(output, digest);
        break;
    }
    case PDPB_GET_LATENCY: {
        if (!input.done()) { malformed(); break; }
        const auto latency = pdph_plugin_latency_samples(host.plugin);
        if (latency < 0) operation(latency); else append32(output, latency);
        break;
    }
    case PDPB_OPEN_EDITOR: {
        const auto title = input.data();
        if (!input.done() || title.contains('\0')) { error = QStringLiteral("Malformed editor control payload"); break; }
        pdph_editor editor = nullptr; pdph_error reason = {};
        const auto result = pdph_editor_open(host.plugin, title.constData(), &editor, &reason);
        if (result != PDPH_OK) error = QString::fromUtf8(reason.message);
        break;
    }
    case PDPB_RAISE_EDITOR:
    case PDPB_CLOSE_EDITOR:
        if (!input.done()) { error = QStringLiteral("Malformed editor control payload"); break; }
        if (frame.type == PDPB_RAISE_EDITOR) pdph_editor_raise(host.plugin->editor);
        else pdph_editor_close(host.plugin->editor);
        break;
    case PDPB_SET_SHORTCUTS: {
        const auto count = input.u32();
        if (!input.valid || count > uint32_t((PDPB_MAX_CONTROL_BYTES - 4) / 8) ||
            frame.payload.size() != 4 + qsizetype(count) * 8) {
            error = QStringLiteral("Malformed editor control payload"); break;
        }
        std::vector<int32_t> strokes; strokes.reserve(count);
        for (uint32_t index = 0; index < count; ++index) {
            const auto key = input.u32(), modifiers = input.u32();
            strokes.push_back(int32_t(key | modifiers));
        }
        if (pdph_editor_set_shortcuts(strokes.data(), int32_t(count), shortcut, &host) != PDPH_OK)
            error = QStringLiteral("Could not install editor shortcuts");
        break;
    }
    case PDPB_QUIT:
        if (!input.done()) malformed();
        break;
    default:
        error = QStringLiteral("Unknown control request"); break;
    }
    if (frame.type == PDPB_OPEN_EDITOR && error.isEmpty() && !host.flushParameters())
        error = QStringLiteral("Could not flush plugin parameter edits");
    reply(host, frame, output, error);
    if (frame.type == PDPB_QUIT && error.isEmpty()) host.stop(0);
}
}
