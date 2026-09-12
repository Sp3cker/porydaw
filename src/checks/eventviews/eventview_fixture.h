#pragma once

#include <QPointF>

#include <memory>

#include <QString>

#include "checks/support/editorrig.h"
#include "core/songdocument.h"
#include "ui/eventtablemodel.h"
#include "ui/songview/quick/eventlistcontroller.h"

class QQuickItem;
class QQuickWindow;
class SongTab;
class SongView;

namespace songview {
class QuickPopupSession;
class TimelineInputItem;
} // namespace songview

namespace checks::eventviews {

enum class FixtureShape { Basic, Tempo, Empty, EotCoincident, Long, Signatures };

// The live event-list surfaces a scenario drives: the controller that owns
// chrome/selection/edit behavior, its Qt model, and the Quick window the page
// renders in — the delivery target for every real key/pointer injection.
struct EventWidgets {
    EventListController *controller = nullptr;
    eventlist::EventTableModel *model = nullptr;
    QQuickWindow *quickWindow = nullptr;
    songview::QuickPopupSession *popupSession = nullptr;

    explicit operator bool() const { return controller && model && quickWindow && popupSession; }
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
    EventViewTabFixture();

    LoadedVoiceGroup m_bank = {};
    std::unique_ptr<SongTab> m_tab;
};

FixtureOpen<EventViewRigFixture> openRigFixture(FixtureShape shape);
FixtureOpen<EventViewTabFixture> openTabFixture(FixtureShape shape);

bool trackIsSorted(const SmfTrack &track);
int rowForTickAndType(const eventlist::EventTableModel &model, Tick tick, int type);
int chunkForTrack(const SongDocument &document, int engineTrack);
// Selects the given SMF chunk the way the page's chunk menu does.
bool selectChunk(EventListController &controller, int chunk);

// The menu panel is a QQuickItem visual descendant of the shared popup layer,
// rather than a QObject-owned child of the canvas window. The lookup itself
// lives on the shared quick_popup seam.
QQuickItem *activeMenuPanel(const EventWidgets &widgets);

// Finds a rendered item through QQuickItem's visual-parent tree. Dynamically
// instantiated delegates and host-owned panels need not be QObject children
// of the window even though they render in its content item.
QQuickItem *visualItem(QQuickWindow &window, const QString &objectName);
// Scene-coordinate seam for real pointer injection into the page's table.
QQuickItem *eventListTable(const EventWidgets &widgets);
qreal eventListRowHeight(const EventWidgets &widgets);
QPointF cellSceneCenter(const EventWidgets &widgets, int row, int column);
// Opens a cell editor with a real double-click and reports the editor item
// holding active focus; closeCellEditor() cancels it with Escape.
bool openCellEditor(const EventWidgets &widgets, int row, int column, const QString &editorName,
                    QQuickItem **editor = nullptr);
void closeCellEditor(const EventWidgets &widgets);

// Real mouse click on a sibling band surface (drawer, roll, ...) so it owns
// active focus; false when the surface is missing, empty, or refuses focus.
bool focusSurface(const EventWidgets &widgets, songview::TimelineInputItem &input);

} // namespace checks::eventviews
