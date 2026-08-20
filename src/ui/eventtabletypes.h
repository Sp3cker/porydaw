#pragma once

#include <cstdint>

#include <QByteArray>
#include <QString>

struct SmfEvent;
class SongView;

namespace eventlist {

enum TypeKind {
    TypeNoteOff,
    TypeNoteOn,
    TypePolyTouch,
    TypeCc,
    TypeProgram,
    TypeChanTouch,
    TypeBend,
    TypeSysEx0,
    TypeSysEx7,
    TypeTempo,
    TypeMeta,
    TypeKindCount
};

int typeKindOf(const SmfEvent &ev);
QString typeKindName(int kind);
bool hasData2(int kind);
QString blobText(const SmfEvent &ev);
QString blobDisplayText(const SmfEvent &ev);
bool parseBlob(const QString &input, QByteArray *out);
QString summaryText(const SmfEvent &ev, SongView *sv);
SmfEvent retyped(const SmfEvent &ev, int kind, uint8_t fallbackChannel);

} // namespace eventlist
