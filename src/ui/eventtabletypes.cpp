#include "eventtabletypes.h"
#include "eventlistview.h"

#include <QRegularExpression>
#include <algorithm>

#include "core/smf.h"
#include "ui/m4asemantics.h"
#include "ui/songview.h"

namespace eventlist {

namespace {

constexpr int kBlobDisplayBytes = 64;

QString metaName(uint8_t metaType)
{
    switch (metaType) {
    case 0x00:
        return EventListView::tr("Sequence number");
    case 0x01:
        return EventListView::tr("Text");
    case 0x02:
        return EventListView::tr("Copyright");
    case 0x03:
        return EventListView::tr("Track name");
    case 0x04:
        return EventListView::tr("Instrument");
    case 0x05:
        return EventListView::tr("Lyric");
    case 0x06:
        return EventListView::tr("Marker");
    case 0x07:
        return EventListView::tr("Cue point");
    case 0x20:
        return EventListView::tr("Channel prefix");
    case 0x21:
        return EventListView::tr("MIDI port");
    case 0x51:
        return EventListView::tr("Tempo");
    case 0x54:
        return EventListView::tr("SMPTE offset");
    case 0x58:
        return EventListView::tr("Time signature");
    case 0x59:
        return EventListView::tr("Key signature");
    case 0x7F:
        return EventListView::tr("Sequencer-specific");
    default:
        return EventListView::tr("Meta 0x%1").arg(metaType, 2, 16, QLatin1Char('0'));
    }
}

QString metaSummary(const SmfEvent &ev)
{
    const QString name = metaName(ev.metaType);
    if (ev.metaType == 0x58 && ev.blob.size() >= 2) {
        return EventListView::tr("Time signature %1")
            .arg(midiTimeSigLabel(uint8_t(ev.blob[0]), uint8_t(ev.blob[1])));
    }
    if (ev.metaType >= 0x01 && ev.metaType <= 0x07) {
        QString text = QStringLiteral("%1 %2").arg(name, blobDisplayText(ev));
        if (metaIsLoopMarker(ev, '['))
            text += EventListView::tr(" — loop start");
        else if (metaIsLoopMarker(ev, ']'))
            text += EventListView::tr(" — loop end");
        return text;
    }
    return name;
}

} // namespace

int typeKindOf(const SmfEvent &ev)
{
    if (ev.isMeta())
        return TypeMeta;
    if (ev.status == 0xF0)
        return TypeSysEx0;
    if (ev.status == 0xF7)
        return TypeSysEx7;
    switch (ev.typeNibble()) {
    case 0x8:
        return TypeNoteOff;
    case 0x9:
        return TypeNoteOn;
    case 0xA:
        return TypePolyTouch;
    case 0xB:
        return TypeCc;
    case 0xC:
        return TypeProgram;
    case 0xD:
        return TypeChanTouch;
    default:
        return TypeBend;
    }
}

QString typeKindName(int kind)
{
    switch (kind) {
    case TypeNoteOff:
        return EventListView::tr("Note off");
    case TypeNoteOn:
        return EventListView::tr("Note on");
    case TypePolyTouch:
        return EventListView::tr("Poly aftertouch");
    case TypeCc:
        return EventListView::tr("Control change");
    case TypeProgram:
        return EventListView::tr("Program change");
    case TypeChanTouch:
        return EventListView::tr("Channel aftertouch");
    case TypeBend:
        return EventListView::tr("Pitch bend");
    case TypeSysEx0:
        return QStringLiteral("SysEx (F0)");
    case TypeSysEx7:
        return QStringLiteral("SysEx (F7)");
    case TypeTempo:
        return EventListView::tr("Tempo");
    default:
        return EventListView::tr("Meta");
    }
}

bool hasData2(int kind)
{
    switch (kind) {
    case TypeNoteOff:
    case TypeNoteOn:
    case TypePolyTouch:
    case TypeCc:
    case TypeBend:
        return true;
    default:
        return false;
    }
}

QString blobText(const SmfEvent &ev)
{
    if (ev.isMeta() && ev.metaType >= 0x01 && ev.metaType <= 0x07 && !ev.blob.isEmpty()) {
        const bool printable = std::all_of(ev.blob.begin(), ev.blob.end(), [](char c) {
            return uint8_t(c) >= 0x20 && uint8_t(c) < 0x7F;
        });
        if (printable)
            return QStringLiteral("\"%1\"").arg(QString::fromLatin1(ev.blob));
    }
    return QString::fromLatin1(ev.blob.toHex(' ')).toUpper();
}

QString blobDisplayText(const SmfEvent &ev)
{
    if (ev.blob.size() <= kBlobDisplayBytes)
        return blobText(ev);
    return EventListView::tr("%1 … (%2 bytes)")
        .arg(QString::fromLatin1(ev.blob.left(kBlobDisplayBytes).toHex(' ')).toUpper())
        .arg(ev.blob.size());
}

bool parseBlob(const QString &input, QByteArray *out)
{
    const QString text = input.trimmed();
    if (text.size() >= 2 && text.startsWith(QLatin1Char('"')) && text.endsWith(QLatin1Char('"'))) {
        *out = text.mid(1, text.size() - 2).toUtf8();
        return true;
    }
    QString hex = text;
    hex.remove(QLatin1Char(' '));
    hex.remove(QLatin1Char(','));
    static const QRegularExpression hexOnly(QStringLiteral("^([0-9A-Fa-f]{2})*$"));
    if (!hexOnly.match(hex).hasMatch())
        return false;
    *out = QByteArray::fromHex(hex.toLatin1());
    return true;
}

QString summaryText(const SmfEvent &ev, SongView *sv)
{
    switch (typeKindOf(ev)) {
    case TypeNoteOn:
        if (ev.data1 == 0)
            return EventListView::tr("Note off %1 (velocity-0 note-on)").arg(midiKeyName(ev.data0));
        return EventListView::tr("Note on %1, velocity %2")
            .arg(midiKeyName(ev.data0))
            .arg(ev.data1);
    case TypeNoteOff:
        return EventListView::tr("Note off %1").arg(midiKeyName(ev.data0));
    case TypePolyTouch:
        return EventListView::tr("Poly aftertouch %1 = %2")
            .arg(midiKeyName(ev.data0))
            .arg(ev.data1);
    case TypeCc: {
        const M4aCcInfo info = m4aClassifyCc(ev.data0);
        return EventListView::tr("CC %1 %2 = %3")
            .arg(ev.data0)
            .arg(QLatin1String(info.display), m4aFormatCcValue(ev.data0, ev.data1));
    }
    case TypeProgram: {
        QString name = sv ? sv->voiceShortName(ev.data0) : QString();
        if (name == EventListView::tr("Voice"))
            name.clear();
        return name.isEmpty() ? EventListView::tr("Voice %1").arg(ev.data0)
                              : EventListView::tr("Voice %1 — %2").arg(ev.data0).arg(name);
    }
    case TypeChanTouch:
        return EventListView::tr("Channel aftertouch = %1").arg(ev.data0);
    case TypeBend:
        return EventListView::tr("Pitch bend %1")
            .arg(m4aFormatBend(int((ev.data1 << 7) | ev.data0) - 8192));
    case TypeSysEx0:
    case TypeSysEx7:
        return EventListView::tr("%n payload byte(s)", nullptr, int(ev.blob.size()));
    default:
        return metaSummary(ev);
    }
}

SmfEvent retyped(const SmfEvent &ev, int kind, uint8_t fallbackChannel)
{
    SmfEvent next = ev;
    const auto toChannel = [&](uint8_t nibble) {
        const uint8_t channel = ev.isChannel() ? ev.channel() : fallbackChannel;
        next.status = uint8_t((nibble << 4) | (channel & 0x0F));
        next.metaType = 0;
        next.blob.clear();
    };
    switch (kind) {
    case TypeNoteOff:
        toChannel(0x8);
        break;
    case TypeNoteOn:
        toChannel(0x9);
        break;
    case TypePolyTouch:
        toChannel(0xA);
        break;
    case TypeCc:
        toChannel(0xB);
        break;
    case TypeProgram:
        toChannel(0xC);
        next.data1 = 0;
        break;
    case TypeChanTouch:
        toChannel(0xD);
        next.data1 = 0;
        break;
    case TypeBend:
        toChannel(0xE);
        break;
    case TypeSysEx0:
    case TypeSysEx7:
        next.status = kind == TypeSysEx0 ? 0xF0 : 0xF7;
        next.metaType = 0;
        next.data0 = next.data1 = 0;
        if (ev.isChannel())
            next.blob.clear();
        break;
    case TypeMeta:
        next.status = 0xFF;
        next.data0 = next.data1 = 0;
        if (!ev.isMeta()) {
            next.metaType = 0x06;
            if (ev.isChannel())
                next.blob.clear();
        }
        break;
    default:
        break;
    }
    return next;
}

} // namespace eventlist
