#include <QCoreApplication>
#include <QDialog>
#include <QDialogButtonBox>
#include <QElapsedTimer>
#include <QImage>
#include <QLineEdit>
#include <QListWidget>
#include <QPixmap>
#include <QPushButton>
#include <QRegion>
#include <QThread>
#include <QTimer>
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
    const auto bands = view.timelineBands();
    if (!marker) {
        failures.append("playhead overlay child not found");
        return failures;
    }
    if (!events) {
        failures.append("EventListView child not found");
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
    rollcheck::rendering::processPaints();
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
        const QPoint voicePosition(row->width() / 2, 30);
        QTimer dialogPoll;
        dialogPoll.setInterval(0);
        bool pickerSeen = false;
        bool searchFilteredList = false;
        QObject::connect(&dialogPoll, &QTimer::timeout, [&] {
            auto *dialog = view.findChild<QDialog *>();
            if (!dialog)
                return;
            pickerSeen = true;
            auto *searchField = dialog->findChild<QLineEdit *>();
            auto *voiceList = dialog->findChild<QListWidget *>();
            auto *dialogButtons = dialog->findChild<QDialogButtonBox *>();
            if (searchField && voiceList && dialogButtons && voiceList->count() == 128) {
                searchField->setText(QStringLiteral("127  "));
                searchFilteredList =
                    voiceList->item(0)->isHidden() && !voiceList->item(127)->isHidden();
                searchField->clear();
                searchFilteredList &= !voiceList->item(0)->isHidden();
                voiceList->setCurrentRow(127);
                searchField->setText(QStringLiteral("1"));
                searchFilteredList &= voiceList->currentRow() == 1 &&
                                      !voiceList->item(1)->isHidden() &&
                                      !voiceList->item(127)->isHidden() &&
                                      dialogButtons->button(QDialogButtonBox::Ok)->isEnabled();
                searchField->clear();
                searchFilteredList &= voiceList->currentRow() == 0;
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
        if (!searchFilteredList)
            fail("voice picker search did not select and restore its first match");
        const auto *renameEditor = view.findChild<QLineEdit *>(QStringLiteral("trackRenameEditor"));
        if (renameEditor && !renameEditor->isHidden())
            fail("voice-line double-click opened the rename editor");
        if (document.undoStack()->count() != undoCommands)
            fail("voice picker navigation changed the undo stack");
    }

    view.close();
    processWindowEvents();
    if (failures == 0)
        std::fprintf(stderr, "rollwindowingcheck: PASS\n");
    return failures == 0 ? 0 : 1;
}
