#include <QApplication>
#include <QCheckBox>
#include <QCoreApplication>
#include <QDialog>
#include <QElapsedTimer>
#include <QImage>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPixmap>
#include <QPushButton>
#include <QRegion>
#include <QThread>
#include <QTimer>
#include <QToolButton>
#include <QWidget>
#include <QWindow>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <utility>

#include "checks/support/eventsynth.h"
#include "checks/support/songfixture.h"
#include "core/miditimeline.h"
#include "core/songdocument.h"
#include "rollcheckrendering.h"
#include "ui/editordrawer/editordrawer.h"
#include "ui/editordrawer/voicechangearea/voicechangearea.h"
#include "ui/eventlistview.h"
#include "ui/playheadoverlay.h"
#include "ui/songview.h"

namespace {

// Window visibility and modal transitions need every queued event processed.
void processWindowEvents()
{
    QCoreApplication::sendPostedEvents();
    QCoreApplication::processEvents();
}

bool waitForNativeWindowExposure(QWidget &widget)
{
    QElapsedTimer elapsed;
    elapsed.start();
    do {
        processWindowEvents();
        auto *window = widget.windowHandle();
        if (widget.isVisible() && window && window->isExposed())
            return true;
        QThread::msleep(10);
    } while (elapsed.elapsed() < 1000);
    return false;
}
QRect visibleTimelineBandRect(const songview::TimelineBand &band, QWidget &owner)
{
    const QWidget *surface = &band.widget;
    if (!surface->isVisibleTo(&owner) || band.timelineOrigin >= surface->width())
        return {};
    QRect visible(surface->mapTo(&owner, QPoint(band.timelineOrigin, 0)),
                  QSize(surface->width() - band.timelineOrigin, surface->height()));
    for (const QWidget *widget = surface; widget; widget = widget->parentWidget()) {
        if (!widget->isVisible())
            return {};
        visible &= QRect(widget->mapTo(&owner, QPoint()), widget->size());
        if (widget == &owner)
            break;
    }
    return visible;
}

QStringList eventListPlayheadCheckFailures(SongView &view, const MidiTimeline &timeline)
{
    auto failures = QStringList{};
    auto *marker = rollcheck::rendering::findPlayheadOverlay(view);
    auto *events = view.findChild<EventListView *>();
    auto *drawer = view.editorDrawer();
    auto *voiceChanges = drawer ? drawer->voiceChangeArea() : nullptr;
    const auto bands = view.timelineBands();
    if (!marker) {
        failures.append("playhead overlay child not found");
        return failures;
    }
    if (!events) {
        failures.append("EventListView child not found");
        return failures;
    }
    if (!voiceChanges) {
        failures.append("Voice Changes timeline band not found");
        return failures;
    }
    if (bands.empty()) {
        failures.append("time ruler band not found");
        return failures;
    }

    const auto centerTick =
        uint64_t(std::ceil(std::max(0.0, view.tickAtContentX(view.width() / 2))));
    view.setPlayheadSample(timeline.sampleForTick(centerTick), false);
    rollcheck::rendering::processPaints();

    constexpr QColor playheadColor(226, 66, 66);
    const QPixmap stoppedPixmap =
        rollcheck::rendering::grabPlayheadOverlay(view, *marker, failures);
    const qreal stoppedMarkerCenter =
        rollcheck::rendering::playheadCenter(stoppedPixmap, playheadColor);
    if (!marker->isVisible() || stoppedMarkerCenter < 0.0) {
        failures.append("stopped playhead did not render before switching to the event list");
        return failures;
    }

    const QPoint markerOffset = marker->mapTo(&view, QPoint());
    const qreal playheadXInView = markerOffset.x() + stoppedMarkerCenter;
    const QRect rulerArea(bands.front().widget.mapTo(&view, QPoint()), bands.front().widget.size());
    view.setEventListVisible(true);
    rollcheck::rendering::processPaints();

    const QRect eventListArea =
        QRect(events->mapTo(&view, QPoint()), events->size()).intersected(view.rect());
    const QPixmap overlayPixmap =
        rollcheck::rendering::grabPlayheadOverlay(view, *marker, failures);
    if (overlayPixmap.isNull()) {
        failures.append("event-list playhead overlay did not render");
    } else {
        const QImage overlayImage = overlayPixmap.toImage();
        const qreal overlayDpr = overlayPixmap.devicePixelRatio();
        if (!events->isVisible() || eventListArea.isEmpty()) {
            failures.append("event list is not visible for the playhead check");
        } else if (playheadXInView < eventListArea.left() ||
                   playheadXInView > eventListArea.right()) {
            failures.append("could not map playhead into the event list");
        } else {
            const QRect eventListOverlayArea = eventListArea.translated(-markerOffset);
            const int triangleHeight =
                std::min(songview::kPlayheadTriangleHeight + 1, eventListOverlayArea.height());
            const QRect triangleArea(eventListOverlayArea.left(), eventListOverlayArea.top(),
                                     eventListOverlayArea.width(), triangleHeight);
            const auto hasLine = [&](const QRect &area) {
                return rollcheck::rendering::hasPlayheadRedLine(
                    overlayImage, overlayDpr, stoppedMarkerCenter, area, playheadColor);
            };
            const auto redWidth = [&](int y) {
                return rollcheck::rendering::playheadRedWidth(
                    overlayImage, overlayDpr, stoppedMarkerCenter, y, playheadColor);
            };
            if (!hasLine(triangleArea))
                failures.append("playhead triangle did not render below the time ruler");
            if (redWidth(triangleArea.bottom() - 1) <= redWidth(triangleArea.top()))
                failures.append("playhead triangle did not point up in the event list");
            const QRect eventListBodyArea(
                eventListArea.left(), eventListArea.top() + triangleHeight, eventListArea.width(),
                eventListArea.height() - triangleHeight);
            QRegion visibleEventListBody(eventListBodyArea);
            for (const songview::TimelineBand &band : view.timelineBands())
                visibleEventListBody -= visibleTimelineBandRect(band, view);
            bool lineOverpainted = false;
            for (const QRect &visibleArea : visibleEventListBody) {
                const QRect overlayArea = visibleArea.translated(-markerOffset);
                if (stoppedMarkerCenter >= overlayArea.left() &&
                    stoppedMarkerCenter <= overlayArea.right() && hasLine(overlayArea)) {
                    lineOverpainted = true;
                    break;
                }
            }
            if (lineOverpainted)
                failures.append("playhead line overpainted the event list");
            if (hasLine(rulerArea.translated(-markerOffset)))
                failures.append("playhead rendered in the event-list time ruler");
            const QRect upperTimelineArea =
                QRect(0, 0, view.width(), eventListArea.top()).translated(-markerOffset);
            const QRect lowerTimelineArea = QRect(0, eventListArea.bottom() + 1, view.width(),
                                                  view.height() - eventListArea.bottom() - 1)
                                                .translated(-markerOffset);
            if (!hasLine(upperTimelineArea) && !hasLine(lowerTimelineArea)) {
                failures.append("playhead overlay did not render on visible timeline surfaces");
            }
        }
    }

    view.setEventListVisible(false);
    view.setDrawerSectionVisible(EditorDrawerPage::VoiceChanges, true);
    view.setDrawerActivePage(EditorDrawerPage::VoiceChanges);
    rollcheck::rendering::processPaints();

    const auto visibleBands = view.timelineBands();
    const auto voiceBand = std::find_if(visibleBands.cbegin(), visibleBands.cend(),
                                        [voiceChanges](const songview::TimelineBand &band) {
                                            return &band.widget == voiceChanges;
                                        });
    if (voiceBand == visibleBands.cend()) {
        failures.append("Voice Changes surface was omitted from the playhead overlay bands");
    } else {
        const QRect voiceArea = visibleTimelineBandRect(*voiceBand, view);
        const QPixmap voiceOverlay =
            rollcheck::rendering::grabPlayheadOverlay(view, *marker, failures);
        const qreal voicePlayheadCenter =
            rollcheck::rendering::playheadCenter(voiceOverlay, playheadColor);
        if (!voiceChanges->isVisible() || voiceArea.isEmpty()) {
            failures.append("Voice Changes timeline band did not become visible");
        } else if (voicePlayheadCenter < 0.0 ||
                   !rollcheck::rendering::hasPlayheadRedLine(
                       voiceOverlay.toImage(), voiceOverlay.devicePixelRatio(), voicePlayheadCenter,
                       voiceArea.translated(-marker->mapTo(&view, QPoint())), playheadColor)) {
            failures.append("playhead overlay did not render on the visible Voice Changes band");
        }
    }
    return failures;
}

} // namespace

