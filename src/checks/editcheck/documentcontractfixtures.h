#pragma once

#include <QByteArray>

#include <cstdint>

#include "core/smf.h"

namespace editcheck::documentcontract {

inline SmfEvent channel(uint8_t status, uint64_t tick, uint8_t data0, uint8_t data1)
{
    SmfEvent event;
    event.tick = tick;
    event.status = status;
    event.data0 = data0;
    event.data1 = data1;
    return event;
}

inline SmfEvent meta(uint8_t type, uint64_t tick, const QByteArray &blob)
{
    SmfEvent event;
    event.tick = tick;
    event.status = 0xFF;
    event.metaType = type;
    event.blob = blob;
    return event;
}

inline SmfTrack conductor()
{
    SmfTrack track;
    SmfEvent text;
    text.status = 0xFF;
    text.metaType = 0x01;
    text.blob = QByteArrayLiteral("contract fixture");
    track.events.push_back(text);
    track.endTick = 48;
    return track;
}

} // namespace editcheck::documentcontract
