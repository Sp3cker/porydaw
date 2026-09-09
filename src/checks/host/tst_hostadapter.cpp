#include "checks/fwd.hpp"
#include "checks/host/hosttestsupport.h"

#include <memory>
#include <optional>

#include <QEnterEvent>
#include <QEvent>
#include <QFocusEvent>
#include <QImage>
#include <QKeyEvent>
#include <QPalette>
#include <QPoint>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QtTest>
#include <algorithm>
#include <array>
#include <cmath>

#include "checks/support/asyncwait.h"
#include "checks/support/eventsynth.h"
#include "checks/support/quickframebuffer.h"
#include "checks/support/songfixture.h"
#include "checks/support/timelinequickcheck.h"
#include "ui/editordrawer/automationcanvas.h"
#include "ui/editordrawer/automationpage.h"
#include "ui/editordrawer/drawerchrome.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/velocityarea/velocityarea.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/layout.h"
#include "ui/songview/otherstrip.h"
#include "ui/songview/pianoroll.h"
#include "ui/songview/quick/quickpopupsession.h"
#include "ui/songview/quick/timelineinputitem.h"
#include "ui/songview/quick/timelinequickview.h"
#include "ui/songview/timelinebandlayout.h"
#include "ui/songview/timeruler.h"
#include "ui/songview/trackheadermodel.h"

#include "ui/editorviewstate.h"
namespace checks::host {
namespace {

class HostAdapterTest final : public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY_MOVE(HostAdapterTest)

  public:
    HostAdapterTest(QString projectRoot, QString songLabel)
        : m_projectRoot(std::move(projectRoot))
        , m_songLabel(std::move(songLabel))
    {}

  private slots:
    void syntheticFixtureConstructsHost()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        QVERIFY(host.view().timeline());
        QVERIFY(host.view().editorDrawer());
        QVERIFY(host.view().editorDrawer()->velocityArea());
        QVERIFY(host.view().quickView());
        QCOMPARE(host.document().notesForTrack(0).size(), size_t{2});
    }

    void route101FixtureAttachesHostedVelocityMarker()
    {
        QString error;
        auto loaded = checks::LoadedSong::load(m_projectRoot, m_songLabel, error);
        QVERIFY2(loaded, qPrintable(error));
        auto rig = checks::SongViewRig::create(std::move(loaded), 44100.0, error);
        QVERIFY2(rig, qPrintable(error));
        SongDocument &document = rig->document();
        const MidiTimeline &timeline = rig->timeline();
        std::optional<DocNote> fixtureNote;
        for (int track = 0; track < document.engineTrackCount() && !fixtureNote; ++track) {
            const std::vector<DocNote> notes = document.notesForTrack(track);
            if (!notes.empty())
                fixtureNote = notes.front();
        }
        QVERIFY(fixtureNote.has_value());
        QVERIFY(std::any_of(timeline.events.cbegin(), timeline.events.cend(),
                            [id = fixtureNote->noteId](const TimelineEvent &event) {
                                return event.type == 0x9 && event.noteId == id;
                            }));
        SongView &view = rig->view();
        QVERIFY(checks::support::showQuickViewport(view, QSize(720, 520)));
        view.selectTrack(fixtureNote->engineTrack);
        view.selectionModel().setNoteSelection({fixtureNote->noteId});
        view.setEditCursorTick(fixtureNote->tick);
        view.setDrawerActivePage(EditorDrawerPage::Velocity);
        view.setDrawerSectionVisible(EditorDrawerPage::Velocity, true);
        settle();
        auto *area = view.editorDrawer()->velocityArea();
        QVERIFY(area);
        QCOMPARE(document.label(), m_songLabel);
        QCOMPARE(view.timeline(), &timeline);
        QCOMPARE(view.selectionModel().primaryTrack(), fixtureNote->engineTrack);
        QCOMPARE(view.selectionModel().noteSelection(), (std::vector<NoteId>{fixtureNote->noteId}));
        QCOMPARE(area->axis().markerCount(), 1);
        QCOMPARE(area->axis().markers().front().velocity, fixtureNote->velocity);
    }

