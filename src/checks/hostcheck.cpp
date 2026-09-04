#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/timelinequickcheck.h"

#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "project/decompproject.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

#include <QApplication>
#include <QColor>
#include <QCoreApplication>
#include <QEnterEvent>
#include <QEvent>
#include <QFileInfo>
#include <QFocusEvent>
#include <QImage>
#include <QKeyEvent>
#include <QMenu>
#include <QMouseEvent>
#include <QPalette>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QScrollBar>
#include <QSize>
#include <QSizeF>
#include <QString>
#include <QStringList>
#include <QTemporaryDir>
#include <QTimer>
#include <QToolTip>
#include <QVariant>
#include <QWidget>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <memory>
#include <optional>
#include <utility>
#include <vector>

namespace {

SmfEvent noteEvent(uint8_t status, uint64_t tick, uint8_t key, uint8_t velocity)
{
    SmfEvent event;
    event.status = status;
    event.tick = tick;
    event.data0 = key;
    event.data1 = velocity;
    return event;
}

uint64_t drawerContextTick(double tick)
{
    return static_cast<uint64_t>(std::floor(std::max(0.0, tick) + 0.5));
}

EditorDrawer *editorDrawer(SongView &view)
{
    return view.editorDrawer();
}

VelocityArea *velocityArea(SongView &view)
{
    auto *drawer = editorDrawer(view);
    return drawer ? drawer->velocityArea() : nullptr;
}

AutomationCanvas *automationCanvas(SongView &view)
{
    auto *drawer = editorDrawer(view);
    auto *page = drawer ? drawer->automationPage() : nullptr;
    return page ? page->canvas() : nullptr;
}

QPointF nodePosition(const SongView &view, const VelocityArea &area, const MidiTimeline &timeline,
                     const DocNote &note)
{
    const double x = double(note.tick) * view.camera().pxPerBeat() / double(timeline.ticksPerBeat) -
                     view.camera().scrollX();
    return {x, area.axis().velocityToY(note.velocity)};
}

void pumpZeroDelayTimers()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

struct QmlBandPropertyNames {
    songview::TimelineBand band;
    const char *rectProperty;
    const char *plotRectProperty;
    const char *visibleProperty;
};

constexpr std::array<QmlBandPropertyNames, 7> qmlBandPropertyNames{{
    {songview::TimelineBand::Ruler, "rulerBandRect", "rulerBandPlotRect", "rulerBandVisible"},
    {songview::TimelineBand::Roll, "rollBandRect", "rollBandPlotRect", "rollBandVisible"},
    {songview::TimelineBand::OtherEvents, "otherEventsBandRect", "otherEventsBandPlotRect",
     "otherEventsBandVisible"},
    {songview::TimelineBand::Automation, "automationBandRect", "automationBandPlotRect",
     "automationBandVisible"},
    {songview::TimelineBand::Velocity, "velocityBandRect", "velocityBandPlotRect",
     "velocityBandVisible"},
    {songview::TimelineBand::VoiceChanges, "voiceChangesBandRect", "voiceChangesBandPlotRect",
     "voiceChangesBandVisible"},
    {songview::TimelineBand::TrackHeaders, "trackHeadersBandRect", "trackHeadersBandPlotRect",
     "trackHeadersBandVisible"},
}};

QString describeRect(const QRect &rect)
{
    return QStringLiteral("[%1,%2 %3x%4]")
        .arg(rect.x())
        .arg(rect.y())
        .arg(rect.width())
        .arg(rect.height());
}

QString describeRect(const QRectF &rect)
{
    return QStringLiteral("[%1,%2 %3x%4]")
        .arg(rect.x(), 0, 'f', 2)
        .arg(rect.y(), 0, 'f', 2)
        .arg(rect.width(), 0, 'f', 2)
        .arg(rect.height(), 0, 'f', 2);
}

QString describeSize(const QSize &size)
{
    return QStringLiteral("%1x%2").arg(size.width()).arg(size.height());
}

QString describeSize(const QSizeF &size)
{
    return QStringLiteral("%1x%2").arg(size.width(), 0, 'f', 2).arg(size.height(), 0, 'f', 2);
}

QString quickHostGeometryDetails(const songview::TimelineQuickView &quick)
{
    const QQuickWindow *const window = quick.quickWindow();
    const QQuickItem *const root = quick.rootObject();
    const QString missing = QStringLiteral("<missing>");
    return QStringLiteral("Quick-host=%1 Quick-window-size=%2 Quick-root-size=%3")
        .arg(describeRect(quick.geometry()))
        .arg(window ? describeSize(window->size()) : missing)
        .arg(root ? describeSize(root->size()) : missing);
}

QString describeRectDelta(const QRectF &expected, const QRectF &actual)
{
    return QStringLiteral("[dx=%1 dy=%2 dw=%3 dh=%4]")
        .arg(actual.x() - expected.x(), 0, 'f', 2)
        .arg(actual.y() - expected.y(), 0, 'f', 2)
        .arg(actual.width() - expected.width(), 0, 'f', 2)
        .arg(actual.height() - expected.height(), 0, 'f', 2);
}

QRect gutterRect(const songview::TimelineBandGeometry &geometry)
{
    return QRect(
        geometry.rect.topLeft(),
        QSize(std::max(0, geometry.plotRect.x() - geometry.rect.x()), geometry.rect.height()));
}

QString canonicalInputFailureDetails(const SongView &view, const songview::TimelineQuickView &quick,
                                     QObject &quickRoot, songview::TimelineBand band,
                                     const QString &plotInputObjectName,
                                     const QString &gutterInputObjectName)
{
    const std::optional<songview::TimelineBandGeometry> &geometry =
        view.timelineBandLayout().geometry(band);
    const QQuickItem *const root = quick.rootObject();
    const auto describeInput = [&](const QString &objectName, const QRect &surfaceRect) {
        const auto *input = quickRoot.findChild<songview::TimelineInputItem *>(objectName);
        const QRectF expectedHostRect = surfaceRect.translated(-quick.geometry().topLeft());
        const QRectF expectedBounds(QPointF{}, surfaceRect.size());
        const QRectF actualHostRect =
            input && root ? QRectF(input->mapToItem(root, QPointF{}), input->size()) : QRectF{};
        const QString missing = QStringLiteral("<missing>");
        return QStringLiteral(
                   "{object=%1 expected-host-local=%2 actual-host-local=%3 host-delta=%4 "
                   "expected-bounds=%5 actual-bounds=%6 bounds-delta=%7 visible=%8}")
            .arg(objectName)
            .arg(describeRect(expectedHostRect))
            .arg(input && root ? describeRect(actualHostRect) : missing)
            .arg(input && root ? describeRectDelta(expectedHostRect, actualHostRect) : missing)
            .arg(describeRect(expectedBounds))
            .arg(input ? describeRect(input->bounds()) : missing)
            .arg(input ? describeRectDelta(expectedBounds, input->bounds()) : missing)
            .arg(input ? (input->isVisible() ? QStringLiteral("true") : QStringLiteral("false"))
                       : missing);
    };
    if (!geometry) {
        return QStringLiteral("canonical-SongView=<missing> plot-object=%1 gutter-object=%2 %3")
            .arg(plotInputObjectName)
            .arg(gutterInputObjectName)
            .arg(quickHostGeometryDetails(quick));
    }
    return QStringLiteral("canonical-band=%1 canonical-plot=%2 plot=%3 gutter=%4 "
                          "Quick-window-unmasked=%5 %6")
        .arg(describeRect(geometry->rect))
        .arg(describeRect(geometry->plotRect))
        .arg(describeInput(plotInputObjectName, geometry->plotRect))
        .arg(describeInput(gutterInputObjectName, gutterRect(*geometry)))
        .arg(checks::support::quickWindowIsUnmasked(quick) ? QStringLiteral("true")
                                                           : QStringLiteral("false"))
        .arg(quickHostGeometryDetails(quick));
}

QString
otherEventsHoverCandidateDetails(const SongView &view, const songview::TimelineQuickView &quick,
                                 const songview::TimelineInputItem *input,
                                 const std::optional<songview::TimelineBandGeometry> &geometry)
{
    if (!geometry) {
        return QStringLiteral("other-events hover candidates: canonical-SongView=<missing> %1")
            .arg(quickHostGeometryDetails(quick));
    }

    const QString canonicalRect = describeRect(geometry->rect);
    const QString plotRange = describeRect(geometry->plotRect);
    if (!input) {
        return QStringLiteral("other-events hover candidates: canonical-SongView=%1 plot-x=%2 "
                              "input=<missing> %3")
            .arg(canonicalRect)
            .arg(plotRange)
            .arg(quickHostGeometryDetails(quick));
    }

    const QQuickItem *const root = quick.rootObject();
    const QString inputHostRect =
        root ? describeRect(QRectF(input->mapToItem(root, QPointF{}), input->size()))
             : QStringLiteral("<missing>");
    const QPoint quickOriginInSongView = quick.mapTo(&view, QPoint{});
    QStringList candidates;
    for (const StripItem &item : view.model().strip) {
        const qreal markerX = view.camera().displayX(double(item.tick), geometry->plotRect.x(),
                                                     input->devicePixelRatio());
        const QPointF markerPositionInSongView(markerX, geometry->rect.center().y());
        const QPointF markerPositionInQuickHost =
            markerPositionInSongView -
            QPointF(quickOriginInSongView.x(), quickOriginInSongView.y());
        const QPointF inputPosition = input->mapFromScene(markerPositionInQuickHost);
        candidates.append(QStringLiteral("{tick=%1 marker-x=%2 input-x=%3 contains=%4}")
                              .arg(static_cast<qulonglong>(item.tick))
                              .arg(markerX, 0, 'f', 2)
                              .arg(inputPosition.x(), 0, 'f', 2)
                              .arg(input->contains(inputPosition) ? QStringLiteral("true")
                                                                  : QStringLiteral("false")));
    }
    return QStringLiteral("other-events hover candidates: canonical-SongView=%1 plot-x=%2 "
                          "input-host-local=%3 input-bounds=%4 input-dpr=%5 candidates=[%6] %7")
        .arg(canonicalRect)
        .arg(plotRange)
        .arg(inputHostRect)
        .arg(describeRect(input->bounds()))
        .arg(input->devicePixelRatio(), 0, 'f', 2)
        .arg(candidates.join(QStringLiteral(", ")))
        .arg(quickHostGeometryDetails(quick));
}

QString imageDetails(const QImage &image)
{
    return QStringLiteral("{null=%1 size=%2 dpr=%3}")
        .arg(image.isNull() ? QStringLiteral("true") : QStringLiteral("false"))
        .arg(describeSize(image.size()))
        .arg(image.devicePixelRatio(), 0, 'f', 2);
}

// The retained QML properties must always republish the canonical layout's
// row and plot rectangles translated into Quick-host coordinates, or empty
// invisible rectangles for a hidden band.
bool publishedQmlRectsMatchCanonical(const QWidget &quick, QObject &quickRoot,
                                     const songview::TimelineBandLayout &layout)
{
    for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
        const std::optional<songview::TimelineBandGeometry> &geometry = layout.geometry(names.band);
        const QRectF expectedRect =
            geometry ? QRectF(geometry->rect.translated(-quick.geometry().topLeft())) : QRectF{};
        const QRectF expectedPlotRect =
            geometry && !geometry->plotRect.isEmpty()
                ? QRectF(geometry->plotRect.translated(-quick.geometry().topLeft()))
                : QRectF{};
        if (quickRoot.property(names.rectProperty).toRectF() != expectedRect ||
            quickRoot.property(names.plotRectProperty).toRectF() != expectedPlotRect ||
            quickRoot.property(names.visibleProperty).toBool() != geometry.has_value())
            return false;
    }
    return true;
}

bool trackHeadersInputMatchesCanonical(const SongView &view,
                                       const songview::TimelineQuickView &quick, QObject &quickRoot,
                                       const songview::TrackHeaderModel &headers)
{
    const std::optional<songview::TimelineBandGeometry> &geometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
    const auto *input = quickRoot.findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineTrackHeadersInput"));
    if (!geometry || !input)
        return false;
    const int rowAreaWidth = std::max(0, geometry->rect.width() - headers.scrollbarWidth());
    const QRect expectedRect(geometry->rect.topLeft() - quick.geometry().topLeft(),
                             QSize(rowAreaWidth, geometry->rect.height()));
    return input->isVisible() && input->interaction() == &headers &&
           input->bounds() == QRectF(QPointF{}, expectedRect.size()) &&
           QRectF(input->mapToItem(quick.rootObject(), QPointF()), input->size()) ==
               QRectF(expectedRect);
}

// Drawer chrome is owned by the one Quick host. Its input item must translate
// the SongView-local snapshot rectangle into that host and bind the matching
// interaction rather than a retained native widget.
bool inputMatchesDrawerChrome(const songview::TimelineQuickView &quick, QQuickItem &quickRoot,
                              const songview::TimelineInputItem *input, const QRectF &songViewRect,
                              bool visible, const songview::TimelineBandInteraction &interaction)
{
    if (!input || input->interaction() != &interaction || input->isVisible() != visible)
        return false;
    if (!visible)
        return songViewRect.isEmpty();
    const QRectF expectedRect = songViewRect.translated(-quick.geometry().topLeft());
    return input->bounds() == QRectF(QPointF{}, songViewRect.size()) &&
           QRectF(input->mapToItem(&quickRoot, QPointF{}), input->size()) == expectedRect;
}

} // namespace

