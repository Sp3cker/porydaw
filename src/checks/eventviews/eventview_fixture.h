#pragma once

#include <memory>

#include <QString>

#include "checks/support/editorrig.h"
#include "core/songdocument.h"
#include "ui/eventtablemodel.h"

class EventListView;
class QComboBox;
class QMenu;
class QTableView;
class SongTab;
class SongView;

namespace checks::eventviews {

enum class FixtureShape { Basic, Tempo, Empty, EotCoincident, Long, Signatures };

struct EventWidgets {
    EventListView *events = nullptr;
    QTableView *table = nullptr;
    QComboBox *chunkCombo = nullptr;
    QMenu *filterMenu = nullptr;
    eventlist::EventTableModel *model = nullptr;

    explicit operator bool() const { return events && table && chunkCombo && filterMenu && model; }
};

template <typename Fixture>
struct FixtureOpen {
    std::unique_ptr<Fixture> fixture;
    QString error;

    explicit operator bool() const { return fixture != nullptr; }
};

class EventViewRigFixture final
{
  public:
    static std::unique_ptr<EventViewRigFixture> create(FixtureShape shape, QString &error);
    ~EventViewRigFixture();

    EventViewRigFixture(const EventViewRigFixture &) = delete;
    EventViewRigFixture &operator=(const EventViewRigFixture &) = delete;

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    EventWidgets openEventList();

  private:
    EventViewRigFixture() = default;

    SongDocument m_document;
    std::unique_ptr<EditorRig> m_rig;
};

class EventViewTabFixture final
{
  public:
    static std::unique_ptr<EventViewTabFixture> create(FixtureShape shape, QString &error);
    ~EventViewTabFixture();

    EventViewTabFixture(const EventViewTabFixture &) = delete;
    EventViewTabFixture &operator=(const EventViewTabFixture &) = delete;

    SongDocument &document() noexcept;
    SongView &view() noexcept;
    SongTab &tab() noexcept;
    EventWidgets openEventList();

  private:
    EventViewTabFixture() = default;

    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
};

FixtureOpen<EventViewRigFixture> openRigFixture(FixtureShape shape);
FixtureOpen<EventViewTabFixture> openTabFixture(FixtureShape shape);

bool trackIsSorted(const SmfTrack &track);
int rowForTickAndType(const eventlist::EventTableModel &model, uint64_t tick, int type);
int chunkForTrack(const SongDocument &document, int engineTrack);
bool selectChunk(QComboBox &combo, int chunk);

} // namespace checks::eventviews