int runRollWindowingCheck(const QString &projectRoot, const QString &songLabel)
{
    QString error;
    auto loadedSong = checks::LoadedSong::load(projectRoot, songLabel, error);
    if (!loadedSong) {
        std::fprintf(stderr, "rollwindowingcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    auto rig = checks::SongViewRig::create(std::move(loadedSong), 48000.0, error);
    if (!rig) {
        std::fprintf(stderr, "rollwindowingcheck: %s\n", qUtf8Printable(error));
        return 1;
    }
    SongDocument &document = rig->document();
    const MidiTimeline *timeline = &rig->timeline();
    SongView &view = rig->view();
    view.resize(1280, 800);
    view.show();
    processWindowEvents();

    int failures = 0;
    const auto fail = [&](const char *message) {
        std::fprintf(stderr, "rollwindowingcheck: FAIL %s: %s\n", qUtf8Printable(songLabel),
                     message);
        ++failures;
    };

    if (!waitForNativeWindowExposure(view))
        fail("SongView did not create an exposed native window");

    for (const QString &error : eventListPlayheadCheckFailures(view, *timeline))
        fail(qUtf8Printable(error));

    const int track = view.selectionModel().primaryTrack();
    auto *row = view.findChild<QWidget *>(QStringLiteral("trackHeaderRow%1").arg(track));
    if (!row) {
        fail("track header row for the selected track was not found");
    } else {
        const int undoCommands = document.undoStack()->count();
        const int undoIndex = document.undoStack()->index();
        const QPoint voicePosition(row->width() / 2, 30);
        QTimer dialogPoll;
        dialogPoll.setInterval(0);
        bool pickerSeen = false;
        bool pickerIsParentedUnderSongView = false;
        bool focusedVoiceList = false;
        bool pickerHasNoTextFilter = false;
        bool pickerHasExpectedFacets = false;
        bool pickerHasMatchingVoicesLabel = false;
        bool pickerHasClearFilters = false;
        QObject::connect(&dialogPoll, &QTimer::timeout, [&] {
            auto *dialog = qobject_cast<QDialog *>(QApplication::activeModalWidget());
            if (!dialog)
                return;
            pickerSeen = true;
            pickerIsParentedUnderSongView = dialog->parentWidget() == &view;
            auto *voiceList = dialog->findChild<QListWidget *>();
            focusedVoiceList =
                voiceList && voiceList->count() == 128 &&
                (dialog->focusWidget() == voiceList || QApplication::focusWidget() == voiceList);
            pickerHasNoTextFilter = !dialog->findChild<QLineEdit *>();
            bool allFamilies = false;
            for (QToolButton *button : dialog->findChildren<QToolButton *>()) {
                if (button->accessibleName() == QStringLiteral("All families")) {
                    allFamilies = true;
                    break;
                }
            }
            bool usedOnly = false;
            bool namedOnly = false;
            for (QCheckBox *box : dialog->findChildren<QCheckBox *>()) {
                if (box->text() == QStringLiteral("Used in this song"))
                    usedOnly = true;
                if (box->text() == QStringLiteral("Named voices only"))
                    namedOnly = true;
            }
            pickerHasExpectedFacets = allFamilies && usedOnly && namedOnly;
            for (QLabel *label : dialog->findChildren<QLabel *>()) {
                if (label->text().endsWith(QStringLiteral(" matching voices"))) {
                    pickerHasMatchingVoicesLabel = true;
                    break;
                }
            }
            for (QPushButton *button : dialog->findChildren<QPushButton *>()) {
                if (button->text() == QStringLiteral("Clear filters")) {
                    pickerHasClearFilters = true;
                    break;
                }
            }
            dialog->reject();
        });
        dialogPoll.start();
        checks::events::sendMouse(*row, QEvent::MouseButtonDblClick, QPointF(voicePosition),
                                  Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        checks::events::sendMouse(*row, QEvent::MouseButtonRelease, QPointF(voicePosition),
                                  Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
        processWindowEvents();
        dialogPoll.stop();

        if (!pickerSeen)
            fail("voice-line double-click did not open the voice picker");
        if (!pickerIsParentedUnderSongView)
            fail("voice picker was not parented under SongView");
        if (!focusedVoiceList)
            fail("voice picker did not expose a focused 128-slot list");
        if (!pickerHasNoTextFilter)
            fail("voice picker retained the removed text filter");
        if (!pickerHasExpectedFacets)
            fail("voice picker did not expose its expected facet controls");
        if (!pickerHasMatchingVoicesLabel)
            fail("voice picker did not expose its matching-voices label");
        if (!pickerHasClearFilters)
            fail("voice picker did not expose its Clear filters button");
        const auto *renameEditor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (renameEditor && !renameEditor->isHidden())
            fail("voice-line double-click opened the rename editor");
        if (document.undoStack()->count() != undoCommands ||
            document.undoStack()->index() != undoIndex)
            fail("rejecting voice picker changed undo history");
    }

    view.close();
    processWindowEvents();
    if (failures == 0)
        std::fprintf(stderr, "rollwindowingcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