    void canonicalGeometryProjectsToQuick()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        auto *headers = view.findChild<songview::TrackHeaderModel *>(
            QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
        QVERIFY(headers);
        QString captureError;
        QQuickWindow *const window = quick->quickWindow();
        QVERIFY(window);
        const QImage publishedFrame =
            checks::support::captureQuickBand(view, QRect(QPoint{}, window->size()), &captureError);
        QVERIFY2(!publishedFrame.isNull(), qPrintable(captureError));
        const songview::TimelineBandLayout &layout = view.timelineBandLayout();
        const auto trackHeaders = layout.geometry(songview::TimelineBand::TrackHeaders);
        QVERIFY(trackHeaders.has_value());
        QVERIFY(trackHeaders->plotRect.isEmpty());
        for (songview::TimelineBand band :
             {songview::TimelineBand::Ruler, songview::TimelineBand::Roll,
              songview::TimelineBand::OtherEvents, songview::TimelineBand::Velocity}) {
            const auto geometry = layout.geometry(band);
            QVERIFY(geometry.has_value());
            QVERIFY(!geometry->rect.isEmpty());
            QVERIFY(!geometry->plotRect.isEmpty());
            QCOMPARE(geometry->plotRect.x(), view.timelineSplitX());
            QCOMPARE(geometry->plotRect.right(), geometry->rect.right());
            QVERIFY(!trackHeaders->rect.intersects(geometry->plotRect));
        }
        struct BandProperties {
            songview::TimelineBand band;
            const char *rect;
            const char *plot;
            const char *visible;
        };
        constexpr std::array<BandProperties, 7> properties{{
            {songview::TimelineBand::Ruler, "rulerBandRect", "rulerBandPlotRect",
             "rulerBandVisible"},
            {songview::TimelineBand::Roll, "rollBandRect", "rollBandPlotRect", "rollBandVisible"},
            {songview::TimelineBand::OtherEvents, "otherEventsBandRect", "otherEventsBandPlotRect",
             "otherEventsBandVisible"},
            {songview::TimelineBand::Automation, "automationBandRect", "automationBandPlotRect",
             "automationBandVisible"},
            {songview::TimelineBand::Velocity, "velocityBandRect", "velocityBandPlotRect",
             "velocityBandVisible"},
            {songview::TimelineBand::VoiceChanges, "voiceChangesBandRect",
             "voiceChangesBandPlotRect", "voiceChangesBandVisible"},
            {songview::TimelineBand::TrackHeaders, "trackHeadersBandRect",
             "trackHeadersBandPlotRect", "trackHeadersBandVisible"},
        }};
        for (const BandProperties &entry : properties) {
            const auto geometry = layout.geometry(entry.band);
            const QRectF expectedRect = geometry ? QRectF(geometry->rect) : QRectF{};
            const QRectF expectedPlot =
                geometry && !geometry->plotRect.isEmpty() ? QRectF(geometry->plotRect) : QRectF{};
            QCOMPARE(root->property(entry.rect).toRectF(), expectedRect);
            QCOMPARE(root->property(entry.plot).toRectF(), expectedPlot);
            QCOMPARE(root->property(entry.visible).toBool(), geometry.has_value());
        }
        QVERIFY(checks::support::physicalInputsMatchCanonical(
            layout, *root, songview::TimelineBand::Ruler, QStringLiteral("timelineRulerInput"),
            QStringLiteral("timelineRulerGutterInput")));
        QVERIFY(checks::support::physicalInputsMatchCanonical(
            layout, *root, songview::TimelineBand::Roll, QStringLiteral("timelineRollInput"),
            QStringLiteral("timelineRollGutterInput")));
        QVERIFY(checks::support::physicalInputsMatchCanonical(
            layout, *root, songview::TimelineBand::OtherEvents,
            QStringLiteral("timelineOtherEventsInput"),
            QStringLiteral("timelineOtherEventsGutterInput")));
        QVERIFY(checks::support::physicalInputsMatchCanonical(
            layout, *root, songview::TimelineBand::Velocity,
            QStringLiteral("timelineVelocityInput"),
            QStringLiteral("timelineVelocityGutterInput")));
        const auto velocity = layout.geometry(songview::TimelineBand::Velocity);
        const auto roll = layout.geometry(songview::TimelineBand::Roll);
        QVERIFY(velocity.has_value());
        QVERIFY(roll.has_value());
        QCOMPARE(velocity->rect.x(), trackHeaders->rect.width());
        QCOMPARE(velocity->plotRect.x(), view.timelineSplitX());
        QCOMPARE(roll->plotRect.x(), view.timelineSplitX());
        QCOMPARE(velocity->plotRect.x() - velocity->rect.x(), view.pianoKeyboardWidth());
        QCOMPARE(roll->plotRect.x() - roll->rect.x(), view.pianoKeyboardWidth());
        QCOMPARE(view.editorDrawer()->bodyRect(EditorDrawerPage::Velocity),
                 std::optional<QRect>{velocity->rect});
    }

