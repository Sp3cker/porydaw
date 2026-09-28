#pragma once

#include <QtCore/qbytearray.h>
#include <QtCore/qendian.h>
#include <QtCore/qstring.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstring>
#include <vector>

enum class RollPaletteSlot : uint16_t {
    RollBackground,
    AccidentalLane,
    ScaleHighlight,
    GridBar,
    GridBeat,
    GridSub1,
    GridSub2,
    GridSub3,
    NoteBorder,
    SelectionRing,
    SelectionFill,
    SelectionFrame,
    TimeSelectionFill,
    LoopEdge,
    LoopGlow,
    DrawPreviewFill,
    KeyboardWhite,
    KeyboardBlack,
    KeyboardSeparator,
    KeyboardHighlight,
    KeyboardLabel,
    NoteLabelLight,
    NoteLabelDark,
    PrimaryText,
    RowLine,
    GridBeatFine,
    PreRollMask,
    RulerPreRollMask,
    RulerTick,
    ChromeBackground,
    Separator,
    RulerDetailText,
    ImplicitSignature,
    NoteVelocityZero,
};
inline constexpr uint16_t rollPaletteSlotCount = uint16_t(RollPaletteSlot::NoteVelocityZero) + 1;

namespace RollContent {

constexpr uint32_t blobMagic = 0x50544452;
constexpr uint16_t blobVersion = 1;
constexpr uint64_t noTick = 0xFFFFFFFFull;
constexpr uint64_t maxTick = noTick - 1;

constexpr uint16_t sectionMetrics = 1;
constexpr uint16_t sectionFonts = 2;
constexpr uint16_t sectionPalette = 3;
constexpr uint16_t sectionRows = 4;
constexpr uint16_t sectionNotes = 5;
constexpr uint16_t sectionKeyboardNames = 6;
constexpr uint16_t sectionTimeAxis = 7;
constexpr uint16_t sectionOverlay = 8;
constexpr uint16_t sectionDrawPreview = 9;
constexpr uint16_t sectionModes = 10;

constexpr uint8_t rowAccidentalLane = 0x1;
constexpr uint8_t rowScaleHighlight = 0x2;

constexpr uint8_t noteGhost = 0x1;
constexpr uint8_t noteSelected = 0x2;
constexpr uint8_t noteTimeCovered = 0x4;

constexpr uint8_t modeNoteName = 0x2;
constexpr uint8_t modeShowVelocityValues = 0x4;
constexpr uint8_t modeTypographyAvailable = 0x8;
constexpr uint8_t modeDrumKeyboard = 0x10;

constexpr uint8_t fontRuler = 0;
constexpr uint8_t fontBeat = 1;
constexpr uint8_t fontBold = 2;
constexpr uint8_t fontSig = 3;
constexpr uint8_t fontChip = 4;
constexpr uint8_t fontKeyLabel = 5;
constexpr uint8_t fontNoteName = 6;
constexpr uint8_t fontNoteValue = 7;

struct Metrics {
    double baseFontPx = 0;
    double keyboardWidth = 0;
    double noteMinWidth = 0;
    double noteMinHeight = 0;
    double selectionRingDip = 0;
    double drawThreshold = 0;
    double detailMinPxPerBeat = 0;
    double autoGridMinCell = 0;
    double gridLineStrokeBase = 0;
    double spaceHalf = 0;
    double spaceTwo = 0;
    double dashLen = 0;
    double valueAllowance = 0;
    double rulerBeatLabelZoomFactor = 0;
    double keyLabelRightInset = 0;
};

struct FontSpec {
    uint8_t id = 0;
    int32_t pixelSize = 0;
    int32_t weight = 0;
    double letterSpacing = 0;
    QString family;

    bool operator==(const FontSpec &) const = default;
};

struct Row {
    uint8_t pitch = 0;
    uint8_t flags = 0;
};

struct Note {
    uint64_t id = 0;
    uint32_t tick = 0;
    uint32_t duration = 0;
    uint8_t pitch = 0;
    uint8_t track = 0;
    uint8_t velocity = 0;
    uint8_t flags = 0;
    uint32_t fillArgb = 0;
};

struct GridSegment {
    uint64_t start = 0;
    uint64_t next = noTick;
    uint32_t beatTicks = 0;
    uint32_t beatsPerBar = 0;
    uint32_t numerator = 0;
    uint8_t denomPow2 = 0;
    uint8_t flags = 0;
};

struct TimeAxis {
    uint8_t feel = 0;
    uint32_t clockTicks = 0;
    uint8_t selectionMode = 0;
    uint32_t musicalDenominator = 0;
    uint64_t loopStartTick = noTick;
    uint64_t loopEndTick = noTick;
    uint32_t ticksPerBeat = 0;
    std::vector<GridSegment> segments;
};

struct Overlay {
    bool active = false;
    uint64_t startTick = 0;
    uint64_t endTick = 0;
    uint32_t selectedTrack = 0;
    uint32_t usedTrackCount = 0;
    std::array<uint8_t, 32> scopeTracks{};
};

struct DrawPreview {
    bool active = false;
    uint32_t tick = 0;
    uint32_t duration = 0;
    uint8_t pitch = 0;
    uint8_t lastVelocity = 0;
};

struct Content {
    Metrics metrics;
    bool hasMetrics = false;
    std::vector<FontSpec> fonts;
    std::vector<uint32_t> palette;
    std::vector<Row> rows;
    std::array<int16_t, 128> rowOfPitch = [] {
        std::array<int16_t, 128> rows{};
        rows.fill(-1);
        return rows;
    }();
    std::vector<Note> notes;
    std::vector<uint32_t> notesByTick;
    uint32_t maxNoteDuration = 0;
    std::array<QString, 128> keyboardNames;
    bool drumMode = false;
    TimeAxis timeAxis;
    bool hasTimeAxis = false;
    Overlay overlay;
    DrawPreview drawPreview;
    uint8_t modes = 0;
    uint8_t selectedTrack = 0;