int runHostAdapterCheck(const QString &scratchProject, const QString &songLabel)
{
    int failures = 0;
    const auto check = [&failures, &songLabel](bool condition, const char *message) {
        if (!condition) {
            std::fprintf(stderr, "host-adapter: FAIL %s: %s\n", qUtf8Printable(songLabel), message);
            ++failures;
        }
    };

    check(QFileInfo(scratchProject).isDir(), "scratch project does not exist");
    check(!songLabel.isEmpty(), "song label is empty");
    if (failures)
        return 1;

    DecompProject fixtureProject;
    QString fixtureError;
    check(fixtureProject.open(scratchProject, &fixtureError), "fixture project should load");
    const SongInfo *fixtureSong = nullptr;
    if (fixtureProject.isOpen()) {
        for (const SongInfo &song : fixtureProject.songs()) {
            if (song.label == songLabel && song.isPlayable()) {
                fixtureSong = &song;
                break;
            }
        }
    }
    check(fixtureSong != nullptr, "fixture song label should resolve to a playable song");
    SongDocument fixtureDocument;
    std::unique_ptr<MidiTimeline> fixtureTimeline;
    std::optional<DocNote> fixtureNote;
    if (fixtureSong) {
        check(fixtureDocument.load(*fixtureSong, &fixtureError),
              "fixture song should load through SongDocument");
        fixtureTimeline = fixtureDocument.buildTimeline(44100.0);
        check(fixtureTimeline != nullptr, "fixture song should build a timeline");
        if (fixtureTimeline) {
            for (int track = 0; track < fixtureTimeline->usedTrackCount; ++track) {
                const std::vector<DocNote> notes = fixtureDocument.notesForTrack(track);
                if (!notes.empty()) {
                    fixtureNote = notes.front();
                    break;
                }
            }
            bool timelineHasFixtureNote = false;
            if (fixtureNote) {
                timelineHasFixtureNote =
                    std::any_of(fixtureTimeline->events.cbegin(), fixtureTimeline->events.cend(),
                                [noteId = fixtureNote->noteId](const TimelineEvent &event) {
                                    return event.type == 0x9 && event.noteId == noteId;
                                });
            }
            check(!fixtureTimeline->events.empty() && fixtureNote.has_value() &&
                      timelineHasFixtureNote,
                  "fixture song should contain timeline and note data");
        }
    }
    if (fixtureTimeline && fixtureNote) {
        SongView fixtureView;
        fixtureView.resize(720, 520);
        fixtureView.setDocument(&fixtureDocument);
        fixtureView.setSong(fixtureTimeline.get(), nullptr);
        fixtureView.show();
        QCoreApplication::processEvents();
        fixtureView.selectTrack(fixtureNote->engineTrack);
        const std::vector<NoteId> fixtureSelection{fixtureNote->noteId};
        fixtureView.selectionModel().setNoteSelection(fixtureSelection);
        fixtureView.setEditCursorTick(fixtureNote->tick);
        fixtureView.setDrawerActivePage(EditorDrawerPage::Velocity);
        fixtureView.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        QCoreApplication::processEvents();
        auto *fixtureDrawer = fixtureView.editorDrawer();
        auto *fixtureArea = velocityArea(fixtureView);
        check(fixtureDocument.label() == songLabel &&
                  fixtureView.timeline() == fixtureTimeline.get() && fixtureDrawer &&
                  fixtureView.hasVisibleDrawerSection() && fixtureArea &&
                  fixtureView.selectionModel().primaryTrack() == fixtureNote->engineTrack &&
                  fixtureView.selectionModel().noteSelection() == fixtureSelection &&
                  fixtureArea->axis().markerCount() == 1 &&
                  fixtureArea->axis().markers()[0].velocity == fixtureNote->velocity,
              "adapter should attach supplied fixture note data to the hosted velocity page");
        fixtureView.hide();
    }
    if (failures)
        return 1;

    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack primary;
    primary.events = {
        noteEvent(0xC0, 0, 0, 0),  noteEvent(0x90, 12, 60, 20), noteEvent(0x90, 12, 60, 70),
        noteEvent(0xC0, 24, 1, 0), noteEvent(0x80, 36, 60, 0),  noteEvent(0x80, 36, 60, 0),
    };
    primary.endTick = 36;
    SmfTrack secondary;
    secondary.events = {
        noteEvent(0x91, 12, 67, 80),
        noteEvent(0x81, 36, 67, 0),
    };
    secondary.endTick = 36;
    smf.tracks = {primary, secondary};

    const QString midiPath = temporary.path() + QStringLiteral("/host-adapter.mid");
    SongInfo song;
    song.label = QStringLiteral("host-adapter");
    song.midPath = midiPath;
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(midiPath, &error) && document.load(song, &error),
          "synthetic fixture should load");
    std::unique_ptr<MidiTimeline> timeline = document.buildTimeline(44100.0);
    check(timeline != nullptr, "synthetic fixture should build a timeline");
    if (failures)
        return 1;

    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0].type = VOICE_SQUARE_1;
    voicegroup.voices[1].type = VOICE_NOISE;
    SongView view;
    view.resize(720, 520);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    view.show();
    QCoreApplication::processEvents();

    auto *area = velocityArea(view);
    auto *quick = view.findChild<songview::TimelineQuickView *>();
    check(area != nullptr, "host should construct the velocity page");
    check(quick != nullptr, "host should construct retained timeline Quick chrome");
    if (!area || !quick)
        return 1;

    EditorViewState editorState;
    editorState.velocity = {true, 180};
    editorState.automation.visible = false;
    editorState.activePage = EditorDrawerPage::Velocity;
    editorState.laneHeight = 42;
    const EditorAutomationRowId lane{EditorAutomationRowKind::ControlChange, 0, 74};
    editorState.emptyLanes.insert(lane);
    editorState.laneRanges.emplace(lane, 96);
    view.applyEditorViewState(editorState);
    QCoreApplication::processEvents();
    check(view.editorViewState() == editorState &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              view.drawerSectionVisible(EditorDrawerPage::Velocity),
          "editor view state should attach without becoming document state");
    const uint64_t revisionBeforeViewCapture = document.revision();
    const int undoBeforeViewCapture = document.undoStack()->count();
    const SongView::ViewState capturedView = view.viewState();
    const EditorViewState capturedEditor = view.editorViewState();
    check(capturedView.valid && capturedEditor.emptyLanes.size() == 1 &&
              capturedEditor.emptyLanes.count(lane) == 1 &&
              document.revision() == revisionBeforeViewCapture &&
              document.undoStack()->count() == undoBeforeViewCapture,
          "detached view-state capture should not save document state");
    check(drawerContextTick(-1.0) == 0 && drawerContextTick(0.49) == 0 &&
              drawerContextTick(0.5) == 1 && drawerContextTick(0.51) == 1,
          "drawer tick should use the neutral shared conversion");

    auto *drawer = editorDrawer(view);
    check(drawer && view.hasVisibleDrawerSection(),
          "drawer should remain visible above other events");
    const std::optional<songview::TimelineBandGeometry> otherEventsGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    check(otherEventsGeometry.has_value(),
          "other events strip should remain visible in canonical layout");
    if (drawer && otherEventsGeometry) {
        const DrawerChrome &chrome = drawer->chrome();
        const QRectF toggleGroup = chrome.voiceChangesToggleRect()
                                       .united(chrome.automationToggleRect())
                                       .united(chrome.velocityToggleRect());
        const std::optional<QRect> velocityBody = drawer->bodyRect(EditorDrawerPage::Velocity);
        const auto &velocityGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
        const qreal pianoKeysCenter =
            velocityGeometry
                ? (qreal(velocityGeometry->rect.x()) + velocityGeometry->plotRect.x()) / 2.0
                : 0.0;
        const bool automationBandHidden =
            !view.timelineBandLayout().geometry(songview::TimelineBand::Automation).has_value();
        check(drawer->overlayRect().bottom() < otherEventsGeometry->rect.top(),
              "drawer should stack above the other events strip");
        check(chrome.velocityHandleVisible() && !chrome.voiceChangesHandleVisible() &&
                  !chrome.automationHandleVisible() && velocityBody.has_value() &&
                  chrome.detentVisible() && automationBandHidden && !chrome.barRect().isEmpty() &&
                  chrome.voiceChangesHandleRect().isEmpty() &&
                  chrome.automationHandleRect().isEmpty() &&
                  chrome.velocityHandleRect().bottom() == velocityBody->top() &&
                  velocityBody->bottom() + 1 == qRound(chrome.barRect().top()) &&
                  chrome.barRect().contains(chrome.voiceChangesToggleRect()) &&
                  chrome.barRect().contains(chrome.automationToggleRect()) &&
                  chrome.barRect().contains(chrome.velocityToggleRect()) &&
                  chrome.automationToggleRect().x() == chrome.voiceChangesToggleRect().x() +
                                                           chrome.voiceChangesToggleRect().width() +
                                                           layout::space(layout::Space::One) &&
                  chrome.velocityToggleRect().x() == chrome.automationToggleRect().x() +
                                                         chrome.automationToggleRect().width() +
                                                         layout::space(layout::Space::One) &&
                  std::abs(toggleGroup.center().x() - pianoKeysCenter) <= 1,
              "DrawerChrome should center its Quick toggles beneath the piano keys");
    }

    auto *rollBand = view.findChild<songview::PianoRoll *>();
    QQuickItem *const quickRoot = quick->rootObject();
    auto *headers = view.findChild<songview::TrackHeaderModel *>(QStringLiteral("trackHeaderModel"),
                                                                 Qt::FindDirectChildrenOnly);
    auto *rulerControls =
        quickRoot ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerControls"))
                  : nullptr;
    auto *divisionControl =
        quickRoot
            ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerDivisionControl"))
            : nullptr;
    auto *feelControl =
        quickRoot ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineRulerFeelControl"))
                  : nullptr;
    auto *trackHeaderBand =
        quickRoot ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"))
                  : nullptr;
    auto *trackHeaderInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                             QStringLiteral("timelineTrackHeadersInput"))
                                       : nullptr;
    QObject *const trackHeaderRows =
        quickRoot ? quickRoot->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"))
                  : nullptr;
    auto *trackHeaderScrollbar =
        quickRoot
            ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollBar"))
            : nullptr;
    auto *trackHeaderThumb =
        quickRoot
            ? quickRoot->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollThumb"))
            : nullptr;
    check(rollBand && quickRoot && quick->quickWindow() && headers && rulerControls &&
              divisionControl && feelControl && trackHeaderBand && trackHeaderInput &&
              trackHeaderRows && trackHeaderScrollbar && trackHeaderThumb,
          "host should expose the timeline Quick controls, header model, and header input");
    check(view.findChild<QWidget *>(QStringLiteral("timeRulerControls"),
                                    Qt::FindDirectChildrenOnly) == nullptr,
          "ruler controls must not retain a native widget");
    if (rollBand && quickRoot && quick->quickWindow() && headers && rulerControls &&
        divisionControl && feelControl && trackHeaderBand && trackHeaderInput && trackHeaderRows &&
        trackHeaderScrollbar && trackHeaderThumb) {
        auto *rulerInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRulerInput"));
        auto *rulerGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRulerGutterInput"));
        auto *rollInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        auto *rollGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollGutterInput"));
        auto *otherInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineOtherEventsInput"));
        auto *otherGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineOtherEventsGutterInput"));
        auto *initialAutomationInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        auto *initialAutomationGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationGutterInput"));
        auto *initialVelocityInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityInput"));
        auto *initialVelocityGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityGutterInput"));
        auto *initialVoiceInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVoiceChangesInput"));
        auto *initialVoiceGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVoiceChangesGutterInput"));
        auto *timeRuler =
            rulerInput ? dynamic_cast<songview::TimeRuler *>(rulerInput->interaction()) : nullptr;
        if (drawer) {
            DrawerChrome &chrome = drawer->chrome();
            const auto chromeAvoidsTimelinePlots = [&](const QRectF &rect, bool visible) {
                if (!visible || rect.isEmpty())
                    return true;
                const QRect aligned = rect.toAlignedRect();
                for (const std::optional<songview::TimelineBandGeometry> &geometry :
                     view.timelineBandLayout().bands) {
                    if (geometry && !geometry->plotRect.isEmpty() &&
                        aligned.intersects(geometry->plotRect))
                        return false;
                }
                return true;
            };
            const auto chromeInputMatches = [&](const char *objectName, const QRectF &rect,
                                                bool visible, DrawerChromeTarget target) {
                return inputMatchesDrawerChrome(*quick, *quickRoot,
                                                quickRoot->findChild<songview::TimelineInputItem *>(
                                                    QString::fromLatin1(objectName)),
                                                rect, visible, chrome.interaction(target));
            };
            const bool quickChromeInputs =
                chromeInputMatches("drawerVoiceChangesHandleInput", chrome.voiceChangesHandleRect(),
                                   chrome.voiceChangesHandleVisible(),
                                   DrawerChromeTarget::VoiceChangesHandle) &&
                chromeInputMatches("drawerVelocityHandleInput", chrome.velocityHandleRect(),
                                   chrome.velocityHandleVisible(),
                                   DrawerChromeTarget::VelocityHandle) &&
                chromeInputMatches("drawerAutomationHandleInput", chrome.automationHandleRect(),
                                   chrome.automationHandleVisible(),
                                   DrawerChromeTarget::AutomationHandle) &&
                chromeInputMatches("drawerBarInput", chrome.barRect(), !chrome.barRect().isEmpty(),
                                   DrawerChromeTarget::Bar) &&
                chromeInputMatches("drawerDetentInput", chrome.detentRect(), chrome.detentVisible(),
                                   DrawerChromeTarget::Detent);
            const bool chromeExcludesTimelinePlots =
                chromeAvoidsTimelinePlots(chrome.voiceChangesHandleRect(),
                                          chrome.voiceChangesHandleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.velocityHandleRect(),
                                          chrome.velocityHandleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.automationHandleRect(),
                                          chrome.automationHandleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.barRect(), !chrome.barRect().isEmpty()) &&
                chromeAvoidsTimelinePlots(chrome.voiceChangesToggleRect(),
                                          chrome.voiceChangesToggleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.automationToggleRect(),
                                          chrome.automationToggleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.velocityToggleRect(),
                                          chrome.velocityToggleVisible()) &&
                chromeAvoidsTimelinePlots(chrome.detentRect(), chrome.detentVisible()) &&
                chromeAvoidsTimelinePlots(chrome.automationScrollbarRect(),
                                          chrome.automationScrollbarVisible());
            check(quickChromeInputs,
                  "Quick drawer chrome inputs should match snapshot geometry and interactions");
            check(chromeExcludesTimelinePlots,
                  "visible DrawerChrome must remain outside every timeline plot");
        }

        check(rulerInput && rulerGutterInput && timeRuler &&
                  rulerGutterInput->interaction() == timeRuler && rollInput && rollGutterInput &&
                  rollInput->interaction() == rollBand &&
                  rollGutterInput->interaction() == rollBand && otherInput && otherGutterInput &&
                  dynamic_cast<songview::OtherStrip *>(otherInput->interaction()) != nullptr &&
                  otherGutterInput->interaction() == otherInput->interaction() &&
                  initialAutomationInput && initialAutomationGutterInput &&
                  initialAutomationInput->interaction() == automationCanvas(view) &&
                  initialAutomationGutterInput->interaction() ==
                      initialAutomationInput->interaction() &&
                  initialVelocityInput && initialVelocityGutterInput &&
                  initialVelocityInput->interaction() == area &&
                  initialVelocityGutterInput->interaction() == area && initialVoiceInput &&
                  initialVoiceGutterInput && drawer &&
                  initialVoiceInput->interaction() == drawer->voiceChangeArea() &&
                  initialVoiceGutterInput->interaction() == drawer->voiceChangeArea() &&
                  trackHeaderInput->interaction() == headers,
              "each timeline plot and gutter input should own its matching interaction");
        check(checks::support::quickWindowIsUnmasked(*quick),
              "the shared Quick window must remain unmasked while it hosts every timeline band");

        const songview::TimelineBandLayout &bandLayout = view.timelineBandLayout();
        const std::optional<songview::TimelineBandGeometry> &rulerGeometry =
            bandLayout.geometry(songview::TimelineBand::Ruler);
        const QRectF rulerGutterRect =
            rulerGeometry
                ? QRectF(gutterRect(*rulerGeometry).translated(-quick->geometry().topLeft()))
                : QRectF{};
        const bool rulerControlsMatchState =
            rulerGeometry && timeRuler && rulerControls->isVisible() &&
            QRectF(rulerControls->mapToItem(quickRoot, QPointF()), rulerControls->size()) ==
                rulerGutterRect &&
            QRectF(rulerGutterInput->mapToItem(quickRoot, QPointF()), rulerGutterInput->size()) ==
                rulerGutterRect &&
            divisionControl->isEnabled() == timeRuler->gridControlsEnabled() &&
            feelControl->isEnabled() == timeRuler->gridControlsEnabled() &&
            divisionControl->property("controlText").toString() == timeRuler->divisionText() &&
            feelControl->property("controlText").toString() == timeRuler->feelText() &&
            std::abs(quick->hostX() + quick->rulerPlotOrigin() -
                     static_cast<qreal>(view.timelineSplitX())) <= 0.5 &&
            quick->quickDevicePixelRatio() > 0.0;
        check(rulerControlsMatchState,
              "Quick ruler controls should map at the live DPR to the canonical ruler gutter");

        const std::optional<songview::TimelineBandGeometry> &trackHeadersGeometry =
            bandLayout.geometry(songview::TimelineBand::TrackHeaders);
        const QRectF expectedTrackHeadersRect =
            trackHeadersGeometry
                ? QRectF(trackHeadersGeometry->rect.translated(-quick->geometry().topLeft()))
                : QRectF{};
        const bool trackHeadersQuickGeometry =
            trackHeadersGeometry && trackHeaderBand->isVisible() &&
            QRectF(trackHeaderBand->mapToItem(quickRoot, QPointF()), trackHeaderBand->size()) ==
                expectedTrackHeadersRect &&
            trackHeadersInputMatchesCanonical(view, *quick, *quickRoot, *headers) &&
            trackHeaderRows->property("count").toInt() == headers->rowCount() &&
            trackHeaderScrollbar->width() == headers->scrollbarWidth() &&
            trackHeaderScrollbar->isVisible() == (headers->maximumScrollY() > 0.0) &&
            trackHeaderThumb->isVisible() == (headers->maximumScrollY() > 0.0);
        check(trackHeadersQuickGeometry,
              "TrackHeaders should publish model-backed Quick rows, input, and scrollbar geometry");

        const auto canonicalVisibleUnion = [&] {
            return checks::support::canonicalVisibleQuickHostRect(
                bandLayout, drawer ? &drawer->chrome() : nullptr);
        };
        QScrollBar *rollScrollbar = nullptr;
        for (QScrollBar *candidate : view.findChildren<QScrollBar *>()) {
            if (candidate->orientation() == Qt::Vertical && candidate->isVisibleTo(&view)) {
                rollScrollbar = candidate;
                break;
            }
        }
        for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
            const auto &geometry = bandLayout.geometry(names.band);
            if (!geometry || names.band == songview::TimelineBand::TrackHeaders)
                continue;
            const int plotStart = geometry->plotRect.x();
            const bool excludesTrackHeaders =
                !trackHeadersGeometry || trackHeadersGeometry->rect.isEmpty() ||
                !trackHeadersGeometry->rect.intersects(geometry->plotRect);
            const QString message =
                QStringLiteral("%1 plotRect must start at timelineSplitX %2, own its band's "
                               "right edge, and exclude TrackHeaders (rect %3, plotRect %4, "
                               "headers %5)")
                    .arg(QString::fromLatin1(names.rectProperty))
                    .arg(view.timelineSplitX())
                    .arg(describeRect(geometry->rect))
                    .arg(describeRect(geometry->plotRect))
                    .arg(trackHeadersGeometry ? describeRect(trackHeadersGeometry->rect)
                                              : QStringLiteral("<missing>"));
            check(!geometry->rect.isEmpty() && !geometry->plotRect.isEmpty() &&
                      geometry->plotRect.x() == view.timelineSplitX() &&
                      geometry->plotRect.right() == geometry->rect.right() && excludesTrackHeaders,
                  qUtf8Printable(message));
        }
        check(trackHeadersGeometry && trackHeadersGeometry->plotRect.isEmpty(),
              "TrackHeaders must publish an empty plotRect");
        const auto &initialVelocityGeometry = bandLayout.geometry(songview::TimelineBand::Velocity);
        const auto &initialRollGeometry = bandLayout.geometry(songview::TimelineBand::Roll);
        check(initialVelocityGeometry && initialRollGeometry && trackHeadersGeometry &&
                  !gutterRect(*initialVelocityGeometry).isEmpty() &&
                  initialVelocityGeometry->rect.x() == trackHeadersGeometry->rect.width() &&
                  gutterRect(*initialVelocityGeometry).width() == view.pianoKeyboardWidth() &&
                  gutterRect(*initialRollGeometry).width() == view.pianoKeyboardWidth() &&
                  initialVelocityGeometry->plotRect.x() == view.timelineSplitX() &&
                  initialVelocityGeometry->plotRect.y() == initialVelocityGeometry->rect.y() &&
                  initialVelocityGeometry->plotRect.height() ==
                      initialVelocityGeometry->rect.height() &&
                  initialVelocityGeometry->plotRect.right() ==
                      initialVelocityGeometry->rect.right(),
              "Velocity and Roll gutters must span the piano-key column after TrackHeaders");
        const QRect rollScrollbarRect =
            rollScrollbar ? QRect(rollScrollbar->mapTo(&view, QPoint{}), rollScrollbar->size())
                          : QRect{};
        check(initialRollGeometry && rollScrollbar &&
                  initialRollGeometry->plotRect.x() == view.timelineSplitX() &&
                  initialRollGeometry->plotRect.right() == initialRollGeometry->rect.right() &&
                  rollScrollbarRect.left() > initialRollGeometry->plotRect.right(),
              "Roll plot surface must exclude the vertical scrollbar");
        check(checks::support::physicalInputsMatchCanonical(
                  bandLayout, *quick, *quickRoot, songview::TimelineBand::Roll,
                  QStringLiteral("timelineRollInput"), QStringLiteral("timelineRollGutterInput")),
              "Roll plot and keyboard inputs should match their physical canonical surfaces");
        const auto &velocityGeometry = bandLayout.geometry(songview::TimelineBand::Velocity);
        const auto &rulerBandGeometry = bandLayout.geometry(songview::TimelineBand::Ruler);
        const auto &otherEventsGeometry = bandLayout.geometry(songview::TimelineBand::OtherEvents);
        check(velocityGeometry && rulerBandGeometry && otherEventsGeometry &&
                  velocityGeometry->plotRect.x() == view.timelineSplitX() &&
                  rulerBandGeometry->plotRect.x() == view.timelineSplitX() &&
                  otherEventsGeometry->plotRect.x() == view.timelineSplitX(),
              "canonical ruler, other-events, and velocity plotRects should start at the shared "
              "timeline split");
        const std::optional<QRect> canonicalVelocityBody =
            drawer ? drawer->bodyRect(EditorDrawerPage::Velocity) : std::nullopt;
        check(drawer && canonicalVelocityBody ==
                            std::optional<QRect>(
                                bandLayout.geometry(songview::TimelineBand::Velocity)->rect),
              "drawer body rectangle should map onto the canonical velocity rectangle");
        check(publishedQmlRectsMatchCanonical(*quick, *quickRoot, bandLayout),
              "published Quick band properties should translate the canonical layout");
        check(checks::support::physicalInputsMatchCanonical(
                  bandLayout, *quick, *quickRoot, songview::TimelineBand::Velocity,
                  QStringLiteral("timelineVelocityInput"),
                  QStringLiteral("timelineVelocityGutterInput")),
              "Velocity plot and keyboard inputs should match their physical canonical surfaces");
        const bool otherEventsInputMatchesCanonical = checks::support::physicalInputsMatchCanonical(
            bandLayout, *quick, *quickRoot, songview::TimelineBand::OtherEvents,
            QStringLiteral("timelineOtherEventsInput"),
            QStringLiteral("timelineOtherEventsGutterInput"));
        if (otherEventsInputMatchesCanonical) {
            check(otherEventsInputMatchesCanonical,
                  "Other Events plot and gutter inputs should match their physical surfaces");
        } else {
            const QString failureMessage =
                QStringLiteral("Other Events physical inputs should match the canonical split; %1")
                    .arg(canonicalInputFailureDetails(
                        view, *quick, *quickRoot, songview::TimelineBand::OtherEvents,
                        QStringLiteral("timelineOtherEventsInput"),
                        QStringLiteral("timelineOtherEventsGutterInput")));
            check(otherEventsInputMatchesCanonical, qUtf8Printable(failureMessage));
        }
        check(checks::support::physicalInputsMatchCanonical(
                  bandLayout, *quick, *quickRoot, songview::TimelineBand::Ruler,
                  QStringLiteral("timelineRulerInput"), QStringLiteral("timelineRulerGutterInput")),
              "Ruler plot and control-gutter inputs should match their physical surfaces");
        auto *otherEventsInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineOtherEventsInput"));
        const StripItem *hoveredStripItem = nullptr;
        QPointF hoveredStripPosition;
        if (otherEventsInput && otherEventsGeometry) {
            const QPoint quickOriginInSongView = quick->mapTo(&view, QPoint{});
            for (const StripItem &item : view.model().strip) {
                const qreal x =
                    view.camera().displayX(double(item.tick), otherEventsGeometry->plotRect.x(),
                                           otherEventsInput->devicePixelRatio());
                const QPointF markerPositionInSongView(x, otherEventsGeometry->rect.center().y());
                const QPointF markerPositionInQuickHost =
                    markerPositionInSongView -
                    QPointF(quickOriginInSongView.x(), quickOriginInSongView.y());
                const QPointF itemPosition =
                    otherEventsInput->mapFromScene(markerPositionInQuickHost);
                if (otherEventsInput->contains(itemPosition)) {
                    hoveredStripItem = &item;
                    hoveredStripPosition = itemPosition;
                    break;
                }
            }
        }
        if (hoveredStripItem) {
            check(hoveredStripItem,
                  "other-events fixture should provide a visible marker for Quick hover");
        } else {
            const QString failureMessage =
                QStringLiteral(
                    "other-events fixture should provide a visible marker for Quick hover; %1")
                    .arg(otherEventsHoverCandidateDetails(view, *quick, otherEventsInput,
                                                          otherEventsGeometry));
            check(hoveredStripItem, qUtf8Printable(failureMessage));
        }
        if (otherEventsInput && hoveredStripItem) {
            QToolTip::hideText();
            const QPointF windowPosition = otherEventsInput->mapToScene(hoveredStripPosition);
            QEnterEvent enter(windowPosition, windowPosition,
                              QPointF(quick->quickWindow()->mapToGlobal(windowPosition.toPoint())));
            QCoreApplication::sendEvent(quick->quickWindow(), &enter);
            QMouseEvent hoverMove(
                QEvent::MouseMove, windowPosition,
                QPointF(quick->quickWindow()->mapToGlobal(windowPosition.toPoint())), Qt::NoButton,
                Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(quick->quickWindow(), &hoverMove);
            QCoreApplication::processEvents();
            check(QToolTip::text().contains(hoveredStripItem->label),
                  "Other Events Quick hover should show the matching native tooltip");
            const QPointF outsidePosition = quickRoot->property("rulerBandRect").toRectF().center();
            QMouseEvent hoverAway(
                QEvent::MouseMove, outsidePosition,
                QPointF(quick->quickWindow()->mapToGlobal(outsidePosition.toPoint())), Qt::NoButton,
                Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(quick->quickWindow(), &hoverAway);
            const auto tooltipHidden = checks::async_wait::waitUntil(
                [] { return true; }, [] { return QToolTip::text().isEmpty(); }, 1000);
            check(tooltipHidden == checks::async_wait::Result::Ready,
                  "Other Events Quick leave should hide the native tooltip");
        }

        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false);
        pumpZeroDelayTimers();

        const QRect hiddenUnion = canonicalVisibleUnion();
        check(!hiddenUnion.isEmpty() && quick->geometry() == hiddenUnion && quick->isVisible(),
              "Quick host geometry should exclude a hidden band's rectangle");
        check(!bandLayout.geometry(songview::TimelineBand::Velocity),
              "hidden velocity band should leave a nullopt canonical entry");
        check(!quickRoot->property("velocityBandVisible").toBool() &&
                  quickRoot->property("velocityBandRect").toRectF().isEmpty(),
              "hidden velocity band should publish no retained Quick rectangle");
        auto *velocityInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityInput"));
        auto *velocityGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityGutterInput"));
        check(velocityInput && !velocityInput->isVisible() && velocityGutterInput &&
                  !velocityGutterInput->isVisible(),
              "hidden velocity band should keep both physical input items invisible");
        auto *voiceInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVoiceChangesInput"));
        auto *voiceGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVoiceChangesGutterInput"));
        check(voiceInput && !voiceInput->isVisible() && voiceGutterInput &&
                  !voiceGutterInput->isVisible() &&
                  !bandLayout.geometry(songview::TimelineBand::VoiceChanges),
              "hidden voice changes band should keep both inputs invisible and no canonical entry");
        auto *automationInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        auto *automationGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationGutterInput"));
        check(automationInput && !automationInput->isVisible() && automationGutterInput &&
                  !automationGutterInput->isVisible() &&
                  !bandLayout.geometry(songview::TimelineBand::Automation),
              "hidden automation band should keep both inputs invisible and no canonical entry");
        for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
            const auto &geometry = bandLayout.geometry(names.band);
            if (!geometry || names.band == songview::TimelineBand::TrackHeaders)
                continue;
            const int plotStart = geometry->plotRect.x();
            const QString message =
                QStringLiteral("%1 plotRect after drawer hide must start at timelineSplitX %2 "
                               "and own its band's right edge")
                    .arg(QString::fromLatin1(names.rectProperty))
                    .arg(view.timelineSplitX());
            check(!geometry->rect.isEmpty() && !geometry->plotRect.isEmpty() &&
                      plotStart == view.timelineSplitX() &&
                      geometry->plotRect.right() == geometry->rect.right(),
                  qUtf8Printable(message));
        }
        const auto &hiddenHeaders = bandLayout.geometry(songview::TimelineBand::TrackHeaders);
        const auto &hiddenRoll = bandLayout.geometry(songview::TimelineBand::Roll);
        check(hiddenHeaders && hiddenHeaders->plotRect.isEmpty(),
              "TrackHeaders must retain an empty plotRect after drawer hide");
        check(hiddenRoll && rollScrollbar &&
                  hiddenRoll->plotRect.right() == hiddenRoll->rect.right() &&
                  rollScrollbarRect.left() > hiddenRoll->plotRect.right(),
              "Roll rect and plotRect must remain outside the scrollbar after drawer hide");
        const QFont originalHostFont = view.font();
        QFont distinctHostFont = originalHostFont;
        distinctHostFont.setItalic(!originalHostFont.italic());
        const QPalette originalHostPalette = view.palette();
        QPalette distinctHostPalette = originalHostPalette;
        distinctHostPalette.setColor(
            QPalette::WindowText, originalHostPalette.color(QPalette::WindowText) == QColor(Qt::red)
                                      ? Qt::blue
                                      : Qt::red);
        view.setFont(distinctHostFont);
        view.setPalette(distinctHostPalette);
        pumpZeroDelayTimers();
        check(voiceInput && voiceInput->font() == distinctHostFont &&
                  voiceInput->palette() == distinctHostPalette && velocityInput &&
                  velocityInput->font() == distinctHostFont &&
                  velocityInput->palette() == distinctHostPalette,
              "Quick input host must publish the SongView font and palette");
        view.setFont(originalHostFont);
        view.setPalette(originalHostPalette);
        pumpZeroDelayTimers();

        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        pumpZeroDelayTimers();
        const QRect shownUnion = canonicalVisibleUnion();
        const std::optional<songview::TimelineBandGeometry> &shownVelocityGeometry =
            bandLayout.geometry(songview::TimelineBand::Velocity);
        check(!shownUnion.isEmpty() && quick->geometry() == shownUnion && quick->isVisible() &&
                  shownVelocityGeometry.has_value(),
              "Quick host geometry should resume from the shown band's current rectangle");
        const bool shownVelocityInputMatchesCanonical =
            quickRoot->property("velocityBandVisible").toBool() &&
            checks::support::physicalInputsMatchCanonical(
                bandLayout, *quick, *quickRoot, songview::TimelineBand::Velocity,
                QStringLiteral("timelineVelocityInput"),
                QStringLiteral("timelineVelocityGutterInput"));
        if (shownVelocityInputMatchesCanonical) {
            check(shownVelocityInputMatchesCanonical,
                  "shown velocity band should republish both physical input surfaces");
        } else {
            const QString failureMessage =
                QStringLiteral(
                    "shown velocity physical inputs should match the canonical split; %1")
                    .arg(canonicalInputFailureDetails(
                        view, *quick, *quickRoot, songview::TimelineBand::Velocity,
                        QStringLiteral("timelineVelocityInput"),
                        QStringLiteral("timelineVelocityGutterInput")));
            check(shownVelocityInputMatchesCanonical, qUtf8Printable(failureMessage));
        }
        for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
            const auto &geometry = bandLayout.geometry(names.band);
            if (!geometry || names.band == songview::TimelineBand::TrackHeaders)
                continue;
            const int plotStart = geometry->plotRect.x();
            const QString message =
                QStringLiteral("%1 plotRect after Velocity show must start at timelineSplitX %2 "
                               "and own its band's right edge")
                    .arg(QString::fromLatin1(names.rectProperty))
                    .arg(view.timelineSplitX());
            check(!geometry->rect.isEmpty() && !geometry->plotRect.isEmpty() &&
                      plotStart == view.timelineSplitX() &&
                      geometry->plotRect.right() == geometry->rect.right(),
                  qUtf8Printable(message));
        }
        const auto &shownHeaders = bandLayout.geometry(songview::TimelineBand::TrackHeaders);
        const auto &shownRoll = bandLayout.geometry(songview::TimelineBand::Roll);
        check(shownHeaders && shownHeaders->plotRect.isEmpty(),
              "TrackHeaders must retain an empty plotRect after Velocity show");
        check(shownVelocityGeometry && shownHeaders &&
                  !gutterRect(*shownVelocityGeometry).isEmpty() &&
                  shownVelocityGeometry->rect.x() == shownHeaders->rect.width() &&
                  gutterRect(*shownVelocityGeometry).width() == view.pianoKeyboardWidth() &&
                  shownVelocityGeometry->plotRect.x() == view.timelineSplitX() &&
                  shownVelocityGeometry->plotRect.right() == shownVelocityGeometry->rect.right(),
              "Shown Velocity gutter must span the piano-key column after TrackHeaders");
        check(shownRoll && rollScrollbar &&
                  shownRoll->plotRect.right() == shownRoll->rect.right() &&
                  rollScrollbarRect.left() > shownRoll->plotRect.right(),
              "Roll rect and plotRect must remain outside the scrollbar after Velocity show");
        check(quick->geometry() == canonicalVisibleUnion(),
              "reshown velocity band should re-enter the canonical layout");
        view.focusTimelineBand(songview::TimelineBand::Velocity, Qt::MouseFocusReason);
        pumpZeroDelayTimers();
        check(view.focusedTimelineBand() == songview::TimelineBand::Velocity,
              "velocity focus bridge did not focus the Quick input item");
        check(velocityInput && !velocityInput->accessibilityDescription().isEmpty(),
              "velocity input should expose its accessibility description");
        QString canonicalCropError;
        const QImage canonicalVelocityCrop = checks::support::captureQuickBand(
            view, shownVelocityGeometry->rect, &canonicalCropError);
        check(canonicalCropError.isEmpty() && !canonicalVelocityCrop.isNull(),
              "canonical velocity rectangle should address a valid Quick framebuffer region");
        check(publishedQmlRectsMatchCanonical(*quick, *quickRoot, bandLayout),
              "republished Quick band properties should translate the canonical layout");
        // Event-list toggle: the stack index swap must explicitly
        // synchronize — the canonical roll entry clears while the list
        // replaces the roll, and the Quick host plus QML band properties
        // follow both ways without any resize.
        const bool eventListWasVisible = view.eventListVisible();
        view.setEventListVisible(true);
        pumpZeroDelayTimers();
        auto *eventListRollInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollInput"));
        auto *eventListRollGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollGutterInput"));
        check(!bandLayout.geometry(songview::TimelineBand::Roll) && eventListRollInput &&
                  !eventListRollInput->isVisible() && eventListRollGutterInput &&
                  !eventListRollGutterInput->isVisible() && quick->isVisible() &&
                  quick->geometry() == canonicalVisibleUnion() &&
                  publishedQmlRectsMatchCanonical(*quick, *quickRoot, bandLayout),
              "event-list view should clear the Roll geometry and both physical inputs");
        for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
            const auto &geometry = bandLayout.geometry(names.band);
            if (!geometry || names.band == songview::TimelineBand::TrackHeaders)
                continue;
            const int plotStart = geometry->plotRect.x();
            const QString message =
                QStringLiteral("%1 plotRect in event-list mode must start at timelineSplitX %2 "
                               "and own its band's right edge")
                    .arg(QString::fromLatin1(names.rectProperty))
                    .arg(view.timelineSplitX());
            check(!geometry->rect.isEmpty() && !geometry->plotRect.isEmpty() &&
                      plotStart == view.timelineSplitX() &&
                      geometry->plotRect.right() == geometry->rect.right(),
                  qUtf8Printable(message));
        }
        const auto &eventListHeaders = bandLayout.geometry(songview::TimelineBand::TrackHeaders);
        check(eventListHeaders && eventListHeaders->plotRect.isEmpty(),
              "TrackHeaders must retain an empty plotRect in event-list mode");
        const auto &eventListVelocity = bandLayout.geometry(songview::TimelineBand::Velocity);
        check(eventListVelocity && eventListHeaders && !gutterRect(*eventListVelocity).isEmpty() &&
                  eventListVelocity->rect.x() == eventListHeaders->rect.width() &&
                  gutterRect(*eventListVelocity).width() == view.pianoKeyboardWidth() &&
                  eventListVelocity->plotRect.x() == view.timelineSplitX() &&
                  eventListVelocity->plotRect.right() == eventListVelocity->rect.right(),
              "Velocity gutter must span the piano-key column in event-list mode");
        view.setEventListVisible(eventListWasVisible);
        pumpZeroDelayTimers();
        check(quick->geometry() == canonicalVisibleUnion() &&
                  publishedQmlRectsMatchCanonical(*quick, *quickRoot, bandLayout),
              "restored roll view should republish the canonical roll entry and Quick geometry");
        for (const QmlBandPropertyNames &names : qmlBandPropertyNames) {
            const auto &geometry = bandLayout.geometry(names.band);
            if (!geometry || names.band == songview::TimelineBand::TrackHeaders)
                continue;
            const int plotStart = geometry->plotRect.x();
            const QString message =
                QStringLiteral("%1 plotRect after roll restore must start at timelineSplitX %2 "
                               "and own its band's right edge")
                    .arg(QString::fromLatin1(names.rectProperty))
                    .arg(view.timelineSplitX());
            check(!geometry->rect.isEmpty() && !geometry->plotRect.isEmpty() &&
                      plotStart == view.timelineSplitX() &&
                      geometry->plotRect.right() == geometry->rect.right(),
                  qUtf8Printable(message));
        }
        const auto &restoredHeaders = bandLayout.geometry(songview::TimelineBand::TrackHeaders);
        const auto &restoredVelocity = bandLayout.geometry(songview::TimelineBand::Velocity);
        const auto &restoredRoll = bandLayout.geometry(songview::TimelineBand::Roll);
        check(restoredHeaders && restoredHeaders->plotRect.isEmpty(),
              "TrackHeaders must retain an empty plotRect after roll restore");
        check(restoredVelocity && restoredHeaders && !gutterRect(*restoredVelocity).isEmpty() &&
                  restoredVelocity->rect.x() == restoredHeaders->rect.width() &&
                  gutterRect(*restoredVelocity).width() == view.pianoKeyboardWidth() &&
                  restoredVelocity->plotRect.x() == view.timelineSplitX() &&
                  restoredVelocity->plotRect.right() == restoredVelocity->rect.right(),
              "Velocity gutter must span the piano-key column after roll restore");
        check(restoredRoll && rollScrollbar &&
                  restoredRoll->plotRect.right() == restoredRoll->rect.right() &&
                  rollScrollbarRect.left() > restoredRoll->plotRect.right(),
              "Roll rect and plotRect must remain outside the scrollbar after roll restore");
    }
    const std::optional<songview::TimelineBandGeometry> captureOtherEventsGeometry =
        view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
    check(captureOtherEventsGeometry.has_value(),
          "Other Events band should remain visible before Quick capture");
    if (captureOtherEventsGeometry) {
        QString stripCaptureError;
        const QImage stripWithoutLoopMarkers = checks::support::captureQuickBand(
            view, captureOtherEventsGeometry->rect, &stripCaptureError);
        const bool stripCaptureSucceeded =
            stripCaptureError.isEmpty() && !stripWithoutLoopMarkers.isNull();
        if (stripCaptureSucceeded) {
            check(stripCaptureSucceeded, "Other Events strip Quick capture should succeed");
        } else {
            const QString failureMessage =
                QStringLiteral("Other Events strip Quick capture should succeed; error=%1 "
                               "requested-SongView=%2 captured=%3 %4")
                    .arg(stripCaptureError.isEmpty() ? QStringLiteral("<none>") : stripCaptureError)
                    .arg(describeRect(captureOtherEventsGeometry->rect))
                    .arg(imageDetails(stripWithoutLoopMarkers))
                    .arg(quickHostGeometryDetails(*quick));
            check(stripCaptureSucceeded, qUtf8Printable(failureMessage));
        }
        document.setLoopTick(false, 6);
        document.setLoopTick(true, 18);
        std::unique_ptr<MidiTimeline> loopTimeline = document.buildTimeline(44100.0);
        check(loopTimeline && loopTimeline->loopStartTick == 6 && loopTimeline->loopEndTick == 18,
              "fixture loop markers should reach the timeline");
        if (loopTimeline) {
            view.updateSong(loopTimeline.get());
            timeline = std::move(loopTimeline);
            QCoreApplication::processEvents();
            const std::optional<songview::TimelineBandGeometry> loopOtherEventsGeometry =
                view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
            QString loopCaptureError;
            const QImage stripWithLoopMarkers =
                loopOtherEventsGeometry
                    ? checks::support::captureQuickBand(view, loopOtherEventsGeometry->rect,
                                                        &loopCaptureError)
                    : QImage{};
            const bool loopMarkersRemainOutsideStrip =
                loopOtherEventsGeometry && loopCaptureError.isEmpty() &&
                !stripWithLoopMarkers.isNull() && stripWithLoopMarkers == stripWithoutLoopMarkers;
            if (loopMarkersRemainOutsideStrip) {
                check(loopMarkersRemainOutsideStrip,
                      "loop markers should not appear in the Other Events strip");
            } else {
                const QString failureMessage =
                    QStringLiteral(
                        "loop markers should not appear in the Other Events strip; "
                        "baseline-canonical-SongView=%1 baseline-captured=%2 baseline-error=%3 "
                        "loop-canonical-SongView=%4 loop-captured=%5 loop-error=%6 %7")
                        .arg(describeRect(captureOtherEventsGeometry->rect))
                        .arg(imageDetails(stripWithoutLoopMarkers))
                        .arg(stripCaptureError.isEmpty() ? QStringLiteral("<none>")
                                                         : stripCaptureError)
                        .arg(loopOtherEventsGeometry ? describeRect(loopOtherEventsGeometry->rect)
                                                     : QStringLiteral("<missing>"))
                        .arg(imageDetails(stripWithLoopMarkers))
                        .arg(loopCaptureError.isEmpty() ? QStringLiteral("<none>")
                                                        : loopCaptureError)
                        .arg(quickHostGeometryDetails(*quick));
                check(loopMarkersRemainOutsideStrip, qUtf8Printable(failureMessage));
            }
        }
    }
    view.setDrawerActivePage(EditorDrawerPage::Automations);
    view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
    QCoreApplication::processEvents();
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    auto *automation = automationCanvas(view);
    auto *automationPage = drawer ? drawer->automationPage() : nullptr;
    const songview::TimelineBandLayout &bandLayout = view.timelineBandLayout();
    check(automation != nullptr && automationPage != nullptr,
          "host should construct the Automation and Voice Changes timeline surfaces");
    check(qobject_cast<QWidget *>(drawer) == nullptr &&
              qobject_cast<QWidget *>(automationPage) == nullptr,
          "drawer and automation scroll state must be QObjects without QWidget shells");
    if (automation && automationPage) {
        auto *automationInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        auto *automationGutterInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationGutterInput"));
        check(automationInput && automationGutterInput && automationInput->isVisible() &&
                  automationGutterInput->isVisible() &&
                  automationInput->interaction() == automation &&
                  automationGutterInput->interaction() == automation,
              "Automation should expose plot and gutter inputs for the page canvas");
        const bool automationInputMatchesCanonical = checks::support::physicalInputsMatchCanonical(
            bandLayout, *quick, *quickRoot, songview::TimelineBand::Automation,
            QStringLiteral("timelineAutomationInput"),
            QStringLiteral("timelineAutomationGutterInput"));
        if (automationInputMatchesCanonical) {
            check(automationInputMatchesCanonical,
                  "Automation inputs should match their physical canonical surfaces");
        } else {
            const QString failureMessage =
                QStringLiteral("Automation physical inputs should match the canonical split; %1")
                    .arg(canonicalInputFailureDetails(
                        view, *quick, *quickRoot, songview::TimelineBand::Automation,
                        QStringLiteral("timelineAutomationInput"),
                        QStringLiteral("timelineAutomationGutterInput")));
            check(automationInputMatchesCanonical, qUtf8Printable(failureMessage));
        }
        const std::optional<songview::TimelineBandGeometry> &automationGeometry =
            bandLayout.geometry(songview::TimelineBand::Automation);
        const DrawerChrome &chrome = drawer->chrome();
        const QRectF automationScrollbarRect = chrome.automationScrollbarRect();
        check(automationGeometry.has_value() && !automationScrollbarRect.isEmpty() &&
                  chrome.scrollbarWidth() == layout::space(layout::Space::Two) &&
                  automationScrollbarRect.width() == layout::space(layout::Space::Two) &&
                  automationScrollbarRect.right() == automationGeometry->rect.x(),
              "DrawerChrome should publish the Quick automation scrollbar as the band's left "
              "column");
        check(automationGeometry && automationGeometry->plotRect.x() == view.timelineSplitX() &&
                  automationGeometry->plotRect.y() == automationGeometry->rect.y() &&
                  automationGeometry->plotRect.height() == automationGeometry->rect.height() &&
                  automationGeometry->plotRect.right() == automationGeometry->rect.right(),
              "Automation plotRect must cover the plot side from timelineSplitX");
        check(automationGeometry &&
                  automationScrollbarRect.right() <= automationGeometry->rect.x() &&
                  automationScrollbarRect.right() < automationGeometry->plotRect.x(),
              "Automation scrollbar must remain outside the rect and left of plotRect");
        check(checks::support::quickWindowIsUnmasked(*quick),
              "the shared Quick window must stay unmasked around the automation scrollbar");
        const QRect automationGutter =
            automationGeometry ? gutterRect(*automationGeometry) : QRect{};
        const QPointF automationGutterProbe =
            automationGutterInput ? automationGutterInput->bounds().center() : QPointF{};
        const QPoint automationGutterSongView =
            automationGutterInput
                ? quick->geometry().topLeft() +
                      automationGutterInput->mapToItem(quickRoot, automationGutterProbe).toPoint()
                : QPoint{};
        const bool automationGutterVisible =
            automationGutterInput && automationGutterInput->isVisible() &&
            automationGutterInput->bounds().contains(automationGutterProbe) &&
            automationGutter.contains(automationGutterSongView) &&
            checks::support::quickWindowIsUnmasked(*quick);
        check(automationGutterVisible,
              "the Automation gutter input should expose a local probe in its fixed surface");
        if (automationInput) {
            const uint64_t panRevision = document.revision();
            const int panUndo = document.undoStack()->count();
            const QPointF panPress(automationInput->width() / 2.0, automationInput->height() / 2.0);
            const auto sendAutomationWindowMouse = [&](QEvent::Type type, const QPointF &position,
                                                       Qt::MouseButton button,
                                                       Qt::MouseButtons buttons) {
                QQuickWindow *const window = quick->quickWindow();
                const QPointF windowPosition = automationInput->mapToScene(position);
                QMouseEvent event(type, windowPosition,
                                  QPointF(window->mapToGlobal(windowPosition.toPoint())), button,
                                  buttons, Qt::NoModifier);
                QCoreApplication::sendEvent(window, &event);
            };
            sendAutomationWindowMouse(QEvent::MouseButtonPress, panPress, Qt::MiddleButton,
                                      Qt::MiddleButton);
            pumpZeroDelayTimers();
            check(view.focusedTimelineBand() == songview::TimelineBand::Automation &&
                      quick->quickWindow()->mouseGrabberItem() == automationInput &&
                      automation->isPanning(),
                  "automation pan press should focus, grab, and start panning through Quick");
            const QPointF rulerScenePosition =
                quickRoot->property("rulerBandRect").toRectF().center();
            sendAutomationWindowMouse(QEvent::MouseMove,
                                      automationInput->mapFromScene(rulerScenePosition),
                                      Qt::NoButton, Qt::MiddleButton);
            check(quick->quickWindow()->mouseGrabberItem() == automationInput &&
                      automation->isPanning(),
                  "pointer grab should remain on the pressed band across another band");
            QFocusEvent panFocusOut(QEvent::FocusOut, Qt::OtherFocusReason);
            QApplication::sendEvent(automationInput, &panFocusOut);
            check(automation->isPanning(),
                  "automation pan should ignore input focus loss like the native canvas");
            QEvent panDeactivate(QEvent::WindowDeactivate);
            QApplication::sendEvent(quick->quickWindow(), &panDeactivate);
            check(!automation->isPanning(),
                  "Quick-window deactivation should cancel the automation pan gesture");
            sendAutomationWindowMouse(QEvent::MouseButtonRelease, panPress, Qt::MiddleButton,
                                      Qt::NoButton);
            check(document.revision() == panRevision && document.undoStack()->count() == panUndo,
                  "automation pan integration should complete without document mutation");
        }
        const int selectedTrack = view.selectionModel().primaryTrack();
        view.setTrackSolo(selectedTrack, false);
        auto *velocityInput = quickRoot->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityInput"));
        check(velocityInput != nullptr, "Quick root must expose timelineVelocityInput");
        if (velocityInput) {
            QKeyEvent soloKey(QEvent::KeyPress, Qt::Key_S, Qt::NoModifier);
            QApplication::sendEvent(velocityInput, &soloKey);
            if (!soloKey.isAccepted())
                QApplication::sendEvent(&view, &soloKey);
            check(view.trackSoloed(selectedTrack),
                  "S from the velocity drawer did not solo the selected track");
            view.setTrackSolo(selectedTrack, false);
        }

        view.selectionModel().clearNoteSelection();
        view.setEditCursorTick(0);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Square 1"),
              "velocity map should resolve the edit-cursor voice while stopped");

        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Noise"),
              "visible velocity page should immediately resolve the playback voice");
        const auto warmVelocity = area->diagnostics();
        for (int tick = 25; tick < 27; ++tick)
            view.setPlayheadSample(timeline->sampleForTick(uint64_t(tick)), true);
        QCoreApplication::processEvents();
        check(area->diagnostics().contentBuildCount == warmVelocity.contentBuildCount &&
                  area->diagnostics().playheadPresentationCount ==
                      warmVelocity.playheadPresentationCount + 2,
              "steady same-context playback should not rebuild visible velocity content");

        view.setPlayheadSample(timeline->sampleForTick(26), false);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Square 1"),
              "stopping should return visible velocity map to the edit cursor");
        view.setPlayheadSample(timeline->sampleForTick(12), true);
        QCoreApplication::processEvents();
        const auto velocityBeforeCrossing = area->diagnostics();
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(QString::fromLatin1(area->axis().map().voiceName()) == QStringLiteral("Noise") &&
                  area->diagnostics().contentBuildCount >
                      velocityBeforeCrossing.contentBuildCount &&
                  area->diagnostics().playheadPresentationCount ==
                      velocityBeforeCrossing.playheadPresentationCount + 1,
              "visible velocity map should refresh and present once across a voice change");

        view.setPlayheadSample(timeline->sampleForTick(24), false);
        view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
        QCoreApplication::processEvents();
        check(checks::support::quickWindowIsUnmasked(*quick),
              "the shared Quick window must remain unmasked after opening Voice Changes");
        const std::optional<songview::TimelineBandGeometry> &voiceGeometry =
            bandLayout.geometry(songview::TimelineBand::VoiceChanges);
        check(voiceGeometry && !gutterRect(*voiceGeometry).isEmpty() &&
                  voiceGeometry->plotRect.x() == view.timelineSplitX() &&
                  voiceGeometry->plotRect.y() == voiceGeometry->rect.y() &&
                  voiceGeometry->plotRect.height() == voiceGeometry->rect.height() &&
                  voiceGeometry->plotRect.right() == voiceGeometry->rect.right(),
              "Voice Changes must expose separate fixed gutter and plot surfaces");
        const bool voiceInputMatchesCanonical =
            voiceGeometry && quickRoot->property("voiceChangesBandVisible").toBool() &&
            checks::support::physicalInputsMatchCanonical(
                bandLayout, *quick, *quickRoot, songview::TimelineBand::VoiceChanges,
                QStringLiteral("timelineVoiceChangesInput"),
                QStringLiteral("timelineVoiceChangesGutterInput"));
        if (voiceInputMatchesCanonical) {
            check(voiceInputMatchesCanonical,
                  "Voice Changes should expose canonical plot and gutter inputs");
        } else {
            const QString failureMessage =
                QStringLiteral("Voice Changes physical inputs should match the canonical split; %1")
                    .arg(canonicalInputFailureDetails(
                        view, *quick, *quickRoot, songview::TimelineBand::VoiceChanges,
                        QStringLiteral("timelineVoiceChangesInput"),
                        QStringLiteral("timelineVoiceChangesGutterInput")));
            check(voiceInputMatchesCanonical, qUtf8Printable(failureMessage));
        }
        const QImage editCursorVoiceContext =
            checks::support::captureQuickBand(view, voiceGeometry->rect);
        const QImage editCursorAutomation =
            checks::support::captureQuickBand(view, automationGeometry->rect);
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        const QImage playbackVoiceContext =
            checks::support::captureQuickBand(view, voiceGeometry->rect);
        const QImage playbackAutomation =
            checks::support::captureQuickBand(view, automationGeometry->rect);
        check(!editCursorAutomation.isNull() && playbackVoiceContext != editCursorVoiceContext &&
                  playbackAutomation == editCursorAutomation,
              "visible Voice Changes should resolve playback voice without refreshing Automation");
        const QImage warmAutomation =
            checks::support::captureQuickBand(view, automationGeometry->rect);
        const QImage warmVoiceContext =
            checks::support::captureQuickBand(view, voiceGeometry->rect);
        for (int tick = 25; tick < 27; ++tick)
            view.setPlayheadSample(timeline->sampleForTick(uint64_t(tick)), true);
        QCoreApplication::processEvents();
        check(checks::support::captureQuickBand(view, voiceGeometry->rect) == warmVoiceContext &&
                  checks::support::captureQuickBand(view, automationGeometry->rect) ==
                      warmAutomation,
              "steady same-voice playback should keep Voice Changes and Automation stable");

        view.setPlayheadSample(timeline->sampleForTick(26), false);
        QCoreApplication::processEvents();
        check(checks::support::captureQuickBand(view, voiceGeometry->rect) ==
                      editCursorVoiceContext &&
                  checks::support::captureQuickBand(view, automationGeometry->rect) ==
                      editCursorAutomation,
              "stopping should return Voice Changes to the edit-cursor voice only");
        view.setPlayheadSample(timeline->sampleForTick(12), true);
        QCoreApplication::processEvents();
        const QImage squarePlaybackVoiceContext =
            checks::support::captureQuickBand(view, voiceGeometry->rect);
        const QImage automationBeforeCrossing =
            checks::support::captureQuickBand(view, automationGeometry->rect);
        view.setPlayheadSample(timeline->sampleForTick(24), true);
        QCoreApplication::processEvents();
        check(checks::support::captureQuickBand(view, voiceGeometry->rect) !=
                      squarePlaybackVoiceContext &&
                  checks::support::captureQuickBand(view, automationGeometry->rect) ==
                      automationBeforeCrossing,
              "Voice Changes should refresh across a program change without refreshing Automation");
        view.setPlayheadSample(timeline->sampleForTick(24), false);
        QCoreApplication::processEvents();
        if (automationGutterInput && automation->laneBody(LaneHandle{0}).isEmpty()) {
            const QPointF tempoHeaderPoint(automationGutterInput->bounds().center().x(),
                                           automation->pinnedTempoRect().center().y() -
                                               automationPage->verticalScroll());
            checks::events::sendMouse(*automationGutterInput, QEvent::MouseButtonPress,
                                      tempoHeaderPoint, Qt::LeftButton, Qt::LeftButton,
                                      Qt::NoModifier);
            checks::events::sendMouse(*automationGutterInput, QEvent::MouseButtonRelease,
                                      tempoHeaderPoint, Qt::LeftButton, Qt::NoButton,
                                      Qt::NoModifier);
            QCoreApplication::processEvents();
        }
        const qreal pinnedTempoPlotY = qreal(automation->laneBody(LaneHandle{0}).center().y() -
                                             automationPage->verticalScroll());
        const QPointF menuStart(4.0, pinnedTempoPlotY);
        const QPointF menuEnd = menuStart + QPointF(48.0, 0.0);
        checks::events::sendMouse(*automationInput, QEvent::MouseButtonPress, menuStart,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*automationInput, QEvent::MouseMove, menuEnd, Qt::NoButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*automationInput, QEvent::MouseButtonRelease, menuEnd,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        const auto &dragSelection = view.selectionModel().timeSelection();
        const qreal menuFirst = view.camera().displayX(double(dragSelection.startTick), 0,
                                                       automationInput->devicePixelRatio());
        const qreal menuLast = view.camera().displayX(double(dragSelection.endTick), 0,
                                                      automationInput->devicePixelRatio());
        const QPointF menuPoint((menuFirst + menuLast) / 2.0, menuStart.y());
        checks::events::sendMouse(*automationInput, QEvent::MouseButtonPress, menuPoint,
                                  Qt::RightButton, Qt::RightButton, Qt::NoModifier);
        QTimer::singleShot(0, [] {
            if (auto *menu = qobject_cast<QMenu *>(QApplication::activePopupWidget()))
                menu->close();
        });
        checks::events::sendMouse(*automationInput, QEvent::MouseButtonRelease, menuPoint,
                                  Qt::RightButton, Qt::NoButton, Qt::NoModifier);
        const songview::EditorSelectionModel::TimeSelection &menuSelection =
            view.selectionModel().timeSelection();
        check(menuSelection.active() &&
                  menuSelection.scope == songview::EditorSelectionModel::TimeSelection::Lanes &&
                  menuSelection.tempo && menuSelection.lanes.empty(),
              "automation range menu should delegate its Tempo scope to the host");
        view.selectionModel().clearTimeSelection();
    }

    check(document.moveTrack(0, 1), "fixture track move should succeed");
    const EditorAutomationRowId movedLane{EditorAutomationRowKind::ControlChange, 1, 74};
    check(view.editorViewState().emptyLanes.count(movedLane) == 1,
          "track remap should reach hosted cosmetics before document refresh");
    std::unique_ptr<MidiTimeline> remappedTimeline = document.buildTimeline(44100.0);
    view.updateSong(remappedTimeline.get());
    timeline = std::move(remappedTimeline);

    std::vector<DocNote> notes = document.notesForTrack(view.selectionModel().primaryTrack());
    check(notes.size() == 2, "remapped selected track should retain duplicate-note identities");
    if (notes.size() != 2)
        return 1;

    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 200);
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(1);
    QCoreApplication::processEvents();
    auto *velocityInput = quickRoot->findChild<songview::TimelineInputItem *>(
        QStringLiteral("timelineVelocityInput"));
    check(velocityInput != nullptr,
          "Quick root must expose timelineVelocityInput for gesture checks");
    const double velocityHeight = velocityInput ? velocityInput->height() : 200.0;

    const QPointF firstNode = nodePosition(view, *area, *timeline, notes[0]);
    const std::vector<NoteId> selected = view.selectionModel().noteSelection();
    std::vector<NoteVelocity> unchangedVelocities;
    unchangedVelocities.reserve(notes.size());
    for (const DocNote &note : notes)
        unchangedVelocities.push_back({note.noteId, note.velocity});
    const uint64_t revisionBeforeNoChange = document.revision();
    const int undoBeforeNoChange = document.undoStack()->count();
    const bool beganNoChange = view.beginVelocityGesture(notes);
    const bool updatedNoChange = view.updateVelocityGesture(unchangedVelocities);
    const auto committedNoChange = view.commitVelocityGesture();
    const std::vector<DocNote> notesAfterNoChange =
        document.notesForTrack(view.selectionModel().primaryTrack());
    check(beganNoChange && !updatedNoChange &&
              committedNoChange == SongView::VelocityCommitResult::Unchanged &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[1].noteId) &&
              document.revision() == revisionBeforeNoChange &&
              document.undoStack()->count() == undoBeforeNoChange &&
              notesAfterNoChange.size() == notes.size() &&
              notesAfterNoChange[0].velocity == notes[0].velocity &&
              notesAfterNoChange[1].velocity == notes[1].velocity &&
              view.selectionModel().noteSelection() == selected,
          "host no-op gesture should preserve preview, revision, MIDI, Undo, and selection");
    const int undoBeforeChange = document.undoStack()->count();
    const uint64_t revisionBeforeChange = document.revision();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, firstNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                  firstNode + QPointF(0.0, -velocityHeight), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
    }
    const auto heldFirstPreview = view.previewVelocity(notes[0].noteId);
    const auto heldSecondPreview = view.previewVelocity(notes[1].noteId);
    DocNote heldFirst;
    DocNote heldSecond;
    check(document.findNote(notes[0].noteId, &heldFirst) &&
              document.findNote(notes[1].noteId, &heldSecond) &&
              heldFirst.velocity == notes[0].velocity && heldSecond.velocity == notes[1].velocity &&
              heldFirstPreview && heldSecondPreview && *heldFirstPreview != notes[0].velocity &&
              *heldSecondPreview != notes[1].velocity &&
              document.revision() == revisionBeforeChange &&
              document.undoStack()->count() == undoBeforeChange,
          "velocity host moves must update preview without changing document history");
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  firstNode + QPointF(0.0, -velocityHeight), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
    }
    DocNote committedFirst;
    DocNote committedSecond;
    check(document.revision() == revisionBeforeChange + 1 &&
              document.undoStack()->count() == undoBeforeChange + 1 &&
              document.findNote(notes[0].noteId, &committedFirst) &&
              document.findNote(notes[1].noteId, &committedSecond) && heldFirstPreview &&
              heldSecondPreview && committedFirst.velocity == *heldFirstPreview &&
              committedSecond.velocity == *heldSecondPreview &&
              !view.previewVelocity(notes[0].noteId) && !view.previewVelocity(notes[1].noteId) &&
              view.selectionModel().noteSelection() == selected,
          "velocity host release should commit one exact batch, clear preview, and preserve "
          "selection");

    document.undoStack()->undo();
    check(view.selectionModel().noteSelection() == selected &&
              document.undoStack()->count() == undoBeforeChange + 1,
          "undo should preserve shared selection while retaining the exact velocity history entry");
    document.undoStack()->redo();

    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId, notes[1].noteId});
    view.setEditCursorTick(2);
    QCoreApplication::processEvents();
    const QPointF unchangedNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeNoOp = document.revision();
    const int undoBeforeNoOp = document.undoStack()->count();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, unchangedNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease, unchangedNode,
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    }
    check(document.revision() == revisionBeforeNoOp &&
              document.undoStack()->count() == undoBeforeNoOp &&
              view.selectionModel().noteSelection().size() == 1 &&
              std::find(selected.cbegin(), selected.cend(),
                        view.selectionModel().noteSelection().front()) != selected.cend(),
          "unchanged stacked-node click should leave history untouched and collapse selection");

    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection(selected);
    view.setEditCursorTick(3);
    QCoreApplication::processEvents();
    const QPointF staleNode = nodePosition(view, *area, *timeline, notes[0]);
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, staleNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    }
    const uint64_t revisionBeforeExternalChange = document.revision();
    const int secondVelocity = notes[1].velocity == 127 ? 1 : 127;
    document.blockSignals(true);
    document.setNotesVelocity({notes[1]}, uint8_t(secondVelocity));
    document.blockSignals(false);
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                  staleNode + QPointF(0.0, -velocityHeight), Qt::NoButton,
                                  Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  staleNode + QPointF(0.0, -velocityHeight), Qt::LeftButton,
                                  Qt::NoButton, Qt::NoModifier);
    }
    const std::vector<DocNote> staleNotes =
        document.notesForTrack(view.selectionModel().primaryTrack());
    check(document.revision() == revisionBeforeExternalChange + 1 && staleNotes.size() == 2 &&
              staleNotes[1].velocity == secondVelocity && !view.previewVelocity(notes[0].noteId) &&
              !view.previewVelocity(notes[1].noteId) &&
              view.selectionModel().noteSelection() == selected,
          "stale velocity batch should apply none of its frozen request, clear preview, and cancel "
          "its gesture");

    std::unique_ptr<MidiTimeline> staleTimeline = document.buildTimeline(44100.0);
    view.updateSong(staleTimeline.get());
    timeline = std::move(staleTimeline);
    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(4);
    QCoreApplication::processEvents();
    const QPointF lifecycleNode = nodePosition(view, *area, *timeline, notes[0]);
    const auto sendVelocityMouse = [&](QEvent::Type type, const QPointF &position,
                                       Qt::MouseButton button, Qt::MouseButtons buttons,
                                       bool throughQuickWindow) {
        if (!velocityInput)
            return;
        if (!throughQuickWindow) {
            checks::events::sendMouse(*velocityInput, type, position, button, buttons,
                                      Qt::NoModifier);
            return;
        }
        QQuickWindow *const window = quick->quickWindow();
        const QPointF windowPosition = velocityInput->mapToScene(position);
        QMouseEvent event(type, windowPosition,
                          QPointF(window->mapToGlobal(windowPosition.toPoint())), button, buttons,
                          Qt::NoModifier);
        QCoreApplication::sendEvent(window, &event);
    };
    const auto cancelGesture = [&](const QPointF &node, auto cancel, bool clearsSelection,
                                   const char *message, bool throughQuickWindow = false) {
        const uint64_t revision = document.revision();
        const int undo = document.undoStack()->count();
        DocNote pressedNote;
        const std::vector<NoteId> selectionBeforeGesture = view.selectionModel().noteSelection();
        const bool pressedNoteResolved =
            !selectionBeforeGesture.empty() &&
            document.findNote(selectionBeforeGesture.front(), &pressedNote);
        const QPointF dragPosition =
            node + QPointF(0.0, pressedNoteResolved && pressedNote.velocity == 127 ? 40.0 : -40.0);
        sendVelocityMouse(QEvent::MouseButtonPress, node, Qt::LeftButton, Qt::LeftButton,
                          throughQuickWindow);
        sendVelocityMouse(QEvent::MouseMove, dragPosition, Qt::NoButton, Qt::LeftButton,
                          throughQuickWindow);
        const std::vector<NoteId> gestureSelection = view.selectionModel().noteSelection();
        const std::vector<NoteId> expectedSelection =
            clearsSelection ? std::vector<NoteId>{} : gestureSelection;
        bool previewStaged = !gestureSelection.empty();
        bool previewChanged = false;
        for (const NoteId id : gestureSelection) {
            DocNote liveNote;
            const auto preview = view.previewVelocity(id);
            const bool noteResolved = document.findNote(id, &liveNote);
            previewStaged = previewStaged && preview.has_value() && noteResolved;
            if (preview && noteResolved && *preview != liveNote.velocity)
                previewChanged = true;
        }
        check(previewStaged && previewChanged && document.revision() == revision &&
                  document.undoStack()->count() == undo,
              "velocity cancellation should begin with changed staged previews and unchanged "
              "history");
        cancel();
        sendVelocityMouse(QEvent::MouseButtonRelease, dragPosition, Qt::LeftButton, Qt::NoButton,
                          throughQuickWindow);
        bool previewCleared = true;
        for (const NoteId id : gestureSelection)
            previewCleared = previewCleared && !view.previewVelocity(id);
        const bool revisionUnchanged = document.revision() == revision;
        const bool undoUnchanged = document.undoStack()->count() == undo;
        const bool selectionRestored = view.selectionModel().noteSelection() == expectedSelection;
        const bool valid =
            revisionUnchanged && undoUnchanged && previewCleared && selectionRestored;
        const QByteArray detail = QByteArray(message) +
                                  " [revision=" + QByteArray::number(revisionUnchanged) +
                                  " undo=" + QByteArray::number(undoUnchanged) +
                                  " preview=" + QByteArray::number(previewCleared) +
                                  " selection=" + QByteArray::number(selectionRestored) + ']';
        check(valid, detail.constData());
    };
    cancelGesture(
        lifecycleNode, [&] { view.setDrawerActivePage(EditorDrawerPage::Automations); }, false,
        "drawer page switch should terminate the visible page gesture");
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setEditCursorTick(5);
    QCoreApplication::processEvents();
    cancelGesture(
        lifecycleNode,
        [&] {
            checks::events::sendKey(view, QEvent::KeyPress, Qt::Key_Escape, Qt::NoModifier,
                                    QString{}, false, ushort{1});
        },
        false, "Escape should terminate the visible page gesture through the host lifecycle");
    cancelGesture(
        lifecycleNode, [&] { view.setDrawerSectionVisible(EditorDrawerPage::Velocity, false); },
        false, "drawer close should terminate the visible page gesture");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    cancelGesture(
        lifecycleNode,
        [&] {
            if (velocityInput)
                velocityInput->ungrabMouse();
        },
        false, "Velocity Quick input ungrab should cancel without mutating history", true);
    cancelGesture(
        lifecycleNode,
        [&] {
            if (velocityInput) {
                QFocusEvent focusOut(QEvent::FocusOut, Qt::OtherFocusReason);
                QApplication::sendEvent(velocityInput, &focusOut);
            }
        },
        false, "Velocity Quick input focus loss should cancel without mutating history");
    cancelGesture(
        lifecycleNode,
        [&] {
            QEvent ungrab(QEvent::UngrabMouse);
            QApplication::sendEvent(&view, &ungrab);
        },
        false, "mouse-grab loss should terminate the visible page gesture");
    cancelGesture(
        lifecycleNode,
        [&] {
            QEvent deactivate(QEvent::WindowDeactivate);
            QApplication::sendEvent(quick->quickWindow(), &deactivate);
        },
        false, "Quick-window deactivation should cancel the hosted velocity gesture", true);
    cancelGesture(
        lifecycleNode,
        [&] {
            QEvent deactivate(QEvent::WindowDeactivate);
            QApplication::sendEvent(&view, &deactivate);
        },
        false, "window deactivation should terminate the visible page gesture");
    LoadedVoiceGroup replacementVoicegroup{};
    QPointF replacementNode = nodePosition(view, *area, *timeline, notes[0]);
    cancelGesture(
        replacementNode, [&] { view.setVoicegroup(&replacementVoicegroup); }, false,
        "voice replacement should terminate the visible page gesture");
    view.setVoicegroup(nullptr);
    replacementNode = nodePosition(view, *area, *timeline, notes[0]);
    cancelGesture(
        replacementNode, [&] { view.setSong(timeline.get(), nullptr); }, true,
        "song replacement should terminate the visible page gesture");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.selectTrack(1);
    notes = document.notesForTrack(view.selectionModel().primaryTrack());
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(7);
    QCoreApplication::processEvents();

    const QPointF documentNode = nodePosition(view, *area, *timeline, notes[0]);
    const uint64_t revisionBeforeDocumentReplacement = document.revision();
    const int undoBeforeDocumentReplacement = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeDocumentReplacement =
        view.selectionModel().noteSelection();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, documentNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                  documentNode + QPointF(0.0, -40.0), Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
    }
    const auto documentReplacementPreview = view.previewVelocity(notes[0].noteId);
    check(selectionBeforeDocumentReplacement.size() == 1 && documentReplacementPreview &&
              document.revision() == revisionBeforeDocumentReplacement &&
              document.undoStack()->count() == undoBeforeDocumentReplacement,
          "document replacement should begin with a staged preview and unchanged history");
    view.setDocument(nullptr);
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  documentNode + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
    }
    check(document.revision() == revisionBeforeDocumentReplacement,
          "document replacement should not change document revision");
    check(document.undoStack()->count() == undoBeforeDocumentReplacement,
          "document replacement should not change document history");
    check(!view.previewVelocity(notes[0].noteId),
          "document replacement should clear the visible velocity preview");
    check(view.selectionModel().noteSelection().empty(),
          "document replacement should clear the note selection");
    view.setDocument(&document);
    view.selectionModel().setNoteSelection({notes[0].noteId});
    view.setEditCursorTick(8);
    QCoreApplication::processEvents();

    const int replacementVelocity = notes[0].velocity == 127 ? 1 : 127;
    const int undoBeforeMutation = document.undoStack()->count();
    const uint64_t revisionBeforeMutation = document.revision();
    const std::vector<NoteId> selectionBeforeMutation = view.selectionModel().noteSelection();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, documentNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                  documentNode + QPointF(0.0, -40.0), Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
    }
    const auto mutationPreview = view.previewVelocity(notes[0].noteId);
    check(mutationPreview && document.revision() == revisionBeforeMutation &&
              document.undoStack()->count() == undoBeforeMutation,
          "document mutation should begin with a staged preview and unchanged history");
    document.setNotesVelocity({notes[0]}, uint8_t(replacementVelocity));
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  documentNode + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
    }
    check(document.revision() == revisionBeforeMutation + 1 &&
              document.undoStack()->count() == undoBeforeMutation + 1 &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeMutation,
          "document mutation should cancel the visible preview without applying its staged batch");

    DocNote undoNote = notes[0];
    check(document.findNote(notes[0].noteId, &undoNote),
          "Undo cancellation fixture should resolve its current note");
    const QPointF undoNode = nodePosition(view, *area, *timeline, undoNote);
    const uint64_t revisionBeforeUndo = document.revision();
    const int undoBeforeUndo = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeUndo = view.selectionModel().noteSelection();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, undoNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove, undoNode + QPointF(0.0, -40.0),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
    }
    const auto undoPreview = view.previewVelocity(notes[0].noteId);
    check(undoPreview && document.revision() == revisionBeforeUndo &&
              document.undoStack()->count() == undoBeforeUndo,
          "Undo cancellation should begin with a staged preview and unchanged history");
    document.undoStack()->undo();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  undoNode + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
    }
    check(document.revision() == revisionBeforeUndo + 1 &&
              document.undoStack()->count() == undoBeforeUndo &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeUndo,
          "Undo should terminate the visible page gesture");

    DocNote redoNote = notes[0];
    check(document.findNote(notes[0].noteId, &redoNote),
          "Redo cancellation fixture should resolve its current note");
    const QPointF redoNode = nodePosition(view, *area, *timeline, redoNote);
    const uint64_t revisionBeforeRedo = document.revision();
    const int undoBeforeRedo = document.undoStack()->count();
    const std::vector<NoteId> selectionBeforeRedo = view.selectionModel().noteSelection();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, redoNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove, redoNode + QPointF(0.0, -40.0),
                                  Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
    }
    const auto redoPreview = view.previewVelocity(notes[0].noteId);
    check(redoPreview && document.revision() == revisionBeforeRedo &&
              document.undoStack()->count() == undoBeforeRedo,
          "Redo cancellation should begin with a staged preview and unchanged history");
    document.undoStack()->redo();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  redoNode + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
    }
    check(document.revision() == revisionBeforeRedo + 1 &&
              document.undoStack()->count() == undoBeforeRedo &&
              !view.previewVelocity(notes[0].noteId) &&
              view.selectionModel().noteSelection() == selectionBeforeRedo,
          "Redo should terminate the visible page gesture");

    DocNote reloadNote = notes[0];
    check(document.findNote(notes[0].noteId, &reloadNote),
          "reload cancellation fixture should resolve its current note");
    const QPointF reloadNode = nodePosition(view, *area, *timeline, reloadNote);
    const uint64_t revisionBeforeReload = document.revision();
    const int undoBeforeReload = document.undoStack()->count();
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, reloadNode,
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*velocityInput, QEvent::MouseMove,
                                  reloadNode + QPointF(0.0, -40.0), Qt::NoButton, Qt::LeftButton,
                                  Qt::NoModifier);
    }
    const auto reloadPreview = view.previewVelocity(notes[0].noteId);
    check(reloadPreview && document.revision() == revisionBeforeReload &&
              document.undoStack()->count() == undoBeforeReload,
          "reload cancellation should begin with a staged preview and unchanged history");
    const bool reloaded = document.load(song, &error);
    if (velocityInput) {
        checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                  reloadNode + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                  Qt::NoModifier);
    }
    check(reloaded && !view.previewVelocity(notes[0].noteId),
          "reload should terminate the visible page gesture");
    std::unique_ptr<MidiTimeline> reloadedTimeline = document.buildTimeline(44100.0);
    view.updateSong(reloadedTimeline.get());
    timeline = std::move(reloadedTimeline);

    view.hide();
    return failures == 0 ? 0 : 1;
}