    // Moving or resizing the page must reproject bands without resizing the
    // shared window or breaking pointer delivery.
    void canvasOnlyResizeDrivesBandLayoutAndPointerTarget()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        QQuickWindow *const window = quick->quickWindow();
        QVERIFY(window);
        QVERIFY(checks::support::showQuickViewport(view, QSize(960, 640)));
        QQuickItem &page = host.viewport();
        QCOMPARE(page.position(), QPointF(0, 0));
        QCOMPARE(root->position(), QPointF(0, 0));
        QCOMPARE(page.size(), QSizeF(window->size()));
        QCOMPARE(root->size(), page.size());
        const std::vector<DocNote> notes = host.document().notesForTrack(0);
        QCOMPARE(notes.size(), size_t{2});

        const QPointF canvasOffset(24, 16);
        const QSizeF canvasSize(window->width() - 160, window->height() - 120);
        page.setPosition(canvasOffset);
        page.setSize(canvasSize);
        settle();
        QCOMPARE(window->size(), QSize(960, 640));
        QCOMPARE(page.position(), canvasOffset);
        QCOMPARE(root->position(), QPointF(0, 0));
        QCOMPARE(page.size(), canvasSize);
        QCOMPARE(root->size(), canvasSize);
        const QRectF canvasRect(QPointF{}, canvasSize);
        auto canvasLocal = [&](const songview::TimelineBandLayout &bandLayout,
                               const QRectF &expectedCanvas) {
            const auto otherEvents = bandLayout.geometry(songview::TimelineBand::OtherEvents);
            if (!otherEvents.has_value() ||
                otherEvents->rect.width() != qRound(expectedCanvas.width()))
                return false;
            for (songview::TimelineBand band :
                 {songview::TimelineBand::Ruler, songview::TimelineBand::Roll,
                  songview::TimelineBand::OtherEvents, songview::TimelineBand::Velocity}) {
                const auto geometry = bandLayout.geometry(band);
                if (!geometry.has_value() || !expectedCanvas.contains(geometry->rect))
                    return false;
            }
            return true;
        };
        QVERIFY2(canvasLocal(view.timelineBandLayout(), canvasRect),
                 "every visible band must fit the translated, shrunken canvas item");
        auto *rollInput =
            root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
        auto *velocityInput =
            root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineVelocityInput"));
        QVERIFY(rollInput && velocityInput);
        const auto canvasFrame = [root](const songview::TimelineInputItem *input) {
            return QRectF(input->mapToItem(root, QPointF()), input->size());
        };
        QVERIFY(canvasRect.contains(canvasFrame(rollInput)));
        QVERIFY(canvasRect.contains(canvasFrame(velocityInput)));