    int rowForPitch(int pitch) const
    {
        return pitch >= 0 && pitch < 128 ? int(rowOfPitch[size_t(pitch)]) : -1;
    }

    const FontSpec *font(uint8_t id) const
    {
        for (const FontSpec &spec : fonts) {
            if (spec.id == id)
                return &spec;
        }
        return nullptr;
    }

    uint32_t color(RollPaletteSlot slot) const { return palette[size_t(slot)]; }
};

class Reader
{
  public:
    Reader(const char *data, size_t size) : p(data), end(data + size) {}

    bool fail() const { return !ok; }
    size_t remaining() const { return size_t(end - p); }

    uint8_t u8()
    {
        uint8_t v = 0;
        take(&v, 1);
        return v;
    }
    uint16_t u16()
    {
        uint16_t v = 0;
        take(&v, 2);
        return qFromLittleEndian(v);
    }
    int32_t i32()
    {
        uint32_t v = 0;
        take(&v, 4);
        return int32_t(qFromLittleEndian(v));
    }
    uint32_t u32()
    {
        uint32_t v = 0;
        take(&v, 4);
        return qFromLittleEndian(v);
    }
    uint64_t u64()
    {
        uint64_t v = 0;
        take(&v, 8);
        return qFromLittleEndian(v);
    }
    double f64()
    {
        const uint64_t bits = u64();
        double v = 0;
        std::memcpy(&v, &bits, 8);
        return v;
    }
    QString utf8(size_t n)
    {
        if (remaining() < n) {
            ok = false;
            return {};
        }
        const QString v = QString::fromUtf8(p, qsizetype(n));
        p += n;
        return v;
    }
    Reader section(size_t n)
    {
        if (remaining() < n) {
            ok = false;
            return Reader(p, 0);
        }
        Reader r(p, n);
        p += n;
        return r;
    }

  private:
    void take(void *dst, size_t n)
    {
        if (remaining() < n) {
            ok = false;
            std::memset(dst, 0, n);
            return;
        }
        std::memcpy(dst, p, n);
        p += n;
    }

