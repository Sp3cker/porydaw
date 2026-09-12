#include "checks/eventviews/eventview_fixture.h"

#include <QCoreApplication>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRect>
#include <QtTest>

#include <algorithm>
#include <optional>
#include <utility>

#include "checks/quickpopupguard.h"
#include "checks/support/support.h"
#include "core/tracklimits.h"
#include "project/projectidentity.h"
#include "project/voicegroupsource.h"
#include "ui/songtab.h"
#include "ui/songview.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"

namespace checks::eventviews {
namespace {

SmfEvent event(uint64_t tick, uint8_t status, uint8_t data0 = 0, uint8_t data1 = 0)
{
    SmfEvent value;
    value.tick = tick;
    value.status = status;
    value.data0 = data0;
    value.data1 = data1;
    return value;
}

SmfEvent meta(uint64_t tick, uint8_t type, QByteArray payload)
{
    SmfEvent value;
    value.tick = tick;
    value.status = 0xff;
    value.metaType = type;
    value.blob = std::move(payload);
    return value;
}

SmfFile fixtureSmf(FixtureShape shape)
{
    SmfFile smf;
    smf.format = 1;
    smf.division = shape == FixtureShape::Signatures ? 48 : 24;

    if (shape == FixtureShape::Empty) {
        smf.tracks.push_back(SmfTrack{{}, 120});
        return smf;
    }
    if (shape == FixtureShape::EotCoincident) {
        smf.tracks.push_back(SmfTrack{{meta(120, 0x06, QByteArrayLiteral("at end"))}, 120});
        return smf;
    }

    SmfTrack primary;
    primary.events = {
        meta(0, 0x58, QByteArray::fromHex("04021808")),
        meta(0, 0x06, QByteArrayLiteral("fixture marker")),
        event(0, 0xc0, 0),
        event(8, 0xb0, 7, 80),
        event(12, 0x90, 60, 90),
        event(30, 0x80, 60),
        meta(50, 0x58, QByteArray::fromHex("03021808")),
        event(60, 0xb0, 7, 20),
        event(60, 0xb0, 10, 30),
        event(70, 0x90, 64, 70),
        event(90, 0x80, 64),
    };
    if (shape == FixtureShape::Tempo)
        primary.events.insert(primary.events.begin(), meta(0, 0x51, QByteArray::fromHex("07a120")));
    if (shape == FixtureShape::Signatures)
        primary.events.insert(primary.events.begin() + 7,
                              meta(36, 0x58, QByteArray::fromHex("06031808")));
    primary.endTick = shape == FixtureShape::Long ? 500 : 120;
    if (shape == FixtureShape::Long) {
        for (uint64_t tick = 100; tick < 500; tick++)
            primary.events.push_back(event(tick, 0xb0, 11, uint8_t(tick % 127)));
    }
    smf.tracks.push_back(std::move(primary));
    smf.tracks.push_back(SmfTrack{{meta(5, 0x06, QByteArrayLiteral("metadata only"))}, 120});
    smf.tracks.push_back(SmfTrack{{event(0, 0xc1, 1), event(24, 0xb1, 7, 64),
                                   event(48, 0x90 | 1, 67, 90), event(72, 0x80 | 1, 67)},
                                  120});
    return smf;
}

SongInfo fixtureSong()
{
    SongInfo song;
    song.label = QStringLiteral("eventviews-fixture");
    song.hasMid = true;
    return song;
}

EventWidgets locateWidgets(SongView &view)
{
    view.setEventListVisible(true);
    QCoreApplication::processEvents();

    EventWidgets widgets;
    const bool ready = QTest::qWaitFor([&view, &widgets] {
        widgets.controller = view.eventListController();
        widgets.model = widgets.controller ? widgets.controller->model() : nullptr;
        songview::TimelineQuickView *quick = view.quickView();
        widgets.quickWindow = quick ? quick->quickWindow() : nullptr;
        widgets.popupSession = quick ? quick->popupSession() : nullptr;
        return bool(widgets);
    });
    if (!ready)
        return {};
    return widgets;
}

QQuickItem *visualDescendant(QQuickItem *root, const QString &objectName)
{
    if (!root)
        return nullptr;
    if (root->objectName() == objectName)
        return root;
    for (QQuickItem *child : root->childItems())
        if (QQuickItem *found = visualDescendant(child, objectName))
            return found;
    return nullptr;
}

} // namespace

std::unique_ptr<EventViewRigFixture> EventViewRigFixture::create(FixtureShape shape, QString &error)
{
    error.clear();
    auto fixture = std::unique_ptr<EventViewRigFixture>(new EventViewRigFixture);
    if (!fixture->m_document.adoptSmf(fixtureSmf(shape), fixtureSong(), &error))
        return nullptr;

    EditorRigConfig config;
    config.viewSize = QSize(1000, 640);
    config.sampleRate = 48000.0;
    config.show = true;
    fixture->m_rig = EditorRig::create(fixture->m_document, config, error);
    if (!fixture->m_rig)
        return nullptr;
    return fixture;
}

EventViewRigFixture::~EventViewRigFixture() = default;

SongDocument &EventViewRigFixture::document() noexcept
{
    return m_document;
}

SongView &EventViewRigFixture::view() noexcept
{
    return m_rig->view();
}

EventWidgets EventViewRigFixture::openEventList()
{
    return locateWidgets(view());
}

EventViewTabFixture::EventViewTabFixture() = default;

std::unique_ptr<EventViewTabFixture> EventViewTabFixture::create(FixtureShape shape, QString &error)
{
    error.clear();
    const std::optional<SongName> name = SongName::create(QStringLiteral("eventviews-fixture"));
    const std::optional<VoicegroupId> identity =
        VoicegroupId::create(QStringLiteral("eventviews-fixture"), QString());
    if (!name || !identity) {
        error = QStringLiteral("could not construct the EventViews fixture identity");
        return nullptr;
    }

    auto fixture = std::unique_ptr<EventViewTabFixture>(new EventViewTabFixture);
    fixture->m_bank.voices[0].type = VOICE_DIRECTSOUND;
    fixture->m_bank.voices[1].type = VOICE_SQUARE_1;
    fixture->m_bank.voices[2].type = VOICE_PROGRAMMABLE_WAVE;
    fixture->m_bank.voices[3].type = VOICE_NOISE;
    fixture->m_tab = std::make_unique<SongTab>(std::move(*name));
    fixture->m_tab->resize(1000, 640);
    fixture->m_tab->setSampleRate(48000.0);
    fixture->m_tab->applyMidiStage(fixtureSong(), fixtureSmf(shape),
                                   track_limits::kHardwareCapacity);
    if (!fixture->m_tab->presentationError().isEmpty()) {
        error = fixture->m_tab->presentationError();
        return nullptr;
    }
    fixture->m_tab->applyBankView(
        LoadedBankView{*identity, borrowVoicegroupLease(&fixture->m_bank), QString()});
    fixture->m_tab->applyVoicegroupBound(*identity);
    if (!fixture->m_tab->isReady()) {
        error = QStringLiteral("SongTab did not become ready");
        return nullptr;
    }
    checks::support::bindEditActionsForTest(fixture->m_tab->view());
    fixture->m_tab->show();
    QCoreApplication::processEvents();
    return fixture;
}

EventViewTabFixture::~EventViewTabFixture() = default;

SongDocument &EventViewTabFixture::document() noexcept
{
    return m_tab->document();
}

SongView &EventViewTabFixture::view() noexcept
{
    return m_tab->view();
}

SongTab &EventViewTabFixture::tab() noexcept
{
    return *m_tab;
}

EventWidgets EventViewTabFixture::openEventList()
{
    return locateWidgets(view());
}
FixtureOpen<EventViewRigFixture> openRigFixture(FixtureShape shape)
{
    FixtureOpen<EventViewRigFixture> opened;
    opened.fixture = EventViewRigFixture::create(shape, opened.error);
    return opened;
}

FixtureOpen<EventViewTabFixture> openTabFixture(FixtureShape shape)
{
    FixtureOpen<EventViewTabFixture> opened;
    opened.fixture = EventViewTabFixture::create(shape, opened.error);
    return opened;
}

bool trackIsSorted(const SmfTrack &track)
{
    return std::is_sorted(
        track.events.begin(), track.events.end(),
        [](const SmfEvent &left, const SmfEvent &right) { return left.tick < right.tick; });
}

int rowForTickAndType(const eventlist::EventTableModel &model, uint64_t tick, int type)
{
    for (int row = 0; row + 1 < model.rowCount(); row++) {
        if (model.data(model.index(row, eventlist::EventTableModel::ColTick), Qt::EditRole)
                    .toULongLong() == tick &&
            model.data(model.index(row, eventlist::EventTableModel::ColType), Qt::EditRole)
                    .toInt() == type)
            return row;
    }
    return -1;
}

int chunkForTrack(const SongDocument &document, int engineTrack)
{
    return document.smfTrackFor(engineTrack);
}

bool selectChunk(EventListController &controller, int chunk)
{
    controller.chunkPicked(chunk);
    return controller.chunk() == chunk;
}

QQuickItem *visualItem(QQuickWindow &window, const QString &objectName)
{
    return visualDescendant(window.contentItem(), objectName);
}

QQuickItem *activeMenuPanel(const EventWidgets &widgets)
{
    return widgets.popupSession ? quick_popup::menuPanel(*widgets.popupSession) : nullptr;
}

QQuickItem *eventListTable(const EventWidgets &widgets)
{
    return widgets.quickWindow ? visualItem(*widgets.quickWindow, QStringLiteral("eventListTable"))
                               : nullptr;
}

qreal eventListRowHeight(const EventWidgets &widgets)
{
    QQuickItem *table = eventListTable(widgets);
    if (!table)
        return 0;
    const auto content = table->property("contentItem").value<QQuickItem *>();
    if (!content)
        return 0;
    qreal height = 0;
    QList<QQuickItem *> pending{content};
    while (!pending.isEmpty()) {
        QQuickItem *item = pending.takeLast();
        const QVariant row = item->property("row");
        const QVariant column = item->property("column");
        if (row.isValid() && column.isValid() && item->isVisible() && item->height() > 0)
            height = height == 0 ? item->height() : qMin(height, item->height());
        pending.append(item->childItems());
    }
    return height;
}

namespace {
QQuickItem *renderedCell(QQuickItem *root, int row, int column)
{
    if (!root)
        return nullptr;
    if (root->property("row").toInt() == row && root->property("row").isValid() &&
        root->property("column").toInt() == column && root->property("column").isValid())
        return root;
    for (QQuickItem *child : root->childItems())
        if (QQuickItem *found = renderedCell(child, row, column))
            return found;
    return nullptr;
}
} // namespace

QPointF cellSceneCenter(const EventWidgets &widgets, int row, int column)
{
    QQuickItem *table = eventListTable(widgets);
    const auto content = table ? table->property("contentItem").value<QQuickItem *>() : nullptr;
    QQuickItem *cell = nullptr;
    if (!content || !QTest::qWaitFor([&] {
            cell = renderedCell(content, row, column);
            return cell && cell->isVisible() && cell->width() > 0 && cell->height() > 0;
        }))
        return {};
    return cell->mapToScene(QPointF(cell->width() / 2.0, cell->height() / 2.0));
}

bool openCellEditor(const EventWidgets &widgets, int row, int column, const QString &editorName,
                    QQuickItem **editor)
{
    if (!widgets.quickWindow || !eventListTable(widgets))
        return false;
    const QPointF scene = cellSceneCenter(widgets, row, column);
    if (scene.isNull() || !QRect(QPoint{}, widgets.quickWindow->size()).contains(scene.toPoint()))
        return false;
    QTest::mouseDClick(widgets.quickWindow, Qt::LeftButton, Qt::NoModifier, scene.toPoint());
    QQuickItem *item = nullptr;
    const bool opened = QTest::qWaitFor([&widgets, &editorName, &item] {
        item = visualItem(*widgets.quickWindow, editorName);
        return item && item->isVisible() && item->hasActiveFocus();
    });
    if (opened && editor)
        *editor = item;
    return opened;
}

void closeCellEditor(const EventWidgets &widgets)
{
    if (!widgets.quickWindow)
        return;
    QTest::keyClick(widgets.quickWindow, Qt::Key_Escape);
    QCoreApplication::processEvents();
}

bool focusSurface(const EventWidgets &widgets, songview::TimelineInputItem &input)
{
    if (!widgets.quickWindow || input.bounds().isEmpty() || input.window() != widgets.quickWindow)
        return false;
    const QPointF center = input.mapToScene(input.bounds().center());
    if (!QRect(QPoint{}, widgets.quickWindow->size()).contains(center.toPoint()))
        return false;
    QTest::mouseClick(widgets.quickWindow, Qt::LeftButton, Qt::NoModifier, center.toPoint());
    QCoreApplication::processEvents();
    return input.hasActiveFocus();
}

} // namespace checks::eventviews