        const QSizeF secondCanvasSize(canvasSize.width(), canvasSize.height() - 48);
        const QRectF secondCanvasRect(QPointF{}, secondCanvasSize);
        const int otherEventsBottomBefore =
            view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents)->rect.bottom();
        page.setSize(secondCanvasSize);
        settle();
        QCOMPARE(window->size(), QSize(960, 640));
        QCOMPARE(page.size(), secondCanvasSize);
        QCOMPARE(root->size(), secondCanvasSize);
        const auto otherEvents =
            view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
        QVERIFY(otherEvents.has_value());
        QCOMPARE(otherEvents->rect.bottom(), otherEventsBottomBefore - 48);
        QVERIFY2(canvasLocal(view.timelineBandLayout(), secondCanvasRect),
                 "the second canvas-only resize must keep every band canvas-local");
        QVERIFY(secondCanvasRect.contains(canvasFrame(rollInput)));
        QVERIFY(secondCanvasRect.contains(canvasFrame(velocityInput)));

        view.selectionModel().clearNoteSelection();
        view.ensureTickVisible(notes.front().tick);
        view.ensureKeyVisible(notes.front().key);
        settle();
        const qreal dpr = rollInput->devicePixelRatio();
        const double keyHeight = view.camera().keyHeight();
        const double scrollY = view.camera().scrollY();
        const qreal noteLeft = view.camera().displayX(double(notes.front().tick), 0.0, dpr);
        const qreal noteRight =
            view.camera().displayX(double(notes.front().tick + notes.front().duration), 0.0, dpr);
        const qreal rowTop =
            std::round(((127 - notes.front().key) * keyHeight - scrollY) * dpr) / dpr;
        const QPointF pressPoint((noteLeft + noteRight) / 2.0, rowTop + keyHeight / 2.0);
        QVERIFY(rollInput->contains(pressPoint));
        const QPointF scenePoint = rollInput->mapToScene(pressPoint);
        QCOMPARE(scenePoint, root->mapToScene(rollInput->mapToItem(root, pressPoint)));
        const QPoint globalPos = window->mapToGlobal(scenePoint.toPoint());
        QMouseEvent press(QEvent::MouseButtonPress, scenePoint, scenePoint, globalPos,
                          Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        QCoreApplication::sendEvent(window, &press);
        QCOMPARE(window->mouseGrabberItem(), static_cast<QQuickItem *>(rollInput));
        QMouseEvent release(QEvent::MouseButtonRelease, scenePoint, scenePoint, globalPos,
                            Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        settle();
        const std::vector<NoteId> selection = view.selectionModel().noteSelection();
        QCOMPARE(selection.size(), size_t{1});
        DocNote selected;
        QVERIFY2(host.document().findNote(selection.front(), &selected),
                 "the mapped press must select the note at the clicked canvas cell");
        QCOMPARE(selected.engineTrack, 0);
        QCOMPARE(selected.tick, notes.front().tick);
        QCOMPARE(int(selected.key), int(notes.front().key));
    }

    void quickInputsOwnTheirInteractions()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        auto input = [root](const char *name) {
            return root->findChild<songview::TimelineInputItem *>(QString::fromLatin1(name));
        };
        auto *ruler = input("timelineRulerInput");
        auto *rulerGutter = input("timelineRulerGutterInput");
        auto *roll = input("timelineRollInput");
        auto *rollGutter = input("timelineRollGutterInput");
        auto *other = input("timelineOtherEventsInput");
        auto *otherGutter = input("timelineOtherEventsGutterInput");
        auto *automation = input("timelineAutomationInput");
        auto *automationGutter = input("timelineAutomationGutterInput");
        auto *velocity = input("timelineVelocityInput");
        auto *velocityGutter = input("timelineVelocityGutterInput");
        auto *voice = input("timelineVoiceChangesInput");
        auto *voiceGutter = input("timelineVoiceChangesGutterInput");
        QVERIFY(ruler && rulerGutter && roll && rollGutter && other && otherGutter && automation &&
                automationGutter && velocity && velocityGutter && voice && voiceGutter);
        QCOMPARE(ruler->interaction(), rulerGutter->interaction());
        QVERIFY(dynamic_cast<songview::TimeRuler *>(ruler->interaction()));
        QCOMPARE(roll->interaction(), rollGutter->interaction());
        QVERIFY(dynamic_cast<songview::PianoRoll *>(roll->interaction()));
        QCOMPARE(other->interaction(), otherGutter->interaction());
        QVERIFY(dynamic_cast<songview::OtherStrip *>(other->interaction()));
        QCOMPARE(automation->interaction(), automationGutter->interaction());
        QCOMPARE(automation->interaction(), view.editorDrawer()->automationPage()->canvas());
        QCOMPARE(velocity->interaction(), velocityGutter->interaction());
        QCOMPARE(velocity->interaction(), view.editorDrawer()->velocityArea());
        QCOMPARE(voice->interaction(), voiceGutter->interaction());
        QCOMPARE(voice->interaction(), view.editorDrawer()->voiceChangeArea());
    }

    void drawerChromeAndQuickHeadersFollowCanonicalGeometry()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        EditorDrawer *drawer = view.editorDrawer();
        QVERIFY(drawer);
        const auto other = view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
        const auto velocity = view.timelineBandLayout().geometry(songview::TimelineBand::Velocity);
        QVERIFY(other.has_value());
        QVERIFY(velocity.has_value());
        const DrawerChrome &chrome = drawer->chrome();
        const std::optional<QRect> body = drawer->bodyRect(EditorDrawerPage::Velocity);
        QVERIFY(body.has_value());
        QVERIFY(chrome.velocityHandleVisible());
        QVERIFY(!chrome.automationHandleVisible());
        QVERIFY(!chrome.voiceChangesHandleVisible());
        QVERIFY(drawer->overlayRect().bottom() < other->rect.top());
        QCOMPARE(chrome.velocityHandleRect().bottom(), body->top());
        QCOMPARE(body->bottom() + 1, qRound(chrome.barRect().top()));
        QCOMPARE(chrome.automationToggleRect().x(), chrome.voiceChangesToggleRect().x() +
                                                        chrome.voiceChangesToggleRect().width() +
                                                        layout::space(layout::Space::One));
        QCOMPARE(chrome.velocityToggleRect().x(), chrome.automationToggleRect().x() +
                                                      chrome.automationToggleRect().width() +
                                                      layout::space(layout::Space::One));
        const QRectF toggles = chrome.voiceChangesToggleRect()
                                   .united(chrome.automationToggleRect())
                                   .united(chrome.velocityToggleRect());
        const qreal pianoCenter = (velocity->rect.x() + velocity->plotRect.x()) / 2.0;
        QVERIFY(std::abs(toggles.center().x() - pianoCenter) <= layout::singlePixel());
        const auto *headers = view.findChild<songview::TrackHeaderModel *>(
            QStringLiteral("trackHeaderModel"), Qt::FindDirectChildrenOnly);
        auto *headerBand =
            root->findChild<QQuickItem *>(QStringLiteral("timelineQuickTrackHeaders"));
        auto *headerInput = root->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineTrackHeadersInput"));
        auto *headerRows = root->findChild<QObject *>(QStringLiteral("timelineTrackHeaderRows"));
        auto *headerScroll =
            root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollBar"));
        auto *headerThumb =
            root->findChild<QQuickItem *>(QStringLiteral("timelineTrackHeaderScrollThumb"));
        QVERIFY(headers && headerBand && headerInput && headerRows && headerScroll && headerThumb);
        const auto headersGeometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::TrackHeaders);
        QVERIFY(headersGeometry.has_value());
        QCOMPARE(headerInput->interaction(), headers);
        QCOMPARE(headerRows->property("count").toInt(), headers->rowCount());
        QCOMPARE(headerScroll->width(), headers->scrollbarWidth());
        QCOMPARE(headerScroll->isVisible(), headers->maximumScrollY() > 0.0);
        QCOMPARE(headerThumb->isVisible(), headers->maximumScrollY() > 0.0);
        QVERIFY(std::abs(quick->rulerPlotOrigin() - view.timelineSplitX()) <=
                layout::singlePixel());
        QVERIFY(quick->quickWindow()->devicePixelRatio() > 0.0);
    }

    void hiddenBandsClearEveryProjection_data()
    {
        QTest::addColumn<EditorDrawerPage>("page");
        QTest::addColumn<songview::TimelineBand>("band");
        QTest::addColumn<QString>("visibleProperty");
        QTest::addColumn<QString>("rectProperty");
        QTest::newRow("velocity") << EditorDrawerPage::Velocity << songview::TimelineBand::Velocity
                                  << QStringLiteral("velocityBandVisible")
                                  << QStringLiteral("velocityBandRect");
        QTest::newRow("automation")
            << EditorDrawerPage::Automations << songview::TimelineBand::Automation
            << QStringLiteral("automationBandVisible") << QStringLiteral("automationBandRect");
        QTest::newRow("voice") << EditorDrawerPage::VoiceChanges
                               << songview::TimelineBand::VoiceChanges
                               << QStringLiteral("voiceChangesBandVisible")
                               << QStringLiteral("voiceChangesBandRect");
    }

    void hiddenBandsClearEveryProjection()
    {
        QFETCH(EditorDrawerPage, page);
        QFETCH(songview::TimelineBand, band);
        QFETCH(QString, visibleProperty);
        QFETCH(QString, rectProperty);
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        view.setDrawerSectionVisible(page, false);
        settle();
        QVERIFY(!view.timelineBandLayout().geometry(band).has_value());
        QVERIFY(!root->property(qPrintable(visibleProperty)).toBool());
        QVERIFY(root->property(qPrintable(rectProperty)).toRectF().isEmpty());
        QString inputName;
        QString gutterName;
        if (band == songview::TimelineBand::Velocity) {
            inputName = QStringLiteral("timelineVelocityInput");
            gutterName = QStringLiteral("timelineVelocityGutterInput");
        } else if (band == songview::TimelineBand::Automation) {
            inputName = QStringLiteral("timelineAutomationInput");
            gutterName = QStringLiteral("timelineAutomationGutterInput");
        } else {
            inputName = QStringLiteral("timelineVoiceChangesInput");
            gutterName = QStringLiteral("timelineVoiceChangesGutterInput");
        }
        auto *plot = root->findChild<songview::TimelineInputItem *>(inputName);
        auto *gutter = root->findChild<songview::TimelineInputItem *>(gutterName);
        QVERIFY(plot && gutter);
        QVERIFY(!plot->isVisible());
        QVERIFY(!gutter->isVisible());
        view.setDrawerSectionVisible(page, true);
        settle();
        QVERIFY(view.timelineBandLayout().geometry(band).has_value());
        QVERIFY(root->property(qPrintable(visibleProperty)).toBool());
        QVERIFY(checks::support::physicalInputsMatchCanonical(view.timelineBandLayout(), *root,
                                                              band, inputName, gutterName));
    }

    void eventListHidesOnlyRollProjection()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        view.setEventListVisible(true);
        settle();
        QVERIFY(!view.timelineBandLayout().geometry(songview::TimelineBand::Roll).has_value());
        auto *roll =
            root->findChild<songview::TimelineInputItem *>(QStringLiteral("timelineRollInput"));
        auto *gutter = root->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineRollGutterInput"));
        QVERIFY(roll && gutter);
        QVERIFY(!roll->isVisible());
        QVERIFY(!gutter->isVisible());
        QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::Velocity).has_value());
        view.setEventListVisible(false);
        settle();
        QVERIFY(view.timelineBandLayout().geometry(songview::TimelineBand::Roll).has_value());
    }

    void otherEventsTooltipUsesTheQuickInputAndClearsOnLeave()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QQuickItem *root = quick->rootObject();
        QVERIFY(root);
        auto *input = root->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineOtherEventsInput"));
        const auto geometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
        QVERIFY(input && geometry.has_value());
        QQuickItem *toolTip =
            root->findChild<QQuickItem *>(QStringLiteral("timelineOtherEventsToolTip"));
        auto *otherStrip = dynamic_cast<songview::OtherStrip *>(input->interaction());
        QVERIFY(toolTip && otherStrip && !toolTip->isVisible());
        QVERIFY(!view.model().strip.empty());
        const StripItem &marker = view.model().strip.front();
        const qreal x = view.camera().displayX(double(marker.tick), geometry->plotRect.x(),
                                               input->devicePixelRatio());
        const QPointF inputPoint =
            input->mapFromScene(QPointF{x, qreal(geometry->rect.center().y())});
        QVERIFY(input->contains(inputPoint));
        const QPointF windowPoint = input->mapToScene(inputPoint);
        QEnterEvent enter(windowPoint, windowPoint,
                          QPointF(quick->quickWindow()->mapToGlobal(windowPoint.toPoint())));
        QCoreApplication::sendEvent(quick->quickWindow(), &enter);
        QMouseEvent move(QEvent::MouseMove, windowPoint, windowPoint,
                         quick->quickWindow()->mapToGlobal(windowPoint.toPoint()), Qt::NoButton,
                         Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(quick->quickWindow(), &move);
        settle();
        QVERIFY(otherStrip->toolTipVisible());
        QVERIFY(otherStrip->toolTipText().contains(marker.label));
        QCOMPARE(otherStrip->toolTipPosition(), inputPoint);
        QVERIFY(toolTip->isVisible());
        const auto renderedText = [](QQuickItem &item) {
            for (QQuickItem *child : item.childItems())
                if (QByteArray(child->metaObject()->className()).contains("QQuickText"))
                    return child->property("text").toString();
            return QString();
        };
        QVERIFY(renderedText(*toolTip).contains(marker.label));
        const QPointF outside = root->property("rulerBandRect").toRectF().center();
        QMouseEvent leave(QEvent::MouseMove, outside, outside,
                          quick->quickWindow()->mapToGlobal(outside.toPoint()), Qt::NoButton,
                          Qt::NoButton, Qt::NoModifier);
        QCoreApplication::sendEvent(quick->quickWindow(), &leave);
        const auto hidden =
            checks::async_wait::waitUntil([] { return true; },
                                          [&] {
                                              return !otherStrip->toolTipVisible() &&
                                                     otherStrip->toolTipText().isEmpty() &&
                                                     !toolTip->isVisible();
                                          },
                                          1000);
        QCOMPARE(hidden, checks::async_wait::Result::Ready);
        settle();
        QVERIFY(!otherStrip->toolTipVisible() && otherStrip->toolTipText().isEmpty());
        QVERIFY(!toolTip->isVisible());
    }

    void loopMarkersReachTimelineButNotTheOtherEventsRaster()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        const auto geometry =
            view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
        QVERIFY(geometry.has_value());
        QString captureError;
        const QImage baseline =
            checks::support::captureQuickBand(view, geometry->rect, &captureError);
        QVERIFY2(!baseline.isNull(), qPrintable(captureError));
        host.document().setLoopTick(false, 6);
        host.document().setLoopTick(true, 18);
        std::unique_ptr<MidiTimeline> loopTimeline = host.document().buildTimeline(44100.0);
        QVERIFY(loopTimeline);
        QCOMPARE(loopTimeline->loopStartTick, uint64_t{6});
        QCOMPARE(loopTimeline->loopEndTick, uint64_t{18});
        view.updateSong(loopTimeline.get());
        settle();
        const auto updated =
            view.timelineBandLayout().geometry(songview::TimelineBand::OtherEvents);
        QVERIFY(updated.has_value());
        const QImage after = checks::support::captureQuickBand(view, updated->rect, &captureError);
        QVERIFY2(!after.isNull(), qPrintable(captureError));
        // The timeline fields above are primary; this raster comparison guards
        // the absence of loop-marker leakage into the Other Events strip.
        QCOMPARE(after, baseline);
        view.updateSong(&host.timeline());
    }
    void automationTempoRangeDelegatesTheSelectionScope()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        settle();
        auto *quick = view.quickView();
        auto *page = view.editorDrawer()->automationPage();
        QVERIFY(quick && page);
        auto *canvas = page->canvas();
        auto *input = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        auto *gutter = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationGutterInput"));
        QVERIFY(canvas && input && gutter);
        if (canvas->laneBody(LaneHandle{0}).isEmpty()) {
            const QPointF header(gutter->bounds().center().x(),
                                 canvas->pinnedTempoRect().center().y() - page->verticalScroll());
            checks::events::sendMouse(*gutter, QEvent::MouseButtonPress, header, Qt::LeftButton,
                                      Qt::LeftButton, Qt::NoModifier);
            checks::events::sendMouse(*gutter, QEvent::MouseButtonRelease, header, Qt::LeftButton,
                                      Qt::NoButton, Qt::NoModifier);
            settle();
        }
        const QRect tempo = canvas->laneBody(LaneHandle{0});
        QVERIFY(!tempo.isEmpty());
        const qreal y = tempo.center().y() - page->verticalScroll();
        const QPointF start(layout::space(layout::Space::One), y);
        const QPointF end = start + QPointF(layout::fontPx(12.0), 0.0);
        checks::events::sendMouse(*input, QEvent::MouseButtonPress, start, Qt::RightButton,
                                  Qt::RightButton, Qt::NoModifier);
        checks::events::sendMouse(*input, QEvent::MouseMove, end, Qt::NoButton, Qt::RightButton,
                                  Qt::NoModifier);
        checks::events::sendMouse(*input, QEvent::MouseButtonRelease, end, Qt::RightButton,
                                  Qt::NoButton, Qt::NoModifier);
        const auto selection = view.selectionModel().timeSelection();
        QVERIFY(selection.active());
        QCOMPARE(selection.scope, songview::EditorSelectionModel::TimeSelection::Lanes);
        QVERIFY(selection.tempo);
        QVERIFY(selection.lanes.empty());
    }

    void automationPanRoutesThroughQuickWindow()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerActivePage(EditorDrawerPage::Automations);
        settle();
        auto *quick = view.quickView();
        auto *automation = view.editorDrawer()->automationPage()->canvas();
        QVERIFY(quick && automation);
        auto *input = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineAutomationInput"));
        QVERIFY(input);
        const uint64_t revision = host.document().revision();
        const int undo = host.document().undoStack()->count();
        const QPointF point(input->width() / 2.0, input->height() / 2.0);
        const QPointF inWindow = input->mapToScene(point);
        QMouseEvent press(QEvent::MouseButtonPress, inWindow, inWindow, Qt::MiddleButton,
                          Qt::MiddleButton, Qt::NoModifier);
        QCoreApplication::sendEvent(quick->quickWindow(), &press);
        settle();
        QCOMPARE(view.focusedTimelineBand(),
                 std::optional<songview::TimelineBand>{songview::TimelineBand::Automation});
        QCOMPARE(quick->quickWindow()->mouseGrabberItem(), static_cast<QQuickItem *>(input));
        QVERIFY(automation->isPanning());
        QFocusEvent focusOut(QEvent::FocusOut, Qt::OtherFocusReason);
        QApplication::sendEvent(input, &focusOut);
        QVERIFY(automation->isPanning());
        QEvent deactivate(QEvent::WindowDeactivate);
        QApplication::sendEvent(quick->quickWindow(), &deactivate);
        QVERIFY(!automation->isPanning());
        QCOMPARE(host.document().revision(), revision);
        QCOMPARE(host.document().undoStack()->count(), undo);
    }

    void velocityVoiceRoutingUsesPresentationOnlyForSteadyContext()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *area = view.editorDrawer()->velocityArea();
        QVERIFY(area);
        view.selectionModel().clearNoteSelection();
        view.setEditCursorTick(0);
        QCOMPARE(QString::fromLatin1(area->axis().map().voiceName()), QStringLiteral("Square 1"));
        view.setPlayheadSample(host.timeline().sampleForTick(24), true);
        settle();
        QCOMPARE(QString::fromLatin1(area->axis().map().voiceName()), QStringLiteral("Noise"));
        const auto before = area->diagnostics();
        view.setPlayheadSample(host.timeline().sampleForTick(25), true);
        view.setPlayheadSample(host.timeline().sampleForTick(26), true);
        settle();
        QCOMPARE(area->diagnostics().contentBuildCount, before.contentBuildCount);
        QCOMPARE(area->diagnostics().playheadPresentationCount,
                 before.playheadPresentationCount + 2);
        view.setPlayheadSample(host.timeline().sampleForTick(26), false);
        settle();
        QCOMPARE(QString::fromLatin1(area->axis().map().voiceName()), QStringLiteral("Square 1"));
    }

    void drawerSoloAndTrackRemapReachTheHost()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        auto *velocity = quick->rootObject()->findChild<songview::TimelineInputItem *>(
            QStringLiteral("timelineVelocityInput"));
        QVERIFY(velocity);
        const int selectedTrack = view.selectionModel().primaryTrack();
        view.setTrackSolo(selectedTrack, false);
        QKeyEvent soloKey(QEvent::KeyPress, Qt::Key_S, Qt::NoModifier);
        QApplication::sendEvent(velocity, &soloKey);
        if (!soloKey.isAccepted())
            QApplication::sendEvent(&view, &soloKey);
        QVERIFY(view.trackSoloed(selectedTrack));
        view.setTrackSolo(selectedTrack, false);
        EditorViewState state = view.editorViewState();
        const EditorAutomationRowId oldLane{EditorAutomationRowKind::ControlChange, 0, 74};
        const EditorAutomationRowId movedLane{EditorAutomationRowKind::ControlChange, 1, 74};
        state.emptyLanes.insert(oldLane);
        view.applyEditorViewState(state);
        QVERIFY(host.document().moveTrack(0, 1));
        QVERIFY(view.editorViewState().emptyLanes.contains(movedLane));
        QVERIFY(!view.editorViewState().emptyLanes.contains(oldLane));
    }

    void voiceChangesRefreshWithoutInvalidatingAutomationRaster()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        view.setDrawerSectionVisible(EditorDrawerPage::Automations, true);
        view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
        view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
        settle();
        const auto automation =
            view.timelineBandLayout().geometry(songview::TimelineBand::Automation);
        const auto voice = view.timelineBandLayout().geometry(songview::TimelineBand::VoiceChanges);
        QVERIFY(automation.has_value());
        QVERIFY(voice.has_value());
        auto *automationArea = view.editorDrawer()->automationPage()->canvas();
        QVERIFY(automationArea);
        const auto automationRows = automationArea->rows();
        QString captureError;
        const QImage voiceBefore =
            checks::support::captureQuickBand(view, voice->rect, &captureError);
        QVERIFY2(!voiceBefore.isNull(), qPrintable(captureError));
        const QImage automationBefore =
            checks::support::captureQuickBand(view, automation->rect, &captureError);
        QVERIFY2(!automationBefore.isNull(), qPrintable(captureError));
        view.setPlayheadSample(host.timeline().sampleForTick(24), true);
        settle();
        QVERIFY(automationRowsEqual(automationArea->rows(), automationRows));
        const QImage voiceAfter =
            checks::support::captureQuickBand(view, voice->rect, &captureError);
        const QImage automationAfter =
            checks::support::captureQuickBand(view, automation->rect, &captureError);
        QVERIFY2(!voiceAfter.isNull() && !automationAfter.isNull(), qPrintable(captureError));
        QVERIFY(voiceAfter != voiceBefore);
        // The image check is a retained negative control. The primary
        // assertion above proves Automation's model did not rebuild.
        QCOMPARE(automationAfter, automationBefore);
    }

    void sharedPopupDiesOnHideAndReadinessReset()
    {
        SyntheticHost host;
        QString error;
        QVERIFY2(host.prepare(&error), qPrintable(error));
        SongView &view = host.view();
        auto *quick = view.quickView();
        QVERIFY(quick);
        QVERIFY(quick->quickWindow());
        auto *session = quick->popupSession();
        QVERIFY(session);
        QObject menuOwner;
        QVERIFY(session->beginMenu(&menuOwner));
        QVERIFY(session->isOpen());
        // Tab switches hide the embedded child while the top level stays
        // active, so Deactivate may never fire: Hide alone must dismiss.
        QEvent hide(QEvent::Hide);
        QCoreApplication::sendEvent(quick->quickWindow(), &hide);
        QVERIFY(!session->isOpen());
        // Readiness/document resets route through cancelTransientInput: any
        // surviving menu or form dies before the gate eats new input.
        QVERIFY(session->beginMenu(&menuOwner));
        QVERIFY(session->isOpen());
        view.cancelTransientInput();
        QVERIFY(!session->isOpen());
    }

  private:
    QString m_projectRoot;
    QString m_songLabel;
};
} // namespace
} // namespace checks::host

int runHostAdapterCheck(const QString &projectRoot, const QString &songLabel,
                        const QStringList &qtArguments)
{
    checks::host::HostAdapterTest test(projectRoot, songLabel);
    QStringList arguments{QStringLiteral("host-adapter")};
    arguments.append(qtArguments);
    return QTest::qExec(&test, arguments);
}

#include "tst_hostadapter.moc"
