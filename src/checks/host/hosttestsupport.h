#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

#include "ui/songview/quick/timelinequickview.h"
#include <QCoreApplication>
#include <QPointer>
#include <QTemporaryDir>

#include "checks/support/editorrig.h"
#include "core/miditimeline.h"
#include "core/smf.h"
#include "core/songdocument.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editorviewstate.h"
#include "ui/songview.h"

namespace checks::host {

// Declare after attachment so borrowed windows and engines outlive scene teardown.
class SceneDetachGuard final
{
  public:
    explicit SceneDetachGuard(songview::TimelineQuickView &quick) : m_quick(&quick) {}
    ~SceneDetachGuard()
    {
        if (m_quick)
            m_quick->detachScene();
    }
    SceneDetachGuard(const SceneDetachGuard &) = delete;
    SceneDetachGuard &operator=(const SceneDetachGuard &) = delete;

  private:
    QPointer<songview::TimelineQuickView> m_quick;
};

inline SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

inline bool automationRowsEqual(const std::vector<AutomationRow> &left,
                                const std::vector<AutomationRow> &right)
{
    return left.size() == right.size() &&
           std::equal(left.cbegin(), left.cend(), right.cbegin(),
                      [](const AutomationRow &leftRow, const AutomationRow &rightRow) {
                          return leftRow.id == rightRow.id;
                      });
}

class SyntheticHost final
{
  public:
    explicit SyntheticHost(bool includeLongTail = false)
    {
        m_smf.format = 1;
        m_smf.division = 24;
        SmfTrack primary;
        primary.events = {
            noteEvent(0xC0, 0, 0, 0),  noteEvent(0x90, 12, 60, 20), noteEvent(0x90, 12, 60, 70),
            noteEvent(0xC0, 24, 1, 0), noteEvent(0x80, 36, 60, 0),  noteEvent(0x80, 36, 60, 0),
        };
        primary.endTick = 36;
        if (includeLongTail) {
            primary.events.push_back(noteEvent(0xB0, 24000, 1, 0));
            primary.endTick = 24000;
        }
        SmfTrack secondary;
        secondary.events = {noteEvent(0x91, 12, 67, 80), noteEvent(0x81, 36, 67, 0)};
        secondary.endTick = 36;
        m_smf.tracks = {primary, secondary};
        m_song.label = QStringLiteral("host-adapter");
        m_song.midPath = m_temporary.path() + QStringLiteral("/host-adapter.mid");
        m_song.hasMid = true;
        m_bank.voices[0].type = VOICE_SQUARE_1;
        m_bank.voices[1].type = VOICE_NOISE;
    }

    bool prepare(QString *error)
    {
        if (!m_temporary.isValid() || !m_smf.writeFile(m_song.midPath, error) ||
            !m_document.load(m_song, error))
            return false;
        EditorRigConfig config;
        config.voicegroup = &m_bank;
        config.activePage = EditorDrawerPage::Velocity;
        config.sections = {{EditorDrawerPage::Velocity, 200}};
        m_rig = EditorRig::create(m_document, config, *error);
        if (!m_rig)
            return false;
        m_rig->view().setDrawerSectionVisible(EditorDrawerPage::Automations, false);
        return true;
    }

    SongDocument &document() noexcept { return m_document; }
    SongView &view() noexcept { return m_rig->view(); }
    const MidiTimeline &timeline() const noexcept { return m_rig->timeline(); }
    LoadedVoiceGroup &bank() noexcept { return m_bank; }

  private:
    QTemporaryDir m_temporary;
    SmfFile m_smf;
    SongInfo m_song;
    SongDocument m_document;
    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<EditorRig> m_rig;
};

inline void settle()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

inline uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

} // namespace checks::host
