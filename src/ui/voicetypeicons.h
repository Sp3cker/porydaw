#pragma once

// The voice-type cell icons' single canonical home: the glyph each VOICE_*
// type byte maps to, the alt-chip flag, and the one SourceIn tint pipeline
// (theme-inked Normal/Selected/Disabled pixmaps, with the grey alt chip and
// the 180-degree reverse-sample flip composed on top). The voicegroup
// browser's Type column is the only consumer; nothing else may grow a
// parallel tint implementation for these glyphs.

#include <QIcon>
#include <QSize>
#include <QString>

extern "C" {
#include "voicegroup_loader.h"
}

#include "ui/theme/themeruntime.h"

namespace voicetypeicons {

// The Type column's per-type glyphs. Alt CGB variants (0x09-0x0C) reuse the
// family glyph on a grey chip; the reverse DirectSound reuses the sample
// waveform rotated 180 degrees.
enum class Glyph { Sample, SampleReverse, Square1, Square2, Wave, Noise, Keysplit, Drumkit };

// Icon-cache key: the glyph plus its alt-chip flag.
constexpr int iconKey(Glyph glyph, bool altChip)
{
    return int(glyph) * 2 + int(altChip);
}

// A type glyph tinted for the item view: Normal/Selected follow the row's
// text ink, Disabled the disabled text. altChip paints a grey chip
// (secondary_text at partial alpha) behind the glyph, which is then inked in
// the item-surface color so it reads inverted. rotate180 flips the finished
// pixmap (the reverse-sample waveform).
QIcon tinted(const QString &svgPath, const QSize &size, qreal dpr, bool altChip, bool rotate180);

// The glyph a raw voice-type byte maps to, shared by the macro path
// (vgMacroVoiceType) and the loaded-bank ToneData path. The alt CGB variants
// (0x09-0x0C) share their family's glyph — the chip flag comes from
// isAltChip, not here. synth (a Golden Sun zero-size wav descriptor, or a
// voice whose symbol resolves to one) reads as a sample; cry types
// (0x20/0x30) and unknowns fall through to Sample as well.
inline Glyph forTypeByte(uint8_t type, bool synth)
{
    if (synth)
        return Glyph::Sample;
    switch (type) {
    case VOICE_KEYSPLIT:
        return Glyph::Keysplit;
    case VOICE_KEYSPLIT_ALL:
        return Glyph::Drumkit;
    case VOICE_DIRECTSOUND_ALT:
        return Glyph::SampleReverse;
    }
    switch (type & VOICE_TYPE_CGB_MASK) {
    case VOICE_SQUARE_1:
        return Glyph::Square1;
    case VOICE_SQUARE_2:
        return Glyph::Square2;
    case VOICE_PROGRAMMABLE_WAVE:
        return Glyph::Wave;
    case VOICE_NOISE:
        return Glyph::Noise;
    default:
        return Glyph::Sample;
    }
}

// Whether the type byte is an alt CGB variant (0x09-0x0C): those render their
// family glyph on a grey chip.
inline bool isAltChip(uint8_t type)
{
    return (type & VOICE_TYPE_FIX) != 0 && (type & VOICE_TYPE_CGB_MASK) != 0;
}

// Glyph -> source fileloop: the table rebuildTypeIcons iterates, so the
// file mapping lives here with the rest of the icon contract instead of in
// the browser.
struct IconSpec {
    Glyph glyph;
    bool altChip;
    const char *svg;
    bool rotate180;
};
inline constexpr IconSpec kIconSpecs[] = {
    {Glyph::Sample, false, "waveform.svg", false},
    {Glyph::SampleReverse, false, "waveform.svg", true},
    {Glyph::Square1, false, "wave-square.svg", false},
    {Glyph::Square1, true, "wave-square.svg", false},
    {Glyph::Square2, false, "wave-triangle.svg", false},
    {Glyph::Square2, true, "wave-triangle.svg", false},
    {Glyph::Wave, false, "wave-sine.svg", false},
    {Glyph::Wave, true, "wave-sine.svg", false},
    {Glyph::Noise, false, "waveform-path.svg", false},
    {Glyph::Noise, true, "waveform-path.svg", false},
    {Glyph::Keysplit, false, "piano-keyboard.svg", false},
    {Glyph::Drumkit, false, "drum.svg", false},
};

} // namespace voicetypeicons
