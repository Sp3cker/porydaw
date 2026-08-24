#pragma once

#include <QByteArray>
#include <QHash>
#include <QPair>
#include <QString>
#include <QStringList>
#include <QVector>
#include <optional>

extern "C" {
#include "voicegroup/voicegroup_loader.h"
}

// The editable voice macros: the five basic families and their variants,
// plus voice_keysplit (whose sub-voicegroup/table pair is swappable) and
// voice_keysplit_all (drumkit; its sub-voicegroup is swappable). Cry voices
// stay read-only and round-trip verbatim.
enum class VgMacro {
    DirectSound,
    DirectSoundNoResample,
    DirectSoundAlt,
    Square1,
    Square1Alt,
    Square2,
    Square2Alt,
    ProgWave,
    ProgWaveAlt,
    Noise,
    NoiseAlt,
    Keysplit,
    KeysplitAll,
};

QString vgMacroName(VgMacro macro);        // the .inc macro word
QString vgMacroDisplayName(VgMacro macro); // UI label
uint8_t vgMacroVoiceType(VgMacro macro);   // matching VOICE_* constant
bool vgMacroHasSymbol(VgMacro macro);      // DirectSound/ProgWave sample arg
bool vgMacroIsCgb(VgMacro macro);          // CGB ADSR ranges (A/D/R 0-7, S 0-15)

// One editable voice's parsed macro arguments, exactly as written in the file
// (unpacked: pan/duty/period/sweep are the raw macro args, not the ToneData
// encodings).
struct VgVoice {
    VgMacro macro = VgMacro::DirectSound;
    int key = 60;
    int pan = 0;
    QString symbol; // DirectSound sample / programmable-wave / keysplit or drumkit sub-voicegroup
    QString keysplitTable; // keysplit only
    int sweep = 0;         // square_1 only
    int duty = 2;          // square_1/2 only
    int period = 0;        // noise only
    int attack = 0;
    int decay = 0;
    int sustain = 0;
    int release = 0;

    bool operator==(const VgVoice &) const = default;
};

// A value draft for editing a slot. None slots use the caller's blank
// template and are marked so callers can preserve materialization semantics.
struct VgVoiceDraft {
    VgVoice voice;
    bool materializesBlank = false;
};

// One ADSR envelope, in the raw macro-argument scale of its voice family
// (CGB: A/D/R 0-7, S 0-15; DirectSound: 0-255 each).
struct VgAdsr {
    int attack = 0;
    int decay = 0;
    int sustain = 0;
    int release = 0;

    bool operator==(const VgAdsr &) const = default;
};

// The envelope family a macro's ADSR values belong to: the _alt/no_resample
// variants collapse onto their base macro (identical envelope semantics).
// -1 for keysplit/drumkit voices, which carry no envelope of their own.
int vgAdsrFamily(VgMacro macro);

// One Golden Sun synth instrument (ipatix improved-mixer feature): a
// DirectSound voice whose "sample" has size 0 and whose data bytes select a
// synthesized waveform instead of PCM. Pulse carries a duty-cycle LFO;
// saw/triangle take no parameters (see parse_synth_macro_line and the
// M4A_SYNTH_* notes in external/poryaaaa/plugin).
struct VgSynthDesc {
    int waveform = 0;    // 0 = pulse, 1 = pseudo-saw, 2 = triangle
    int baseDuty = 0x80; // pulse only: duty threshold (0x80 = 50% square)
    int dutyStep = 0;    // pulse only: duty LFO advance per frame
    int modDepth = 0;    // pulse only: LFO swing around the base duty
    int phase = 0;       // pulse only: duty LFO phase offset

    bool operator==(const VgSynthDesc &o) const
    {
        if (waveform != o.waveform)
            return false;
        return waveform != 0 || (baseDuty == o.baseDuty && dutyStep == o.dutyStep &&
                                 modDepth == o.modDepth && phase == o.phase);
    }
    bool operator!=(const VgSynthDesc &o) const { return !(*this == o); }
};

// Waveform label ("Pulse", "Sawtooth", "Triangle").
QString vgSynthWaveformName(int waveform);

// The canonical param-named symbol for a descriptor
// ("DirectSoundSynth_GoldenSun_<params>" / "_Saw" / "_Triangle"), before any
// collision suffixing.
QString vgSynthSymbolName(const VgSynthDesc &desc);