    const char *p;
    const char *end;
    bool ok = true;
};

inline bool decodeSection(uint16_t kind, Reader &s, Content &out)
{
    switch (kind) {
    case sectionMetrics: {
        Metrics &m = out.metrics;
        m.baseFontPx = s.f64();
        m.keyboardWidth = s.f64();
        m.noteMinWidth = s.f64();
        m.noteMinHeight = s.f64();
        m.selectionRingDip = s.f64();
        m.drawThreshold = s.f64();
        m.detailMinPxPerBeat = s.f64();
        m.autoGridMinCell = s.f64();
        m.gridLineStrokeBase = s.f64();
        m.spaceHalf = s.f64();
        m.spaceTwo = s.f64();
        m.dashLen = s.f64();
        m.valueAllowance = s.f64();
        m.rulerBeatLabelZoomFactor = s.f64();
        m.keyLabelRightInset = s.f64();
        out.hasMetrics = true;
        return true;
    }
    case sectionFonts: {
        const uint8_t count = s.u8();
        out.fonts.clear();
        out.fonts.reserve(count);
        for (int i = 0; i < count && !s.fail(); ++i) {
            FontSpec f;
            f.id = s.u8();
            f.pixelSize = s.i32();
            f.weight = s.i32();
            f.letterSpacing = s.f64();
            const uint16_t len = s.u16();
            f.family = s.utf8(len);
            out.fonts.push_back(std::move(f));
        }
        return true;
    }
    case sectionPalette: {
        const uint16_t count = s.u16();
        if (count < rollPaletteSlotCount)
            return false;
        out.palette.clear();
        out.palette.reserve(count);
        for (int i = 0; i < count && !s.fail(); ++i)
            out.palette.push_back(s.u32());
        return true;
    }
    case sectionRows: {
        const uint16_t count = s.u16();
        if (count > 128)
            return false;
        out.rows.clear();
        out.rows.reserve(count);
        out.rowOfPitch.fill(-1);
        for (int i = 0; i < count && !s.fail(); ++i) {
            Row r;
            r.pitch = s.u8();
            r.flags = s.u8();
            if (r.pitch >= 128)
                return false;
            out.rowOfPitch[r.pitch] = int16_t(i);
            out.rows.push_back(r);
        }
        return true;
    }
    case sectionNotes: {
        const uint32_t count = s.u32();
        if (size_t(count) > s.remaining() / 24)
            return false;
        out.notes.clear();
        out.notes.reserve(count);
        out.notesByTick.resize(count);
        out.maxNoteDuration = 0;
        for (uint32_t i = 0; i < count; ++i) {
            Note n;
            n.id = s.u64();
            n.tick = s.u32();
            n.duration = s.u32();
            n.pitch = s.u8();
            n.track = s.u8();
            n.velocity = s.u8();
            n.flags = s.u8();
            n.fillArgb = s.u32();
            out.notes.push_back(n);
            out.notesByTick[i] = i;
            out.maxNoteDuration = std::max(out.maxNoteDuration, n.duration);
        }
        std::stable_sort(out.notesByTick.begin(), out.notesByTick.end(),
                         [&notes = out.notes](uint32_t a, uint32_t b) {
                             return notes[a].tick < notes[b].tick;
                         });
        return true;
    }
    case sectionKeyboardNames: {
        const uint16_t count = s.u16();
        out.keyboardNames.fill(QString());
        for (int i = 0; i < count && !s.fail(); ++i) {
            const uint8_t pitch = s.u8();
            const uint16_t len = s.u16();
            QString name = s.utf8(len);
            if (pitch >= 128)
                return false;
            out.keyboardNames[pitch] = std::move(name);
        }
        return true;
    }
    case sectionTimeAxis: {
        TimeAxis &t = out.timeAxis;
        t.feel = s.u8();
        t.clockTicks = s.u32();
        t.selectionMode = s.u8();
        t.musicalDenominator = s.u32();
        t.loopStartTick = s.u64();
        t.loopEndTick = s.u64();
        const uint16_t segmentCount = s.u16();
        if (segmentCount == 0)
            return false;
        t.segments.clear();
        t.segments.reserve(segmentCount);
        for (int i = 0; i < segmentCount && !s.fail(); ++i) {
            GridSegment g;
            g.start = s.u64();
            g.next = s.u64();
            g.beatTicks = s.u32();
            g.beatsPerBar = s.u32();
            g.numerator = s.u32();
            g.denomPow2 = s.u8();
            g.flags = s.u8();
            const bool last = i + 1 == segmentCount;
            const uint64_t expectedStart = t.segments.empty() ? 0 : t.segments.back().next;
            if (g.beatTicks == 0 || g.beatsPerBar == 0 || g.start != expectedStart
                || (last ? g.next != noTick : g.next <= g.start))
                return false;
            t.segments.push_back(g);
        }
        t.ticksPerBeat = s.u32();
        if (t.ticksPerBeat == 0)
            return false;
        out.hasTimeAxis = true;
        return true;
    }
    case sectionOverlay: {
        Overlay &o = out.overlay;
        o.active = s.u8() != 0;
        o.startTick = s.u64();
        o.endTick = s.u64();
        o.selectedTrack = s.u32();
        o.usedTrackCount = s.u32();
        for (uint8_t &scope : o.scopeTracks)
            scope = s.u8();
        return true;
    }
    case sectionDrawPreview: {
        DrawPreview &d = out.drawPreview;
        d.active = s.u8() != 0;
        d.tick = s.u32();
        d.duration = s.u32();
        d.pitch = s.u8();
        d.lastVelocity = s.u8();
        return true;
    }
    case sectionModes:
        out.modes = s.u8();
        out.selectedTrack = s.u8();
        out.drumMode = out.modes & modeDrumKeyboard;
        return true;
    default:
        return true;
    }
}

inline bool decode(const QByteArray &blob, Content &out)
{
    out = Content{};
    if (blob.isEmpty())
        return true;
    Reader r(blob.constData(), size_t(blob.size()));
    if (r.u32() != blobMagic || r.u16() != blobVersion)
        return false;
    const uint16_t sectionCount = r.u16();
    for (uint16_t i = 0; i < sectionCount; ++i) {
        const uint16_t kind = r.u16();
        const uint32_t length = r.u32();
        Reader s = r.section(length);
        if (r.fail() || !decodeSection(kind, s, out) || s.fail())
            return false;
    }
    return !r.fail() && (!out.hasMetrics || out.palette.size() >= rollPaletteSlotCount);
}

} // namespace RollContent
