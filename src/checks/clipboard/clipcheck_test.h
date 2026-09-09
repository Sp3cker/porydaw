#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include <QObject>
#include <QString>
#include <Qt>

#include "checks/clipcheck_support.h"
#include "checks/support/editorrig.h"

#include "core/noteid.h"

extern "C" {
#include "voicegroup_loader.h"
}

class QTemporaryDir;
class SongDocument;
class SongTab;
class SongView;

namespace songview {
class TimelineInputItem;
}

namespace checks::clipboard {

struct NoteSpec {
    uint64_t tick = 0;
    uint8_t key = 0;
    uint32_t duration = 0;
    uint8_t velocity = 0;

    bool operator==(const NoteSpec &) const = default;
};

struct LaneSpec {
    uint64_t tick = 0;
    int value = 0;

    bool operator==(const LaneSpec &) const = default;
};

struct TempoSpec {
    uint64_t tick = 0;
    uint32_t microsecondsPerQuarterNote = 0;

    bool operator==(const TempoSpec &) const = default;
};

class ClipTabRig final
{
  public:
    static std::unique_ptr<ClipTabRig> create(uint16_t ticksPerBeat, QString &error);
    ~ClipTabRig();

    ClipTabRig(const ClipTabRig &) = delete;
    ClipTabRig &operator=(const ClipTabRig &) = delete;

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    bool sendRollKey(int key, Qt::KeyboardModifiers modifiers);
    bool sendViewKey(int key, Qt::KeyboardModifiers modifiers);

  private:
    ClipTabRig();

    std::unique_ptr<QTemporaryDir> m_temporary;
    std::unique_ptr<LoadedVoiceGroup> m_bank;
    std::unique_ptr<SongTab> m_tab;
    // Borrows m_tab->view(), so it must be released before the session.
    std::unique_ptr<checks::QuickSceneHost> m_sceneHost;
    songview::TimelineInputItem *m_roll = nullptr;
};

std::vector<NoteSpec> notesOf(const SongDocument &document, int engineTrack);
std::vector<LaneSpec> lanesOf(const SongDocument &document, int engineTrack, uint8_t cc);
std::vector<TempoSpec> tempoOf(const SongDocument &document);
std::vector<NoteId> noteIds(const SongDocument &document, int engineTrack);

class ClipCheckTest final : public QObject
{
    Q_OBJECT

  public:
    ClipCheckTest() = default;
    Q_DISABLE_COPY_MOVE(ClipCheckTest)

  private slots:
    void init();
    void cleanup();

    void crossTpbNotePaste();
    void mergeTimeRangeAndUndo();
    void emptyLaneMergeIsNoop();
    void tiledTimePasteUndoesOneTileAtATime();

    void crossViewNoteCopyPaste();
    void sameViewNoteCopyPaste();
    void songViewEditKeyPaste();
    void timeSelectionCopy();
    void scopedRangeCopyPasteCreatesTracks();
    void rangeDeleteCutAndUndo();

  private:
    std::unique_ptr<clipcheck_support::ClipboardStateGuard> m_clipboard;
};

} // namespace checks::clipboard