// The project's Golden Sun synth instruments: every set_synth_* definition in
// the sound data files (file order), plus which set_synth_* assembler macros
// the project defines. An empty macro list means new definitions can't be
// written — they wouldn't assemble (the mixer support ships with the macros).
struct VgSynthCatalog {
    QList<QPair<QString, VgSynthDesc>> defs;
    QStringList macroWords;

    bool available() const { return !defs.isEmpty() || !macroWords.isEmpty(); }
    bool creatable() const { return !macroWords.isEmpty(); }
    const VgSynthDesc *find(const QString &symbol) const;
    QString symbolFor(const VgSynthDesc &desc) const; // "" when none matches
};

// The most common envelopes observed across a project's voicegroups, keyed
// by instrument symbol and by envelope family. Silent or clicking envelopes
// never qualify, so a hit is always audible.
struct VgAdsrDefaults {
    QHash<QString, VgAdsr> bySymbol; // DirectSound sample / prog-wave symbol
    QHash<int, VgAdsr> byFamily;     // vgAdsrFamily() key
};

// The envelope a voice should adopt when it switches into a new envelope
// family, or picks a new instrument symbol while its envelope is untouched:
// the project-typical envelope for its instrument symbol, then for its
// family, then a full-sustain fallback with a short release tail (an
// instant release-0 cutoff clicks audibly).
VgAdsr vgDefaultAdsr(const VgAdsrDefaults &defaults, VgMacro macro, const QString &symbol);

// A voice edit is "structural" when audio can't be updated by poking scalar
// ToneData fields: the macro (voice type) or a sample/wave symbol changed, so
// the caller must reload the voicegroup from rendered source instead.
bool vgVoiceStructuralChange(const VgVoice &before, const VgVoice &after);

enum class VgLineKind {
    None,          // slot has no source line (past the file's last voice)
    Other,         // comment / label / directive — verbatim
    Header,        // voice_group NAME[, startingNote]
    Editable,      // one of the VgMacro macros, args parsed OK
    ReadOnlyVoice, // cry / cry_reverse
    Broken,        // recognized macro prefix but unparseable args — verbatim
};

// Source-of-truth model for one voicegroup: the .inc file's lines with the
// loader's slot accounting, byte-conservative editing of the editable voice
// lines, and re-rendering for save or for pre-save audition.
// Saving remains rooted in this text model: ToneData is a runtime materialization
// and does not preserve source formatting.
class VoicegroupSource
{
  public:
    // Opens the snapshot-provided source file and verifies that it declares
    // canonicalSymbol. Files with multiple declarations are edited as the
    // matching labelled section; no other project files are probed.
    bool open(const QString &projectRoot, const QString &sourcePath, const QString &loadName,
              const QString &canonicalSymbol, QString *error);
    // Re-reads the located file from disk, dropping all unsaved edits.
    bool reload(QString *error);

    QString filePath() const { return m_filePath; }
    QString sourcePath() const { return m_sourcePath; }
    // The name used to resolve this voicegroup in the project snapshot.
    QString loadName() const { return m_loadName; }
    bool monolithic() const { return !m_sectionLabel.isEmpty(); }
    QString sectionLabel() const { return m_sectionLabel; }

    VgLineKind kindAt(int slot) const;
    bool isEditable(int slot) const { return kindAt(slot) == VgLineKind::Editable; }
    const VgVoice *voiceAt(int slot) const;
    // Returns the existing editable voice or the supplied template for an
    // undefined slot. Invalid, read-only, and broken slots have no draft.
    std::optional<VgVoiceDraft> voiceDraft(int slot, const VgVoice &blankTemplate) const;
    // Rewrites an existing voice, or materializes a previously undefined
    // slot. New sparse entries use the voice_group starting-note convention
    // and silent square-wave padding so existing voice slots stay fixed.
    bool setVoice(int slot, const VgVoice &voice);
    // Full in-memory source state for structural undo. Restoring bytes leaves
    // the current save baseline unchanged, so dirty() still reflects disk.
    QByteArray sourceBytes() const;
    bool restoreSourceBytes(const QByteArray &bytes);
    bool dirty() const { return m_dirty; }