int runHostSeamsCheck()
{
    int failures = 0;
    const auto check = [&failures](bool condition, const char *what) {
        if (!condition) {
            std::fprintf(stderr, "host-seams: FAIL: %s\n", what);
            ++failures;
        }
    };

    auto state = EditorViewState{};
    check(!state.velocity.visible && !state.velocity.height && state.automation.visible &&
              !state.automation.height && !state.voiceChanges.visible &&
              !state.voiceChanges.height && state.activePage == EditorDrawerPage::Automations &&
              state.laneHeight == 0 && state.laneHeights.empty() && state.laneRanges.empty() &&
              state.emptyLanes.empty() && state.hiddenLanes().empty(),
          "new songs default to open Automations and hidden Velocity and Voice Changes");
    const auto controllerRow = EditorAutomationRowId{EditorAutomationRowKind::ControlChange, 2, 1};
    auto changedState = state;
    changedState.velocity = {false, 144};
    changedState.automation = {true, 96};
    changedState.activePage = EditorDrawerPage::Velocity;
    changedState.laneHeight = 96;
    changedState.laneHeights.emplace(controllerRow, 112);
    changedState.laneRanges.emplace(controllerRow, 91);
    changedState.emptyLanes.emplace(controllerRow);
    changedState.hideLane(controllerRow);
    check(changedState != state, "typed cosmetic lane state compares by value");

    QTemporaryDir temporary;
    QString error;
    SmfFile smf;
    smf.format = 1;
    smf.division = 24;
    SmfTrack track;
    track.events = {
        noteEvent(0xC0, 0, 0, 0),
        noteEvent(0x90, 12, 60, 64),
        noteEvent(0x80, 36, 60, 0),
        noteEvent(0xB0, 24000, 1, 0),
    };
    track.endTick = 24000;
    smf.tracks.push_back(track);
    SongInfo song;
    song.label = QStringLiteral("editor-state");
    song.midPath = temporary.path() + QStringLiteral("/editor-state.mid");
    song.hasMid = true;
    SongDocument document;
    check(temporary.isValid() && smf.writeFile(song.midPath, &error) && document.load(song, &error),
          "concrete editor fixture should load");
    auto timeline = document.buildTimeline(44100.0);
    check(timeline != nullptr, "concrete editor fixture should build a timeline");
    if (!timeline)
        return 1;

    LoadedVoiceGroup voicegroup{};
    voicegroup.voices[0].type = VOICE_SQUARE_1;
    SongView view;
    view.resize(900, 600);
    view.setDocument(&document);
    view.setSong(timeline.get(), &voicegroup);
    auto *drawer = view.editorDrawer();
    auto *automation = drawer ? drawer->automationPage() : nullptr;
    auto *velocity = drawer ? drawer->velocityArea() : nullptr;
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    check(drawer && automation && velocity && voiceChanges,
          "SongView must own all three concrete drawer pages");
    if (!drawer || !automation || !velocity || !voiceChanges)
        return 1;
    check(qobject_cast<QWidget *>(drawer) == nullptr &&
              qobject_cast<QWidget *>(automation) == nullptr,
          "EditorDrawer and AutomationPage must be QObjects without QWidget scroll shells");

    view.applyEditorViewState(changedState);
    check(view.editorViewState() == changedState &&
              view.drawerActivePage() == EditorDrawerPage::Velocity &&
              !view.drawerSectionVisible(EditorDrawerPage::Velocity) &&
              view.drawerSectionVisible(EditorDrawerPage::Automations),
          "typed drawer state should attach through SongView without document mutation");
    view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
    view.setDrawerActivePage(EditorDrawerPage::Velocity);
    view.setDrawerSectionHeight(EditorDrawerPage::Velocity, 280);
    view.show();
    QCoreApplication::processEvents();

    const int automationMaximumScroll = qMax(0, automation->automationContentHeight() -
                                                    automation->automationViewportSize().height());
    automation->setVerticalScroll(automationMaximumScroll + 97);
    check(automation->verticalScroll() == automationMaximumScroll,
          "AutomationPage must be the only automation scroll store, clamping setVerticalScroll "
          "into its synchronized range");
    automation->setVerticalScroll(0);
    check(automation->verticalScroll() == 0,
          "AutomationPage scroll store must accept in-range offsets without a scrollbar proxy");
    check(drawer->chrome().scrollbarWidth() == layout::space(layout::Space::Two),
          "DrawerChrome must size the Quick automation scrollbar with layout::space(Space::Two)");
    view.setEditorHorizontalScroll(96.0);
    view.setEditorTimeZoom(1.75 * layout::fontPx(8.0 / 3.0));
    view.setFollowScrollPaused(true);
    view.focusContent();
    view.announce(QStringLiteral("editor-state"));
    view.showDrawerPageNoteStatus(DrawerPageNoteStatus{60, 64, 64, 24, 12});
    view.showDrawerPageNoteStatus(std::nullopt);
    view.requestDrawerPageUndo();
    view.requestDrawerPageRedo();
    const auto runtime = view.viewState();
    check(runtime.valid && runtime.scrollPx == 96.0 &&
              runtime.pxPerBeat == 1.75 * layout::fontPx(8.0 / 3.0),
          "SongView editor endpoints should update runtime camera state");
    const auto grid = DrawerPageGridState{view.grid().gridTicksAt(12), view.grid().snapTicksAt(12)};
    const auto voice = view.voiceContext(12);
    check(grid.gridTicks > 0 && grid.snapTicks > 0 && voice.voice == &voicegroup.voices[0] &&
              voice.voiceSlot == 0,
          "SongView should resolve grid and voice state at concrete page ticks");

    view.setEditorTimeZoom(48.0);
    view.setEditorHorizontalScroll(0.0);
    auto live = DrawerPageLiveState{};
    live.documentRevision = document.revision();
    live.timeZoom = view.camera().pxPerBeat();
    live.horizontalScroll = view.camera().scrollX();
    live.editCursorTick = 12;
    live.trackColor = QColor{10, 20, 30};
    live.playback = {12.0, true};
    automation->refreshLiveState(live);
    velocity->refreshLiveState(live);
    voiceChanges->refreshLiveState(live);
    check(!automation->canvas()->rows().empty() &&
              velocity->axis().mode() == VelocityAxis::Mode::Intrinsic,
          "concrete pages should refresh live state through their SongView owner");

    const auto notes = document.notesForTrack(0);
    check(notes.size() == 1, "concrete fixture should retain its note identity");
    if (notes.empty())
        return 1;
    view.selectionModel().setNoteSelection({notes.front().noteId});
    const std::vector<NoteVelocity> velocities{{notes.front().noteId, 96}};
    const uint64_t revisionBeforeStale = document.revision();
    const int undoBeforeStale = document.undoStack()->count();
    const bool beganStale = view.beginVelocityGesture(notes);
    const bool updatedStale = view.updateVelocityGesture(velocities);
    check(beganStale && updatedStale && view.previewVelocity(notes.front().noteId) &&
              *view.previewVelocity(notes.front().noteId) == 96 &&
              document.revision() == revisionBeforeStale &&
              document.undoStack()->count() == undoBeforeStale,
          "concrete SongView should expose a deferred velocity preview");
    document.blockSignals(true);
    document.setNotesVelocity({notes.front()}, 95);
    document.blockSignals(false);
    const auto staleCommitted = view.commitVelocityGesture();
    DocNote staleNote;
    check(staleCommitted == SongView::VelocityCommitResult::Rejected &&
              document.revision() == revisionBeforeStale + 1 &&
              document.undoStack()->count() == undoBeforeStale + 1 &&
              document.findNote(notes.front().noteId, &staleNote) && staleNote.velocity == 95 &&
              !view.previewVelocity(notes.front().noteId),
          "stale SongView velocity gesture should be rejected atomically and clear its preview");

    const uint64_t revisionBeforeAccepted = document.revision();
    const int undoBeforeAccepted = document.undoStack()->count();
    const bool beganAccepted = view.beginVelocityGesture(document.notesForTrack(0));
    const bool updatedAccepted = view.updateVelocityGesture(velocities);
    const auto accepted = view.commitVelocityGesture();
    DocNote acceptedNote = notes.front();
    check(beganAccepted && updatedAccepted &&
              accepted == SongView::VelocityCommitResult::Committed &&
              document.revision() == revisionBeforeAccepted + 1 &&
              document.undoStack()->count() == undoBeforeAccepted + 1 &&
              document.findNote(notes.front().noteId, &acceptedNote) &&
              acceptedNote.velocity == 96 && !view.previewVelocity(notes.front().noteId),
          "matching SongView velocity gesture should commit exactly once and clear its preview");

    if (!notes.empty()) {
        view.selectionModel().setNoteSelection({notes.front().noteId});
        live.documentRevision = document.revision();
        live.playback.playing = false;
        velocity->refreshLiveState(live);
        const QPointF node = nodePosition(view, *velocity, *timeline, acceptedNote);
        const uint64_t beforePageSwitch = document.revision();
        const int undoBeforePageSwitch = document.undoStack()->count();
        const std::vector<NoteId> selectionBeforePageSwitch = view.selectionModel().noteSelection();
        auto *quickCanvas =
            view.findChild<songview::TimelineQuickView *>(QStringLiteral("timelineQuickCanvas"));
        auto *quickRoot = quickCanvas ? quickCanvas->rootObject() : nullptr;
        auto *velocityInput = quickRoot ? quickRoot->findChild<songview::TimelineInputItem *>(
                                              QStringLiteral("timelineVelocityInput"))
                                        : nullptr;
        check(velocityInput != nullptr,
              "concrete SongView did not expose the velocity Quick input item");
        if (velocityInput) {
            checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, node,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*velocityInput, QEvent::MouseMove, node + QPointF(0.0, -40.0),
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        }
        const auto pageSwitchPreview = view.previewVelocity(notes.front().noteId);
        check(pageSwitchPreview && document.revision() == beforePageSwitch &&
                  document.undoStack()->count() == undoBeforePageSwitch,
              "drawer page replacement should begin with a staged preview and unchanged history");
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        if (velocityInput) {
            checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                      node + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                      Qt::NoModifier);
        }
        check(document.revision() == beforePageSwitch &&
                  document.undoStack()->count() == undoBeforePageSwitch &&
                  !view.previewVelocity(notes.front().noteId) &&
                  view.selectionModel().noteSelection() == selectionBeforePageSwitch,
              "drawer page replacement must cancel the concrete velocity preview first");

        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        velocity->refreshLiveState(live);
        const uint64_t beforeDocumentSwap = document.revision();
        const int undoBeforeDocumentSwap = document.undoStack()->count();
        const std::vector<NoteId> selectionBeforeDocumentSwap =
            view.selectionModel().noteSelection();
        if (velocityInput) {
            checks::events::sendMouse(*velocityInput, QEvent::MouseButtonPress, node,
                                      Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*velocityInput, QEvent::MouseMove, node + QPointF(0.0, -40.0),
                                      Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
        }
        const auto documentSwapPreview = view.previewVelocity(notes.front().noteId);
        check(!selectionBeforeDocumentSwap.empty() && documentSwapPreview &&
                  document.revision() == beforeDocumentSwap &&
                  document.undoStack()->count() == undoBeforeDocumentSwap,
              "document replacement should begin with a staged preview and unchanged history");
        view.setDocument(nullptr);
        if (velocityInput) {
            checks::events::sendMouse(*velocityInput, QEvent::MouseButtonRelease,
                                      node + QPointF(0.0, -40.0), Qt::LeftButton, Qt::NoButton,
                                      Qt::NoModifier);
        }
        check(document.revision() == beforeDocumentSwap &&
                  document.undoStack()->count() == undoBeforeDocumentSwap &&
                  !view.previewVelocity(notes.front().noteId) &&
                  view.selectionModel().noteSelection().empty(),
              "document replacement must cancel the concrete velocity preview first");
        view.setDocument(&document);
        view.updateSong(timeline.get());
    }

    const auto cosmeticsBeforeChange = view.editorViewState();
    automation->documentChanged();
    velocity->documentChanged();
    voiceChanges->documentChanged();
    check(view.editorViewState() == cosmeticsBeforeChange,
          "document refresh must preserve concrete drawer cosmetics");
    view.cancelActiveInteractions();
    view.hide();

    bool quickHostDestroyed = false;
    bool voiceInteractionAliveAtQuickDestruction = false;
    auto destructionProbe = std::make_unique<SongView>();
    auto *quickHost = destructionProbe->findChild<songview::TimelineQuickView *>(
        QStringLiteral("timelineQuickCanvas"), Qt::FindDirectChildrenOnly);
    QPointer<VoiceChangeArea> voiceInteraction =
        destructionProbe->editorDrawer()->voiceChangeArea();
    check(quickHost && voiceInteraction,
          "destruction-order probe must construct the Quick host and voice interaction");
    check(voiceInteraction && voiceInteraction->parent() == destructionProbe.get(),
          "VoiceChangeArea must have SongView lifetime ownership");
    if (quickHost) {
        QObject::connect(quickHost, &QObject::destroyed, [&] {
            quickHostDestroyed = true;
            voiceInteractionAliveAtQuickDestruction = !voiceInteraction.isNull();
        });
    }
    destructionProbe.reset();
    check(quickHostDestroyed, "SongView destruction must destroy its Quick host");
    check(voiceInteractionAliveAtQuickDestruction,
          "Quick host must detach before VoiceChangeArea destruction");
    return failures == 0 ? 0 : 1;
}