    // Writes the whole file back; only edited voice lines differ from the
    // bytes read at open/reload time.
    bool save(QString *error);

    // The edited source as a standalone parseable file: the whole buffer for
    // a per-file voicegroup, the section slice for a monolithic one.
    QByteArray renderPreview() const;

    // Pushes the slot's scalar fields into a loaded ToneData using the C
    // loader's packing, for live audition without a reload. Returns false
    // when the voice needs a structural reload instead (type mismatch).
    bool applyScalarsToToneData(int slot, ToneData *td) const;

    // Appends pending Golden Sun synth definitions to
    // sound/direct_sound_synth_data.inc. Existing equal definitions are
    // reused; conflicting symbols or projects without set_synth_* macros
    // refuse the write.
    static bool writeSynthDefinitions(const QString &projectRoot,
                                      const QList<QPair<QString, VgSynthDesc>> &defs,
                                      QString *error);
    // Writes sound/voicegroups/<name>.inc matching the siblings' header style
    // and line endings. copyFromFile/copySectionLabel name an existing
    // voicegroup to copy the voice lines from; empty means the 128-slot dummy
    // template. Requires the per-file layout (sound/voicegroups/ exists).
    static bool createVoicegroup(const QString &projectRoot, const QString &name,
                                 const QString &copyFromFile, const QString &copySectionLabel,
                                 QString *error);
    // Appends .include "sound/voicegroups/<name>.inc" after the last .include
    // in sound/voice_groups.inc (byte-conservative; no-op if the hub file
    // doesn't exist — the loader and browser discover the file regardless).
    static bool appendIncludeLine(const QString &projectRoot, const QString &name, QString *error);
    // The inverse pair, for deleting a song's now-unused voicegroup: drops
    // the hub's .include line (no-op when absent), then the .inc file itself.
    // Idempotent — an already-deleted voicegroup is a success.
    static bool removeIncludeLine(const QString &projectRoot, const QString &name, QString *error);
    static bool deleteVoicegroup(const QString &projectRoot, const QString &name, QString *error);

  private:
    struct Line {
        QByteArray raw; // original bytes, no '\n', trailing '\r' kept
        VgLineKind kind = VgLineKind::Other;
        int slot = -1;
        VgVoice voice; // valid when kind == Editable
        // Editable-line formatting, captured for faithful re-rendering:
        QByteArray indent;             // leading whitespace
        QByteArray macroText;          // macro word incl. any trailing space
        QVector<QByteArray> argPieces; // between-comma pieces, whitespace kept
        QByteArray tail;               // trailing whitespace + comment
    };
    struct SlotSpan {
        int first = VOICEGROUP_SIZE;
        int last = -1;

        bool empty() const { return last < 0; }
    };
    struct BlankSlotInsertion {
        int insertionIndex = -1;
        int headerIndex = -1;
        int headerStartingSlot = -1;
        QVector<Line> additions;
    };

    SlotSpan discoverSlotSpan() const;
    int discoverHeaderIndex() const;
    Line generatedVoiceLine(int slot, const VgVoice &voice) const;
    static VgVoice silentPaddingVoice();
    void rewriteHeaderStartingSlot(int headerIndex, int startingSlot);
    bool buildBlankSlotInsertion(int slot, const VgVoice &voice,
                                 BlankSlotInsertion *insertion) const;
    void applyBlankSlotInsertion(const BlankSlotInsertion &insertion);

    bool parse(const QByteArray &content, QString *error);
    void rebuildSlotToLine();
    QByteArray lineEnding() const;
    void renderLine(Line &line) const;
    bool matchesPristineSource() const;

    QString m_projectRoot;
    QString m_sourcePath;
    QString m_filePath;
    QString m_sectionLabel; // empty = per-file layout
    QString m_loadName;
    QVector<Line> m_lines;
    int m_slotToLine[VOICEGROUP_SIZE];
    int m_sectionBegin = 0; // line index of the label line (0 for per-file)
    int m_sectionEnd = 0;   // exclusive
    bool m_endsWithNewline = true;
    // Full-file bytes at open/reload or the last save. A source insertion can
    // add/remove lines, so per-line pristine state is not sufficient.
    QByteArray m_pristineSource;
    bool m_dirty = false;
};
